import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../data/models/vpn_config.dart';
import '../constants/app_constants.dart';
import 'logger_service.dart';
import 'traffic_stats_service.dart';
import 'notification_service.dart';

// FFI typedefs for native function signatures
typedef InitializeNativeFunction = Int32 Function(Pointer<Utf8> configPath);
typedef InitializeVPNDart = int Function(Pointer<Utf8> configPath);

typedef StartVPNNativeFunction = Int32 Function();
typedef StartVPNDart = int Function();

typedef StopVPNNativeFunction = Int32 Function();
typedef StopVPNDart = int Function();

typedef GetStatusNativeFunction = Int32 Function();
typedef GetStatusDart = int Function();

// Status codes that match the native code
class VPNStatus {
  static const int disconnected = 0;
  static const int connecting = 1;
  static const int connected = 2;
  static const int disconnecting = 3;
  static const int error = 4;
}

class VPNConnectionService {
  // Singleton pattern
  static final VPNConnectionService _instance = VPNConnectionService._internal();
  factory VPNConnectionService() => _instance;
  VPNConnectionService._internal();

  // Native library
  late DynamicLibrary _nativeLib;
  late InitializeVPNDart _initializeVPN;
  late StartVPNDart _startVPN;
  late StopVPNDart _stopVPN;
  late GetStatusDart _getStatus;

  // Connection state
  bool _isInitialized = false;
  int _status = VPNStatus.disconnected;
  VpnConfig? _currentConfig;
  
  // Stream controllers for state updates
  final _connectionStatusController = StreamController<int>.broadcast();
  Stream<int> get connectionStatus => _connectionStatusController.stream;
  
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get connectionErrors => _errorController.stream;
  
  // Getters for service state
  bool get isConnected => _status == VPNStatus.connected;
  bool get isConnecting => _status == VPNStatus.connecting;
  bool get isDisconnecting => _status == VPNStatus.disconnecting;
  VpnConfig? get currentConfig => _currentConfig;
  int get status => _status;

  // Initialize the VPN service
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      LoggerService.info('Initializing VPN Connection Service');
      
      // Load the appropriate native library based on platform
      await _loadNativeLibrary();
      
      // Set up FFI functions
      _initializeVPN = _nativeLib.lookupFunction<InitializeNativeFunction, InitializeVPNDart>('initializeVPN');
      _startVPN = _nativeLib.lookupFunction<StartVPNNativeFunction, StartVPNDart>('startVPN');
      _stopVPN = _nativeLib.lookupFunction<StopVPNNativeFunction, StopVPNDart>('stopVPN');
      _getStatus = _nativeLib.lookupFunction<GetStatusNativeFunction, GetStatusDart>('getStatus');
      
      // Initialize configuration directory
      final configDir = await _getConfigDirectory();
      await Directory(configDir).create(recursive: true);
      
      _isInitialized = true;
      _updateStatus(VPNStatus.disconnected);
      
