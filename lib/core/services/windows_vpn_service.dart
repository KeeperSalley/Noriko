import 'dart:async';
import 'dart:io';
import 'dart:ffi';
import 'dart:convert';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../data/models/vpn_config.dart';
import '../constants/app_constants.dart';
import 'logger_service.dart';

// Коды состояния VPN
class VPNStatus {
  static const int disconnected = 0;
  static const int connecting = 1;
  static const int connected = 2;
  static const int disconnecting = 3;
  static const int error = 4;
}

class WindowsVpnService {
  // Singleton pattern
  static final WindowsVpnService _instance = WindowsVpnService._internal();
  factory WindowsVpnService() => _instance;
  WindowsVpnService._internal();

  // DLL handle
  late DynamicLibrary _proxyHelper;
  
  // Function pointers to native methods
  late int Function() _initializeProxy;
  late int Function(Pointer<Utf8>) _setupProxy;
  late int Function() _disableProxy;
  late int Function(Pointer<Int64>, Pointer<Int64>, Pointer<Int32>) _getStatistics;

  bool _isInitialized = false;
  bool _isConnected = false;
  
  // List of VPN process IDs
  final List<int> _vpnProcessIds = [];
  
  // Statistics tracking
  Timer? _statsTimer;
  int _downloadedBytes = 0;
  int _uploadedBytes = 0;
  int _ping = 0;
  
  // Initialize the service
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      LoggerService.info('Инициализация Windows VPN Service');
      
      // Load proxy helper DLL
      await _loadProxyHelper();
      
      // Initialize the proxy module
      final initResult = _initializeProxy();
      if (initResult != 1) {
        LoggerService.error('Ошибка инициализации прокси модуля: $initResult');
        return false;
      }
      
