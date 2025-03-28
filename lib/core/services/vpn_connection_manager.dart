import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

import '../../data/models/vpn_config.dart';
import '../constants/app_constants.dart';
import 'logger_service.dart';
import 'notification_service.dart';
import 'app_settings_service.dart';
import 'routing_service.dart';
import 'traffic_stats_service.dart';
import 'android_vpn_bridge.dart';
import 'rust_vpn_bridge.dart';
import 'windows_vpn_service.dart'; // Импортируем новый сервис для Windows

/// Status codes for VPN connection status
class VPNStatus {
  static const int disconnected = 0;
  static const int connecting = 1;
  static const int connected = 2;
  static const int disconnecting = 3;
  static const int error = 4;

  static String statusToString(int status) {
    switch (status) {
      case disconnected:
        return 'Disconnected';
      case connecting:
        return 'Connecting';
      case connected:
        return 'Connected';
      case disconnecting:
        return 'Disconnecting';
      case error:
        return 'Error';
      default:
        return 'Unknown';
    }
  }
}

/// The VPN connection manager that coordinates between platform-specific implementations
class VPNConnectionManager {
  // Singleton pattern
  static final VPNConnectionManager _instance = VPNConnectionManager._internal();
  factory VPNConnectionManager() => _instance;
  VPNConnectionManager._internal();

  // Platform-specific implementations
  final AndroidVPNBridge _androidBridge = AndroidVPNBridge();
  final RustVPNBridge _rustBridge = RustVPNBridge();
  final WindowsVpnService _windowsVpnService = WindowsVpnService(); // Добавляем Windows сервис
  
  // Services
  final TrafficStatsService _trafficStatsService = TrafficStatsService();
  final RoutingService _routingService = RoutingService();
  
  // Connection state
  bool _isInitialized = false;
  int _status = VPNStatus.disconnected;
  VpnConfig? _currentConfig;
  DateTime? _connectionStartTime;
  
  // Stream controllers for state updates
  final _statusController = StreamController<int>.broadcast();
  Stream<int> get connectionStatus => _statusController.stream;
  
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get connectionErrors => _errorController.stream;
  
  // Timer for checking connection status
  Timer? _statusCheckTimer;
  
  // Getters for service state
  bool get isConnected => _status == VPNStatus.connected;
  bool get isConnecting => _status == VPNStatus.connecting;
  bool get isDisconnecting => _status == VPNStatus.disconnecting;
  VpnConfig? get currentConfig => _currentConfig;
  int get status => _status;
  
  // Get connection time as duration
  Duration get connectionTime {
    if (_connectionStartTime == null || !isConnected) {
      return Duration.zero;
    }
    
    return DateTime.now().difference(_connectionStartTime!);
  }
  
  // Initialize the connection manager
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      LoggerService.info('Инициализация VPN Connection Manager');
      
      // Initialize routing service
      await _routingService.initialize();
      
      // Initialize platform-specific implementation
      if (Platform.isAndroid) {
        await _androidBridge.prepare();
        
        // Listen for status updates from Android bridge
        _androidBridge.status.listen(_updateStatus);
      } 
      else if (Platform.isWindows) {
        // Инициализация Windows-сервиса
        await _windowsVpnService.initialize();
      }
      else {
        await _rustBridge.initialize();
        
        // Listen for status updates from Rust bridge
        _rustBridge.status.listen(_updateStatus);
        _rustBridge.errors.listen(_errorController.add);
      }
      
      // Start status check timer
      _startStatusCheckTimer();
      
      _isInitialized = true;
      _updateStatus(VPNStatus.disconnected);
      
