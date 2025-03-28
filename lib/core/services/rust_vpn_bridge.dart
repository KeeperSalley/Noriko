import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import '../constants/app_constants.dart';
import 'logger_service.dart';

// FFI typedefs for Rust function signatures
typedef InitializeRustFunction = Int32 Function(Pointer<Utf8> configPath);
typedef InitializeRustDart = int Function(Pointer<Utf8> configPath);

typedef StartVPNRustFunction = Int32 Function();
typedef StartVPNRustDart = int Function();

typedef StopVPNRustFunction = Int32 Function();
typedef StopVPNRustDart = int Function();

typedef CheckVPNStatusRustFunction = Int32 Function();
typedef CheckVPNStatusRustDart = int Function();

typedef GetDownloadedBytesRustFunction = Int64 Function();
typedef GetDownloadedBytesRustDart = int Function();

typedef GetUploadedBytesRustFunction = Int64 Function();
typedef GetUploadedBytesRustDart = int Function();

typedef GetPingRustFunction = Int32 Function();
typedef GetPingRustDart = int Function();

// Isolate function typedefs
typedef IsolateInitFunction = int Function(String);
typedef IsolateStartFunction = int Function();
typedef IsolateStopFunction = int Function();
typedef IsolateCheckStatusFunction = int Function();
typedef IsolateGetStatsFunction = Map<String, int> Function();

// Status codes that match the Rust implementation
class VPNStatus {
  static const int disconnected = 0;
  static const int connecting = 1;
  static const int connected = 2;
  static const int disconnecting = 3;
  static const int error = 4;
}

/// A bridge to the Rust-based native VPN implementation (for desktop platforms)
class RustVPNBridge {
  // Singleton pattern
  static final RustVPNBridge _instance = RustVPNBridge._internal();
  factory RustVPNBridge() => _instance;
  RustVPNBridge._internal();

  // Native library
  late DynamicLibrary _nativeLib;
  late InitializeRustDart _initializeVPN;
  late StartVPNRustDart _startVPN;
  late StopVPNRustDart _stopVPN;
  late CheckVPNStatusRustDart _checkStatus;
  late GetDownloadedBytesRustDart _getDownloadedBytes;
  late GetUploadedBytesRustDart _getUploadedBytes;
  late GetPingRustDart _getPing;

  // Isolate for running VPN operations
  Isolate? _vpnIsolate;
  ReceivePort? _receivePort;
  SendPort? _sendPort;
  Completer<SendPort>? _sendPortCompleter;

  // State
  bool _isInitialized = false;
  int _status = VPNStatus.disconnected;
  String? _configPath;
  
  // Stream controllers for state updates
  final _statusController = StreamController<int>.broadcast();
  Stream<int> get status => _statusController.stream;
  
  final _errorController = StreamController<String>.broadcast();
  Stream<String> get errors => _errorController.stream;
  
  // Initialize the Rust VPN bridge
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      LoggerService.info('Initializing Rust VPN Bridge');
      
      // Load the appropriate native library
      await _loadNativeLibrary();
      
      // Set up FFI functions
      _bindFunctions();
      
      // Start the VPN isolate
      await _startVPNIsolate();
      
      _isInitialized = true;
      _updateStatus(VPNStatus.disconnected);
      