      LoggerService.info('VPN Connection Service initialized successfully');
      return true;
    } catch (e) {
      LoggerService.error('Failed to initialize VPN Connection Service', e);
      _errorController.add('Failed to initialize VPN service: ${e.toString()}');
      return false;
    }
  }

  // Load the appropriate native library for the current platform
  Future<void> _loadNativeLibrary() async {
    String libName;
    
    if (Platform.isWindows) {
      libName = 'noriko_core.dll';
    } else if (Platform.isLinux) {
      libName = 'libnoriko_core.so';
    } else if (Platform.isMacOS) {
      libName = 'libnoriko_core.dylib';
    } else if (Platform.isAndroid) {
      libName = 'libnoriko_core.so';
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
    
    try {
      // Get the path to the library - this may vary based on how you bundle native libraries
      String libPath;
      
      if (Platform.isAndroid) {
        // Android loads from app's library path automatically
        _nativeLib = DynamicLibrary.open(libName);
        return;
      } else {
        // For desktop platforms, locate the library relative to the executable
        if (Platform.isWindows || Platform.isLinux) {
          final exePath = Platform.resolvedExecutable;
          final exeDir = path.dirname(exePath);
          libPath = path.join(exeDir, 'lib', libName);
        } else if (Platform.isMacOS) {
          final exePath = Platform.resolvedExecutable;
          final appDir = path.dirname(path.dirname(path.dirname(exePath)));
          libPath = path.join(appDir, 'Frameworks', libName);
        } else {
          throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
        }
      }
      
      LoggerService.info('Loading native library from: $libPath');
      _nativeLib = DynamicLibrary.open(libPath);
    } catch (e) {
      LoggerService.error('Failed to load native library', e);
      throw Exception('Failed to load native VPN library: ${e.toString()}');
    }
  }

  // Get the configuration directory path
  Future<String> _getConfigDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    return path.join(appDir.path, AppConstants.configDir);
  }

  // Connect to VPN with the specified configuration
  Future<bool> connect(VpnConfig config) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }
    
    if (isConnected || isConnecting) {
      LoggerService.warning('VPN is already connected or connecting');
      return false;
    }
    
    try {
      _updateStatus(VPNStatus.connecting);
      LoggerService.info('Connecting to VPN: ${config.displayName}');
      
      // Generate configuration file
      final configFile = await _generateConfigFile(config);
      if (configFile == null) {
        _updateStatus(VPNStatus.error);
        _errorController.add('Failed to generate configuration file');
        return false;
      }
      
      // Initialize VPN with the configuration
      final configPathUtf8 = configFile.toNativeUtf8();
      final initResult = _initializeVPN(configPathUtf8);
      malloc.free(configPathUtf8);
      
      if (initResult != 0) {
        _updateStatus(VPNStatus.error);
        _errorController.add('Failed to initialize VPN with error code: $initResult');
        return false;
      }
      
      // Start VPN connection
      final startResult = _startVPN();
      if (startResult != 0) {
        _updateStatus(VPNStatus.error);
        _errorController.add('Failed to start VPN with error code: $startResult');
        return false;
      }
      
      // Start monitoring connection status
      _startStatusMonitoring();
      
      // Store current configuration
      _currentConfig = config;
      
      // Show notification
      await NotificationService.showConnectionNotification(config.displayName);
      
      // Start traffic monitoring
      TrafficStatsService().startMonitoring();
      
      LoggerService.info('VPN Connected successfully');
      return true;
    } catch (e) {
      LoggerService.error('Failed to connect to VPN', e);
      _updateStatus(VPNStatus.error);
      _errorController.add('Failed to connect to VPN: ${e.toString()}');
      return false;
    }
  }

  // Disconnect from VPN
  Future<bool> disconnect() async {
    if (!_isInitialized) {
      return false;
    }
    
    if (!isConnected && !isConnecting) {
      LoggerService.warning('VPN is not connected or connecting');
      return false;
    }
    
    try {
      _updateStatus(VPNStatus.disconnecting);
      LoggerService.info('Disconnecting from VPN');
      
      // Stop VPN connection
      final stopResult = _stopVPN();
      if (stopResult != 0) {
        _updateStatus(VPNStatus.error);
        _errorController.add('Failed to stop VPN with error code: $stopResult');
        return false;
      }
      
      // Stop traffic monitoring
      TrafficStatsService().stopMonitoring();
      
      // Update status
      _updateStatus(VPNStatus.disconnected);
      
      // Show notification
      await NotificationService.showDisconnectionNotification();
      
      LoggerService.info('VPN Disconnected successfully');
      return true;
    } catch (e) {
      LoggerService.error('Failed to disconnect from VPN', e);
      _errorController.add('Failed to disconnect from VPN: ${e.toString()}');
      return false;
    }
  }

  // Get the current connection status
  Future<int> checkStatus() async {
    if (!_isInitialized) {
      return VPNStatus.disconnected;
    }
    
    try {
      final status = _getStatus();
      _updateStatus(status);
      return status;
    } catch (e) {
      LoggerService.error('Failed to get VPN status', e);
      return VPNStatus.error;
    }
  }

  // Update the connection status and notify listeners
  void _updateStatus(int newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      LoggerService.info('VPN Status updated to: $_getStatusString(newStatus)');
      _connectionStatusController.add(newStatus);
    }
  }

  // Start a timer to monitor the connection status
  void _startStatusMonitoring() {
    // Check status every 2 seconds
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      final status = await checkStatus();
      
      if (status == VPNStatus.disconnected || status == VPNStatus.error) {
        timer.cancel();
      }
    });
  }

  // Generate a configuration file for the VPN engine
  Future<String?> _generateConfigFile(VpnConfig config) async {
    try {
      final configDir = await _getConfigDirectory();
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
          throw UnsupportedError('Unsupported protocol: ${config.protocol}');
      }
      
      // Write the configuration to file
      final file = File(configFile);
      await file.writeAsString(jsonConfig);
      
      LoggerService.info('Generated configuration file: $configFile');
      return configFile;
    } catch (e) {
      LoggerService.error('Failed to generate configuration file', e);
      return null;
    }
  }

  // Generate V2Ray configuration (for VLESS and VMess)
  Future<String> _generateV2RayConfig(VpnConfig config) async {
    final Map<String, dynamic> v2rayConfig = {
      "log": {
        "loglevel": "warning"
      },
      "inbounds": [
        {
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "settings": {
            "udp": true
          }
        },
        {
          "port": 10809,
          "listen": "127.0.0.1",
          "protocol": "http"
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
            } : null
          },
          "tag": "proxy"
        },
        {
          "protocol": "freedom",
          "settings": {},
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
      }
    };
    
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
      "mode": "tcp_and_udp"
    };
    
    return jsonEncode(ssConfig);
  }

  // Convert status code to string for logging
  String _getStatusString(int status) {
    switch (status) {
      case VPNStatus.disconnected:
        return 'Disconnected';
      case VPNStatus.connecting:
        return 'Connecting';
      case VPNStatus.connected:
        return 'Connected';
      case VPNStatus.disconnecting:
        return 'Disconnecting';
      case VPNStatus.error:
        return 'Error';
      default:
        return 'Unknown';
    }
  }

  // Cleanup resources
  void dispose() {
    _connectionStatusController.close();
    _errorController.close();
    
    // Stop traffic monitoring
    TrafficStatsService().stopMonitoring();
    
    // Ensure VPN is stopped
    if (isConnected || isConnecting) {
      disconnect();
    }
  }
}