      LoggerService.info('VPN Connection Manager инициализирован успешно');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка инициализации VPN Connection Manager', e);
      _errorController.add('Ошибка инициализации VPN-сервиса: ${e.toString()}');
      return false;
    }
  }
  
  // Connect to a VPN server
  Future<bool> connect(VpnConfig config) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }
    
    if (isConnected || isConnecting) {
      LoggerService.warning('VPN уже подключен или подключается');
      return false;
    }
    
    try {
      _updateStatus(VPNStatus.connecting);
      _currentConfig = config;
      
      // Generate appropriate configuration file
      final configFile = await _generateConfigFile(config);
      if (configFile == null) {
        _updateStatus(VPNStatus.error);
        _errorController.add('Ошибка создания конфигурационного файла');
        return false;
      }
      
      LoggerService.info('Подключение к VPN-серверу: ${config.displayName}');
      
      bool result;
      
      // Use platform-specific implementation
      if (Platform.isAndroid) {
        // Convert config to Android-specific format
        final androidConfig = await _generateAndroidConfig(config);
        
        // Connect using Android bridge
        result = await _androidBridge.start(androidConfig);
      } 
      else if (Platform.isWindows) {
        // Connect using Windows VPN Service
        result = await _windowsVpnService.connect(config);
      }
      else {
        // Connect using Rust bridge
        result = await _rustBridge.initializeVPN(configFile);
        
        if (result) {
          result = await _rustBridge.start();
        }
      }
      
      if (result) {
        // Start tracking connection time
        _connectionStartTime = DateTime.now();
        
        // Save last connected server
        await AppSettingsService.saveLastServer(jsonEncode(config.toJson()));
        
        // Show notification
        await NotificationService.showConnectionNotification(config.displayName);
        
        LoggerService.info('VPN подключен успешно');
        return true;
      } else {
        _updateStatus(VPNStatus.error);
        _errorController.add('Ошибка подключения к VPN-серверу');
        return false;
      }
    } catch (e) {
      LoggerService.error('Ошибка подключения к VPN', e);
      _updateStatus(VPNStatus.error);
      _errorController.add('Ошибка подключения к VPN: ${e.toString()}');
      return false;
    }
  }
  
  // Disconnect from VPN
  Future<bool> disconnect() async {
    if (!_isInitialized) {
      return false;
    }
    
    if (!isConnected && !isConnecting) {
      LoggerService.warning('VPN не подключен и не подключается');
      return false;
    }
    
    try {
      _updateStatus(VPNStatus.disconnecting);
      LoggerService.info('Отключение от VPN');
      
      bool result;
      
      // Use platform-specific implementation
      if (Platform.isAndroid) {
        result = await _androidBridge.stop();
      } 
      else if (Platform.isWindows) {
        result = await _windowsVpnService.disconnect();
      }
      else {
        result = await _rustBridge.stop();
      }
      
      if (result) {
        // Reset connection time
        _connectionStartTime = null;
        
        // Show notification
        await NotificationService.showDisconnectionNotification();
        
        LoggerService.info('VPN отключен успешно');
        
        // Check status after short delay to ensure update
        Future.delayed(const Duration(milliseconds: 500), () async {
          await checkStatus();
        });
        
        return true;
      } else {
        _errorController.add('Ошибка отключения от VPN-сервера');
        return false;
      }
    } catch (e) {
      LoggerService.error('Ошибка отключения от VPN', e);
      _errorController.add('Ошибка отключения от VPN: ${e.toString()}');
      return false;
    }
  }
  
  // Check the VPN connection status
  Future<int> checkStatus() async {
    if (!_isInitialized) {
      return VPNStatus.disconnected;
    }
    
    try {
      int currentStatus;
      
      // Use platform-specific implementation
      if (Platform.isAndroid) {
        final isRunning = await _androidBridge.isRunning();
        currentStatus = isRunning ? VPNStatus.connected : VPNStatus.disconnected;
      } 
      else if (Platform.isWindows) {
        currentStatus = _windowsVpnService.isConnected() 
          ? VPNStatus.connected 
          : VPNStatus.disconnected;
      }
      else {
        currentStatus = await _rustBridge.checkStatus();
      }
      
      _updateStatus(currentStatus);
      return currentStatus;
    } catch (e) {
      LoggerService.error('Ошибка проверки статуса VPN', e);
      return _status;
    }
  }
  
  // Get traffic statistics
  Future<Map<String, dynamic>> getTrafficStats() async {
    try {
      if (!isConnected) {
        return {
          'downloadedBytes': 0,
          'uploadedBytes': 0,
          'connectionTime': connectionTime.inSeconds,
          'ping': 0,
        };
      }
      
      Map<String, dynamic> stats;
      
      // Use platform-specific implementation
      if (Platform.isAndroid) {
        stats = await _androidBridge.getTrafficStats();
      } 
      else if (Platform.isWindows) {
        stats = _windowsVpnService.getTrafficStats();
      }
      else {
        final rustStats = await _rustBridge.getStats();
        stats = {
          'downloadedBytes': rustStats['downloadedBytes'] ?? 0,
          'uploadedBytes': rustStats['uploadedBytes'] ?? 0,
          'ping': rustStats['ping'] ?? 0,
        };
      }
      
      // Add connection time
      stats['connectionTime'] = connectionTime.inSeconds;
      
      return stats;
    } catch (e) {
      LoggerService.error('Ошибка получения статистики трафика', e);
      return {
        'downloadedBytes': 0,
        'uploadedBytes': 0,
        'connectionTime': connectionTime.inSeconds,
        'ping': 0,
      };
    }
  }
  
  // Format bytes to appropriate units (KB, MB, GB)
  String formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
  
  // Format duration to hh:mm:ss
  String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
  
  // Start a timer to periodically check connection status
  void _startStatusCheckTimer() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      await checkStatus();
    });
  }
  
  // Update the status and notify listeners
  void _updateStatus(int newStatus) {
    if (_status != newStatus) {
      LoggerService.info('VPN Status изменился: ${VPNStatus.statusToString(_status)} -> ${VPNStatus.statusToString(newStatus)}');
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }
  
  // Generate configuration file for the VPN engine
  Future<String?> _generateConfigFile(VpnConfig config) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final configDir = path.join(appDir.path, AppConstants.configDir);
      
      // Create config directory if it doesn't exist
      final configDirObj = Directory(configDir);
      if (!await configDirObj.exists()) {
        await configDirObj.create(recursive: true);
      }
      
      final configFile = path.join(configDir, 'current_config.json');
      
      // Generate appropriate config based on protocol
      String jsonConfig;
      
      switch (config.protocol.toLowerCase()) {
        case 'vless':
          jsonConfig = await _generateV2RayConfig(config);
          break;
        case 'vmess':
          jsonConfig = await _generateV2RayConfig(config);
          break;
        case 'trojan':
          jsonConfig = await _generateTrojanConfig(config);
          break;
        case 'shadowsocks':
        case 'ss':
          jsonConfig = await _generateShadowsocksConfig(config);
          break;
        default:
          throw UnsupportedError('Неподдерживаемый протокол: ${config.protocol}');
      }
      
      // Write the configuration to file
      final file = File(configFile);
      await file.writeAsString(jsonConfig);
      
      LoggerService.info('Создан конфигурационный файл: $configFile');
      return configFile;
    } catch (e) {
      LoggerService.error('Ошибка создания конфигурационного файла', e);
      return null;
    }
  }
  
  // Generate configuration for Android VPN service
  Future<Map<String, dynamic>> _generateAndroidConfig(VpnConfig config) async {
    // Create generic config structure for Android
    final Map<String, dynamic> androidConfig = {
      'server': config.address,
      'port': config.port,
      'protocol': config.protocol.toLowerCase(),
      'id': config.id,
      'params': config.params,
      'tag': config.tag.isNotEmpty ? config.tag : config.displayName,
    };
    
    // Add routing configuration
    final routing = _routingService.currentProfile;
    androidConfig['routing'] = {
      'mode': routing.isSplitTunnelingEnabled
          ? (routing.isProxyOnlyEnabled ? 2 : 1)
          : 0,
      'rules': routing.rules.map((rule) => rule.toJson()).toList(),
    };
    
    return androidConfig;
  }
  
  // Generate V2Ray configuration (for VLESS and VMess)
  Future<String> _generateV2RayConfig(VpnConfig config) async {
    // Create base V2Ray config with improved UDP support
    final Map<String, dynamic> v2rayConfig = {
      "log": {
        "loglevel": "warning",
        "access": "access.log",
        "error": "error.log"
      },
      "inbounds": [
        {
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "settings": {
            "udp": true,
            "auth": "noauth"
          },
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"]
          },
          "tag": "socks-in"
        },
        {
          "port": 10809,
          "listen": "127.0.0.1",
          "protocol": "http",
          "settings": {},
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"]
          },
          "tag": "http-in"
        },
        {
          "port": 10810,
          "listen": "127.0.0.1",
          "protocol": "dokodemo-door",
          "settings": {
            "network": "udp",
            "followRedirect": true
          },
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"]
          },
          "tag": "udp-in"
        }
      ],
      "outbounds": [
        {
          "protocol": config.protocol.toLowerCase(),
          "settings": {
            "vnext": [
              {
                "address": config.address,
                "port": config.port,
                "users": [
                  {
                    "id": config.id,
                    "encryption": config.params["encryption"] ?? "none",
                    "flow": config.params["flow"] ?? "",
                    "security": config.params["security"] ?? "none"
                  }
                ]
              }
            ]
          },
          "streamSettings": {
            "network": config.params["type"] ?? "tcp",
            "security": config.params["security"] ?? "none",
            "tlsSettings": config.params["security"] == "tls" ? {
              "serverName": config.params["sni"] ?? config.address,
              "allowInsecure": config.params["allowInsecure"] == "true"
            } : null,
            "wsSettings": config.params["type"] == "ws" ? {
              "path": config.params["path"] ?? "/",
              "headers": {
                "Host": config.params["host"] ?? config.address
              }
            } : null,
            "tcpSettings": config.params["type"] == "tcp" ? {
              "header": {
                "type": "none"
              }
            } : null,
            "kcpSettings": config.params["type"] == "kcp" ? {
              "mtu": 1350,
              "tti": 50,
              "uplinkCapacity": 12,
              "downlinkCapacity": 100,
              "congestion": false,
              "readBufferSize": 2,
              "writeBufferSize": 2,
              "header": {
                "type": "none"
              }
            } : null,
            "grpcSettings": config.params["type"] == "grpc" ? {
              "serviceName": config.params["serviceName"] ?? "",
              "multiMode": config.params["multiMode"] == "true"
            } : null
          },
          "mux": {
            "enabled": true,
            "concurrency": 8
          },
          "tag": "proxy"
        },
        {
          "protocol": "freedom",
          "settings": {
            "domainStrategy": "UseIP", // Использовать IP для доменов
            "redirect": ":0",
            "userLevel": 0
          },
          "tag": "direct"
        },
        {
          "protocol": "blackhole",
          "settings": {},
          "tag": "block"
        }
      ],
      // Get routing config from routing service
      "routing": _routingService.generateV2RayRouting(),
      // Настройка DNS для предотвращения утечек
      "dns": {
        "servers": [
          "8.8.8.8",  // Google DNS через прокси
          "1.1.1.1",  // Cloudflare DNS через прокси
          {
            "address": "114.114.114.114",  // Китайский DNS напрямую 
            "port": 53,
            "domains": ["geosite:cn"]
          },
          "localhost"
        ],
        "tag": "dns-out"
      },
      // Дополнительные настройки для улучшения производительности
      "policy": {
        "levels": {
          "0": {
            "handshake": 4,
            "connIdle": 300,
            "uplinkOnly": 2,
            "downlinkOnly": 5,
            "statsUserUplink": false,
            "statsUserDownlink": false,
            "bufferSize": 10240
          }
        },
        "system": {
          "statsInboundUplink": false,
          "statsInboundDownlink": false,
          "statsOutboundUplink": false,
          "statsOutboundDownlink": false
        }
      }
    };
    
    // Проверяем, включена ли поддержка UDP в профиле
    if (!_routingService.currentProfile.udpSupport) {
      // Если UDP не поддерживается, удаляем UDP inbound
      v2rayConfig["inbounds"] = (v2rayConfig["inbounds"] as List)
          .where((inbound) => inbound["tag"] != "udp-in")
          .toList();
          
      // И отключаем UDP в socks
      for (var inbound in v2rayConfig["inbounds"]) {
        if (inbound["protocol"] == "socks" && inbound["settings"] != null) {
          inbound["settings"]["udp"] = false;
        }
      }
    }
    
    return jsonEncode(v2rayConfig);
  }
  
  // Generate Trojan configuration
  Future<String> _generateTrojanConfig(VpnConfig config) async {
    final Map<String, dynamic> trojanConfig = {
      "run_type": "client",
      "local_addr": "127.0.0.1",
      "local_port": 10808,
      "remote_addr": config.address,
      "remote_port": config.port,
      "password": [config.id],
      "log_level": 1,
      "ssl": {
        "verify": config.params["allowInsecure"] != "true",
        "verify_hostname": config.params["allowInsecure"] != "true",
        "sni": config.params["sni"] ?? config.address,
        "alpn": ["h2", "http/1.1"],
        "reuse_session": true,
        "session_ticket": false,
        "curves": ""
      },
      "tcp": {
        "no_delay": true,
        "keep_alive": true,
        "reuse_port": false,
        "fast_open": false,
        "fast_open_qlen": 20
      },
      "udp": {
        // Поддержка UDP для Trojan
        "enabled": _routingService.currentProfile.udpSupport,
        "timeout": 30,
        "prefer_ipv4": true
      },
      "routing": {
        // Include routing rules from the routing service
        "enabled": _routingService.currentProfile.isSplitTunnelingEnabled,
        "rules": _routingService.currentProfile.rules.map((rule) {
          return {
            "type": rule.type,
            "target": rule.value,
            "action": rule.action
          };
        }).toList(),
      }
    };
    
    return jsonEncode(trojanConfig);
  }
  
  // Generate Shadowsocks configuration
  Future<String> _generateShadowsocksConfig(VpnConfig config) async {
    // Extract the encryption method from params or use a default
    final method = config.params["method"] ?? "aes-256-gcm";
    
    final Map<String, dynamic> ssConfig = {
      "server": config.address,
      "server_port": config.port,
      "password": config.id,
      "method": method,
      "local_address": "127.0.0.1",
      "local_port": 10808,
      "timeout": 60,
      "fast_open": false,
      "reuse_port": false,
      "no_delay": true,
      "mode": _routingService.currentProfile.udpSupport ? "tcp_and_udp" : "tcp_only",
      // Add routing if supported by the Shadowsocks implementation
      "routing": {
        "enabled": _routingService.currentProfile.isSplitTunnelingEnabled,
        "bypass": _routingService.currentProfile.rules
          .where((rule) => rule.action == "direct")
          .map((rule) => rule.value)
          .toList(),
        "block": _routingService.currentProfile.rules
          .where((rule) => rule.action == "block")
          .map((rule) => rule.value)
          .toList(),
        "proxy": _routingService.currentProfile.rules
          .where((rule) => rule.action == "proxy")
          .map((rule) => rule.value)
          .toList(),
      }
    };
    
    return jsonEncode(ssConfig);
  }
  
  // Add an app to split tunneling (Android only)
  Future<bool> addAppToSplitTunnel(String packageName) async {
    if (!Platform.isAndroid) return false;
    
    try {
      return await _androidBridge.addAppToSplitTunnel(packageName);
    } catch (e) {
      LoggerService.error('Ошибка добавления приложения в split tunnel', e);
      return false;
    }
  }
  
  // Remove an app from split tunneling (Android only)
  Future<bool> removeAppFromSplitTunnel(String packageName) async {
    if (!Platform.isAndroid) return false;
    
    try {
      return await _androidBridge.removeAppFromSplitTunnel(packageName);
    } catch (e) {
      LoggerService.error('Ошибка удаления приложения из split tunnel', e);
      return false;
    }
  }
  
  // Get apps in split tunneling (Android only)
  Future<List<String>> getSplitTunnelApps() async {
    if (!Platform.isAndroid) return [];
    
    try {
      return await _androidBridge.getSplitTunnelApps();
    } catch (e) {
      LoggerService.error('Ошибка получения приложений split tunnel', e);
      return [];
    }
  }
  
  // Set split tunneling mode (Android only)
  Future<bool> setSplitTunnelMode(int mode) async {
    if (!Platform.isAndroid) return false;
    
    try {
      return await _androidBridge.setSplitTunnelMode(mode);
    } catch (e) {
      LoggerService.error('Ошибка установки режима split tunnel', e);
      return false;
    }
  }
  
  // Set current routing profile
  Future<bool> setRoutingProfile(String profileName) async {
    try {
      final result = await _routingService.setCurrentProfileByName(profileName);
      
      if (result && isConnected) {
        // If connected, reconnect to apply new routing
        final currentConfig = _currentConfig;
        if (currentConfig != null) {
          await disconnect();
          // Wait for disconnection to complete
          await Future.delayed(const Duration(milliseconds: 500));
          await connect(currentConfig);
        }
      }
      
      return result;
    } catch (e) {
      LoggerService.error('Ошибка установки профиля маршрутизации', e);
      return false;
    }
  }
  
  // Get current routing profile
  RoutingProfile getCurrentRoutingProfile() {
    return _routingService.currentProfile;
  }
  
  // Get all available routing profiles
  List<RoutingProfile> getRoutingProfiles() {
    return _routingService.savedProfiles;
  }
  
  // Toggle UDP support in the current profile
  Future<bool> toggleUdpSupport(bool enabled) async {
    try {
      final result = await _routingService.toggleUdpSupport(enabled);
      
      // Если мы подключены, то нужно переподключиться, чтобы применить настройки
      if (result && isConnected) {
        final currentConfig = _currentConfig;
        if (currentConfig != null) {
          await disconnect();
          // Wait for disconnection to complete
          await Future.delayed(const Duration(milliseconds: 500));
          await connect(currentConfig);
        }
      }
      
      return result;
    } catch (e) {
      LoggerService.error('Ошибка изменения поддержки UDP', e);
      return false;
    }
  }
  
  // Is UDP support enabled in the current profile
  bool isUdpSupportEnabled() {
    return _routingService.currentProfile.udpSupport;
  }
  
  // Clean up resources
  void dispose() {
    // Stop the status check timer
    _statusCheckTimer?.cancel();
    
    // Disconnect if connected
    if (isConnected || isConnecting) {
      disconnect();
    }
    
    // Clean up platform-specific implementations
    if (Platform.isAndroid) {
      _androidBridge.dispose();
    } else if (Platform.isWindows) {
      _windowsVpnService.dispose();
    } else {
      _rustBridge.dispose();
    }
    
    // Close stream controllers
    _statusController.close();
    _errorController.close();
    
    // Clean up services
    _routingService.dispose();
    
    _isInitialized = false;
  }
}