      LoggerService.info('Rust VPN Bridge initialized successfully');
      return true;
    } catch (e) {
      LoggerService.error('Failed to initialize Rust VPN Bridge', e);
      _errorController.add('Failed to initialize VPN: ${e.toString()}');
      return false;
    }
  }

  // Load the appropriate native library
  Future<void> _loadNativeLibrary() async {
    String libName;
    
    if (Platform.isWindows) {
      libName = 'noriko_vpn.dll';
    } else if (Platform.isLinux) {
      libName = 'libnoriko_vpn.so';
    } else if (Platform.isMacOS) {
      libName = 'libnoriko_vpn.dylib';
    } else {
      throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
    }
    
    try {
      String libPath;
      
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
      
      LoggerService.info('Loading Rust native library from: $libPath');
      _nativeLib = DynamicLibrary.open(libPath);
    } catch (e) {
      LoggerService.error('Failed to load Rust native library', e);
      throw Exception('Failed to load Rust VPN library: ${e.toString()}');
    }
  }

  // Bind Rust FFI functions
  void _bindFunctions() {
    try {
      _initializeVPN = _nativeLib.lookupFunction<InitializeRustFunction, InitializeRustDart>('initialize_vpn');
      _startVPN = _nativeLib.lookupFunction<StartVPNRustFunction, StartVPNRustDart>('start_vpn');
      _stopVPN = _nativeLib.lookupFunction<StopVPNRustFunction, StopVPNRustDart>('stop_vpn');
      _checkStatus = _nativeLib.lookupFunction<CheckVPNStatusRustFunction, CheckVPNStatusRustDart>('check_vpn_status');
      _getDownloadedBytes = _nativeLib.lookupFunction<GetDownloadedBytesRustFunction, GetDownloadedBytesRustDart>('get_downloaded_bytes');
      _getUploadedBytes = _nativeLib.lookupFunction<GetUploadedBytesRustFunction, GetUploadedBytesRustDart>('get_uploaded_bytes');
      _getPing = _nativeLib.lookupFunction<GetPingRustFunction, GetPingRustDart>('get_ping');
    } catch (e) {
      LoggerService.error('Failed to bind Rust functions', e);
      throw Exception('Failed to bind Rust functions: ${e.toString()}');
    }
  }

  // Start the VPN isolate to avoid blocking the UI thread
  Future<void> _startVPNIsolate() async {
    LoggerService.info('Starting VPN isolate');
    
    // Create a receive port for communication
    _receivePort = ReceivePort();
    _sendPortCompleter = Completer<SendPort>();
    
    // Create the isolate
    _vpnIsolate = await Isolate.spawn(
      _vpnIsolateEntry,
      _receivePort!.sendPort,
    );
    
    // Listen for messages from the isolate
    _receivePort!.listen((message) {
      if (message is SendPort) {
        // Receive the send port from the isolate
        _sendPort = message;
        _sendPortCompleter!.complete(message);
      } else if (message is Map<String, dynamic>) {
        // Handle status updates
        if (message.containsKey('status')) {
          final status = message['status'] as int;
          _updateStatus(status);
        }
        
        // Handle errors
        if (message.containsKey('error')) {
          final error = message['error'] as String;
          _errorController.add(error);
        }
      }
    });
    
    // Wait for the send port
    _sendPort = await _sendPortCompleter!.future;
  }

  // Isolate entry point
  static void _vpnIsolateEntry(SendPort sendPort) {
    // Create a receive port for receiving messages
    final receivePort = ReceivePort();
    
    // Send the send port back to the main isolate
    sendPort.send(receivePort.sendPort);
    
    // Load the native library in this isolate
    DynamicLibrary? nativeLib;
    InitializeRustDart? initializeVPN;
    StartVPNRustDart? startVPN;
    StopVPNRustDart? stopVPN;
    CheckVPNStatusRustDart? checkStatus;
    GetDownloadedBytesRustDart? getDownloadedBytes;
    GetUploadedBytesRustDart? getUploadedBytes;
    GetPingRustDart? getPing;
    
    try {
      // Load the appropriate native library
      String libName;
      
      if (Platform.isWindows) {
        libName = 'noriko_vpn.dll';
      } else if (Platform.isLinux) {
        libName = 'libnoriko_vpn.so';
      } else if (Platform.isMacOS) {
        libName = 'libnoriko_vpn.dylib';
      } else {
        sendPort.send({'error': 'Unsupported platform: ${Platform.operatingSystem}'});
        return;
      }
      
      String libPath;
      
      if (Platform.isWindows || Platform.isLinux) {
        final exePath = Platform.resolvedExecutable;
        final exeDir = path.dirname(exePath);
        libPath = path.join(exeDir, 'lib', libName);
      } else if (Platform.isMacOS) {
        final exePath = Platform.resolvedExecutable;
        final appDir = path.dirname(path.dirname(path.dirname(exePath)));
        libPath = path.join(appDir, 'Frameworks', libName);
      } else {
        sendPort.send({'error': 'Unsupported platform: ${Platform.operatingSystem}'});
        return;
      }
      
      nativeLib = DynamicLibrary.open(libPath);
      
      // Bind functions
      initializeVPN = nativeLib.lookupFunction<InitializeRustFunction, InitializeRustDart>('initialize_vpn');
      startVPN = nativeLib.lookupFunction<StartVPNRustFunction, StartVPNRustDart>('start_vpn');
      stopVPN = nativeLib.lookupFunction<StopVPNRustFunction, StopVPNRustDart>('stop_vpn');
      checkStatus = nativeLib.lookupFunction<CheckVPNStatusRustFunction, CheckVPNStatusRustDart>('check_vpn_status');
      getDownloadedBytes = nativeLib.lookupFunction<GetDownloadedBytesRustFunction, GetDownloadedBytesRustDart>('get_downloaded_bytes');
      getUploadedBytes = nativeLib.lookupFunction<GetUploadedBytesRustFunction, GetUploadedBytesRustDart>('get_uploaded_bytes');
      getPing = nativeLib.lookupFunction<GetPingRustFunction, GetPingRustDart>('get_ping');
      
      sendPort.send({'status': VPNStatus.disconnected});
    } catch (e) {
      sendPort.send({'error': 'Failed to initialize VPN isolate: $e'});
      return;
    }
    
    // Listen for messages from the main isolate
    receivePort.listen((message) {
      if (message is Map<String, dynamic>) {
        if (message.containsKey('command')) {
          final command = message['command'] as String;
          
          switch (command) {
            case 'initialize':
              final configPath = message['configPath'] as String;
              _handleInitialize(sendPort, initializeVPN!, configPath);
              break;
            case 'start':
              _handleStart(sendPort, startVPN!);
              break;
            case 'stop':
              _handleStop(sendPort, stopVPN!);
              break;
            case 'check_status':
              _handleCheckStatus(sendPort, checkStatus!);
              break;
            case 'get_stats':
              _handleGetStats(sendPort, getDownloadedBytes!, getUploadedBytes!, getPing!);
              break;
          }
        }
      }
    });
  }

  // Handle initialize command in the isolate
  static void _handleInitialize(SendPort sendPort, InitializeRustDart initializeVPN, String configPath) {
    try {
      final configPathUtf8 = configPath.toNativeUtf8();
      final result = initializeVPN(configPathUtf8);
      malloc.free(configPathUtf8);
      
      if (result != 0) {
        sendPort.send({'error': 'Failed to initialize VPN with error code: $result'});
      } else {
        sendPort.send({'status': VPNStatus.disconnected});
      }
    } catch (e) {
      sendPort.send({'error': 'Error in initialize: $e'});
    }
  }

  // Handle start command in the isolate
  static void _handleStart(SendPort sendPort, StartVPNRustDart startVPN) {
    try {
      sendPort.send({'status': VPNStatus.connecting});
      
      final result = startVPN();
      
      if (result != 0) {
        sendPort.send({'error': 'Failed to start VPN with error code: $result'});
        sendPort.send({'status': VPNStatus.error});
      } else {
        sendPort.send({'status': VPNStatus.connected});
      }
    } catch (e) {
      sendPort.send({'error': 'Error in start: $e'});
      sendPort.send({'status': VPNStatus.error});
    }
  }

  // Handle stop command in the isolate
  static void _handleStop(SendPort sendPort, StopVPNRustDart stopVPN) {
    try {
      sendPort.send({'status': VPNStatus.disconnecting});
      
      final result = stopVPN();
      
      if (result != 0) {
        sendPort.send({'error': 'Failed to stop VPN with error code: $result'});
        sendPort.send({'status': VPNStatus.error});
      } else {
        sendPort.send({'status': VPNStatus.disconnected});
      }
    } catch (e) {
      sendPort.send({'error': 'Error in stop: $e'});
      sendPort.send({'status': VPNStatus.error});
    }
  }

  // Handle check status command in the isolate
  static void _handleCheckStatus(SendPort sendPort, CheckVPNStatusRustDart checkStatus) {
    try {
      final status = checkStatus();
      sendPort.send({'status': status});
    } catch (e) {
      sendPort.send({'error': 'Error in check status: $e'});
    }
  }

  // Handle get stats command in the isolate
  static void _handleGetStats(
    SendPort sendPort,
    GetDownloadedBytesRustDart getDownloadedBytes,
    GetUploadedBytesRustDart getUploadedBytes,
    GetPingRustDart getPing,
  ) {
    try {
      final downloadedBytes = getDownloadedBytes();
      final uploadedBytes = getUploadedBytes();
      final ping = getPing();
      
      sendPort.send({
        'stats': {
          'downloadedBytes': downloadedBytes,
          'uploadedBytes': uploadedBytes,
          'ping': ping,
        }
      });
    } catch (e) {
      sendPort.send({'error': 'Error in get stats: $e'});
    }
  }

  // Initialize the VPN with a configuration
  Future<bool> initializeVPN(String configPath) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }
    
    try {
      _configPath = configPath;
      
      // Send initialize command to the isolate
      _sendPort!.send({
        'command': 'initialize',
        'configPath': configPath,
      });
      
      return true;
    } catch (e) {
      LoggerService.error('Failed to initialize VPN', e);
      _errorController.add('Failed to initialize VPN: ${e.toString()}');
      return false;
    }
  }

  // Start the VPN
  Future<bool> start() async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }
    
    if (_configPath == null) {
      _errorController.add('VPN not initialized with configuration');
      return false;
    }
    
    try {
      // Send start command to the isolate
      _sendPort!.send({
        'command': 'start',
      });
      
      return true;
    } catch (e) {
      LoggerService.error('Failed to start VPN', e);
      _errorController.add('Failed to start VPN: ${e.toString()}');
      return false;
    }
  }

  // Stop the VPN
  Future<bool> stop() async {
    if (!_isInitialized) {
      return false;
    }
    
    try {
      // Send stop command to the isolate
      _sendPort!.send({
        'command': 'stop',
      });
      
      return true;
    } catch (e) {
      LoggerService.error('Failed to stop VPN', e);
      _errorController.add('Failed to stop VPN: ${e.toString()}');
      return false;
    }
  }

  // Check the VPN status
  Future<int> checkStatus() async {
    if (!_isInitialized) {
      return VPNStatus.disconnected;
    }
    
    try {
      // Create a completer to wait for the response
      final completer = Completer<int>();
      
      // Set up a listener for the status
      final subscription = status.listen((status) {
        if (!completer.isCompleted) {
          completer.complete(status);
        }
      });
      
      // Send check status command to the isolate
      _sendPort!.send({
        'command': 'check_status',
      });
      
      // Wait for the response with a timeout
      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => _status,
      );
      
      // Clean up
      await subscription.cancel();
      
      return result;
    } catch (e) {
      LoggerService.error('Failed to check VPN status', e);
      return _status;
    }
  }

  // Get traffic statistics
  Future<Map<String, int>> getStats() async {
    if (!_isInitialized) {
      return {
        'downloadedBytes': 0,
        'uploadedBytes': 0,
        'ping': 0,
      };
    }
    
    try {
      // Create a completer to wait for the response
      final completer = Completer<Map<String, int>>();
      
      // Set up a listener for the response
      StreamSubscription? subscription;
      subscription = _receivePort!.listen((message) {
        if (message is Map<String, dynamic> && message.containsKey('stats')) {
          final stats = message['stats'] as Map<String, dynamic>;
          completer.complete({
            'downloadedBytes': stats['downloadedBytes'] as int? ?? 0,
            'uploadedBytes': stats['uploadedBytes'] as int? ?? 0,
            'ping': stats['ping'] as int? ?? 0,
          });
          subscription?.cancel();
        }
      });
      
      // Send get stats command to the isolate
      _sendPort!.send({
        'command': 'get_stats',
      });
      
      // Wait for the response with a timeout
      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => {
          'downloadedBytes': 0,
          'uploadedBytes': 0,
          'ping': 0,
        },
      );
      
      // Clean up
      await subscription.cancel();
      
      return result;
    } catch (e) {
      LoggerService.error('Failed to get VPN stats', e);
      return {
        'downloadedBytes': 0,
        'uploadedBytes': 0,
        'ping': 0,
      };
    }
  }

  // Update the status and notify listeners
  void _updateStatus(int newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }

  // Clean up resources
  void dispose() {
    // Stop the VPN if it's running
    if (_status == VPNStatus.connected || _status == VPNStatus.connecting) {
      stop();
    }
    
    // Kill the isolate
    _vpnIsolate?.kill(priority: Isolate.immediate);
    _vpnIsolate = null;
    
    // Close ports
    _receivePort?.close();
    _receivePort = null;
    
    // Close controllers
    _statusController.close();
    _errorController.close();
    
    _isInitialized = false;
  }
}