      _isInitialized = true;
      LoggerService.info('Windows VPN Service инициализирован успешно');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка инициализации Windows VPN Service', e);
      return false;
    }
  }
  
  // Load proxy helper DLL
  Future<void> _loadProxyHelper() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final dllPath = path.join(exeDir, 'windows_proxy_helper.dll');
      
      LoggerService.info('Загрузка proxy helper из: $dllPath');
      
      if (!File(dllPath).existsSync()) {
        throw Exception('Прокси помощник DLL не найден: $dllPath');
      }
      
      _proxyHelper = DynamicLibrary.open(dllPath);
      
      // Bind native functions from DLL
      _initializeProxy = _proxyHelper
          .lookupFunction<Int32 Function(), int Function()>('InitializeProxy');
      
      _setupProxy = _proxyHelper
          .lookupFunction<Int32 Function(Pointer<Utf8>),
              int Function(Pointer<Utf8>)>('SetupProxy');
      
      _disableProxy = _proxyHelper
          .lookupFunction<Int32 Function(), int Function()>('DisableProxy');
      
      _getStatistics = _proxyHelper
          .lookupFunction<Int32 Function(Pointer<Int64>, Pointer<Int64>, Pointer<Int32>),
              int Function(Pointer<Int64>, Pointer<Int64>, Pointer<Int32>)>('GetStatistics');
      
      LoggerService.info('Прокси помощник загружен успешно');
    } catch (e) {
      LoggerService.error('Ошибка загрузки прокси помощника', e);
      throw Exception('Не удалось загрузить прокси помощник: $e');
    }
  }
  
  // Connect to VPN with the specified configuration
  Future<bool> connect(VpnConfig config) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }
    
    if (_isConnected) {
      LoggerService.warning('VPN уже подключен');
      return true;
    }
    
    try {
      LoggerService.info('Подключение к VPN серверу: ${config.displayName}');
      
      // Generate configuration file for the proxy protocol
      final configFile = await _generateConfigFile(config);
      
      // Start the appropriate client based on protocol
      bool clientStarted = false;
      
      switch (config.protocol.toLowerCase()) {
        case 'vless':
        case 'vmess':
          clientStarted = await _startV2Ray(configFile);
          break;
        case 'trojan':
          clientStarted = await _startTrojan(configFile);
          break;
        case 'shadowsocks':
        case 'ss':
          clientStarted = await _startShadowsocks(configFile);
          break;
        default:
          throw Exception('Неподдерживаемый протокол: ${config.protocol}');
      }
      
      if (!clientStarted) {
        throw Exception('Не удалось запустить VPN клиент');
      }
      
      // Wait for the proxy service to start
      await Future.delayed(const Duration(seconds: 1));
      
      // Setup system proxy to use our local SOCKS proxy
      final socksPortPtr = '10808'.toNativeUtf8(); // Standard Socks port used by proxies
      
      final proxyResult = _setupProxy(socksPortPtr);
      
      malloc.free(socksPortPtr);
      
      if (proxyResult != 1) {
        throw Exception('Не удалось настроить системный прокси: $proxyResult');
      }
      
      // Start statistics collection
      _startStatsCollection();
      
      _isConnected = true;
      LoggerService.info('VPN подключен успешно');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка подключения к VPN', e);
      // Clean up in case of error
      await _cleanupOnError();
      return false;
    }
  }
  
  // Generate configuration file for the proxy protocol
  Future<String> _generateConfigFile(VpnConfig config) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final configDir = path.join(appDir.path, AppConstants.configDir);
      
      // Create config directory if it doesn't exist
      await Directory(configDir).create(recursive: true);
      
      final configFile = path.join(configDir, 'current_config.json');
      
      // Generate the appropriate config based on protocol
      String jsonConfig;
      
      switch (config.protocol.toLowerCase()) {
        case 'vless':
        case 'vmess':
          jsonConfig = _generateV2RayConfig(config);
          break;
        case 'trojan':
          jsonConfig = _generateTrojanConfig(config);
          break;
        case 'shadowsocks':
        case 'ss':
          jsonConfig = _generateShadowsocksConfig(config);
          break;
        default:
          throw Exception('Неподдерживаемый протокол: ${config.protocol}');
      }
      
      // Write the configuration to file
      await File(configFile).writeAsString(jsonConfig);
      
      LoggerService.info('Конфигурационный файл создан: $configFile');
      return configFile;
    } catch (e) {
      LoggerService.error('Ошибка создания конфигурационного файла', e);
      throw Exception('Не удалось создать конфигурационный файл: $e');
    }
  }
  
  // Generate V2Ray configuration
  String _generateV2RayConfig(VpnConfig config) {
    // Create optimized V2Ray config with improved privacy and performance
    final Map<String, dynamic> v2rayConfig = {
      "log": {
        "loglevel": "warning",
        "access": path.join(Directory.systemTemp.path, "v2ray_access.log"),
        "error": path.join(Directory.systemTemp.path, "v2ray_error.log")
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
            "domainStrategy": "UseIP"
          },
          "tag": "direct"
        },
        {
          "protocol": "blackhole",
          "settings": {},
          "tag": "block"
        }
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
          {
            "type": "field",
            "ip": ["geoip:private"],
            "outboundTag": "direct"
          },
          {
            "type": "field",
            "domain": ["geosite:category-ads"],
            "outboundTag": "block"
          }
        ]
      },
      "dns": {
        "servers": [
          "8.8.8.8",
          "1.1.1.1",
          "localhost"
        ]
      }
    };
    
    return jsonEncode(v2rayConfig);
  }
  
  // Generate Trojan configuration
  String _generateTrojanConfig(VpnConfig config) {
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
        "enabled": config.params.containsKey('enableUdp') ? config.params["enableUdp"] == "true" : true,
        "timeout": 30,
        "prefer_ipv4": true
      }
    };
    
    return jsonEncode(trojanConfig);
  }
  
  // Generate Shadowsocks configuration
  String _generateShadowsocksConfig(VpnConfig config) {
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
      "mode": config.params.containsKey('enableUdp') && config.params["enableUdp"] == "false" 
          ? "tcp_only" 
          : "tcp_and_udp"
    };
    
    return jsonEncode(ssConfig);
  }
  
  // Start V2Ray process
  Future<bool> _startV2Ray(String configFile) async {
    try {
      // Path to V2Ray executable
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final v2rayPath = path.join(exeDir, 'bin', 'v2ray', 'v2ray.exe');
      
      // Check if the executable exists
      if (!File(v2rayPath).existsSync()) {
        throw Exception('V2Ray исполняемый файл не найден: $v2rayPath');
      }
      
      // Start the process
      final process = await Process.start(
        v2rayPath,
        ['-config', configFile],
        mode: ProcessStartMode.detached
      );
      
      // Save the PID for later termination
      _vpnProcessIds.add(process.pid);
      
      LoggerService.info('V2Ray запущен с PID: ${process.pid}');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка запуска V2Ray', e);
      return false;
    }
  }
  
  // Start Trojan process
  Future<bool> _startTrojan(String configFile) async {
    try {
      // Path to Trojan executable
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final trojanPath = path.join(exeDir, 'bin', 'trojan', 'trojan.exe');
      
      // Check if the executable exists
      if (!File(trojanPath).existsSync()) {
        throw Exception('Trojan исполняемый файл не найден: $trojanPath');
      }
      
      // Start the process
      final process = await Process.start(
        trojanPath,
        ['-c', configFile],
        mode: ProcessStartMode.detached
      );
      
      // Save the PID for later termination
      _vpnProcessIds.add(process.pid);
      
      LoggerService.info('Trojan запущен с PID: ${process.pid}');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка запуска Trojan', e);
      return false;
    }
  }
  
  // Start Shadowsocks process
  Future<bool> _startShadowsocks(String configFile) async {
    try {
      // Path to Shadowsocks executable
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final ssPath = path.join(exeDir, 'bin', 'shadowsocks', 'sslocal.exe');
      
      // Check if the executable exists
      if (!File(ssPath).existsSync()) {
        throw Exception('Shadowsocks исполняемый файл не найден: $ssPath');
      }
      
      // Start the process
      final process = await Process.start(
        ssPath,
        ['-c', configFile],
        mode: ProcessStartMode.detached
      );
      
      // Save the PID for later termination
      _vpnProcessIds.add(process.pid);
      
      LoggerService.info('Shadowsocks запущен с PID: ${process.pid}');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка запуска Shadowsocks', e);
      return false;
    }
  }
  
  // Start collecting traffic statistics
  void _startStatsCollection() {
    _statsTimer?.cancel();
    
    // Reset statistics
    _downloadedBytes = 0;
    _uploadedBytes = 0;
    _ping = 0;
    
    // Start a timer to update statistics every second
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Allocate memory for statistics
      final downloadedPtr = calloc<Int64>();
      final uploadedPtr = calloc<Int64>();
      final pingPtr = calloc<Int32>();
      
      try {
        // Get current statistics from library
        final result = _getStatistics(downloadedPtr, uploadedPtr, pingPtr);
        
        if (result == 1) {
          // Update statistics values
          _downloadedBytes = downloadedPtr.value;
          _uploadedBytes = uploadedPtr.value;
          _ping = pingPtr.value;
        }
      } catch (e) {
        LoggerService.error('Ошибка получения статистики трафика', e);
      } finally {
        // Free allocated memory
        calloc.free(downloadedPtr);
        calloc.free(uploadedPtr);
        calloc.free(pingPtr);
      }
    });
  }
  
  // Stop collecting statistics
  void _stopStatsCollection() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }
  
  // Disconnect from VPN
  Future<bool> disconnect() async {
    if (!_isConnected) {
      return true;
    }
    
    try {
      LoggerService.info('Отключение от VPN');
      
      // Stop statistics collection
      _stopStatsCollection();
      
      // Disable system proxy
      final disableResult = _disableProxy();
      if (disableResult != 1) {
        LoggerService.error('Ошибка отключения системного прокси: $disableResult');
      }
      
      // Terminate all VPN processes
      for (final pid in _vpnProcessIds) {
        try {
          await Process.run('taskkill', ['/F', '/PID', '$pid']);
          LoggerService.info('Процесс с PID $pid завершен');
        } catch (e) {
          LoggerService.error('Ошибка завершения процесса с PID $pid', e);
        }
      }
      
      // Clear the process list
      _vpnProcessIds.clear();
      
      _isConnected = false;
      LoggerService.info('VPN отключен успешно');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка отключения от VPN', e);
      return false;
    }
  }
  
  // Clean up resources on error
  Future<void> _cleanupOnError() async {
    try {
      // Stop all processes
      for (final pid in _vpnProcessIds) {
        try {
          await Process.run('taskkill', ['/F', '/PID', '$pid']);
        } catch (e) {
          // Ignore errors during cleanup
        }
      }
      
      // Clear the process list
      _vpnProcessIds.clear();
      
      // Try to disable proxy
      try {
        _disableProxy();
      } catch (e) {
        // Ignore errors during cleanup
      }
      
      // Stop statistics collection
      _stopStatsCollection();
    } catch (e) {
      // Ignore any errors in cleanup
    }
  }
  
  // Check if VPN is connected
  bool isConnected() {
    return _isConnected;
  }
  
  // Get traffic statistics
  Map<String, dynamic> getTrafficStats() {
    return {
      'downloadedBytes': _downloadedBytes,
      'uploadedBytes': _uploadedBytes,
      'ping': _ping,
    };
  }
  
  // Clean up resources
  void dispose() {
    // Disconnect if connected
    if (_isConnected) {
      disconnect();
    }
    
    // Stop statistics timer
    _stopStatsCollection();
  }
}