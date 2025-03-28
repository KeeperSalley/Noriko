import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'logger_service.dart';

// FFI typedefs for native function signatures
typedef GetDownloadedBytesNativeFunction = Int64 Function();
typedef GetDownloadedBytesDart = int Function();

typedef GetUploadedBytesNativeFunction = Int64 Function();
typedef GetUploadedBytesDart = int Function();

typedef GetConnectionSpeedNativeFunction = Int32 Function();
typedef GetConnectionSpeedDart = int Function();

class TrafficStats {
  final int downloadedBytes;
  final int uploadedBytes;
  final int speedKbps;
  final Duration connectionTime;

  TrafficStats({
    required this.downloadedBytes,
    required this.uploadedBytes,
    required this.speedKbps,
    required this.connectionTime,
  });

  // Helper methods to format traffic data
  String get formattedDownloaded => _formatBytes(downloadedBytes);
  String get formattedUploaded => _formatBytes(uploadedBytes);
  String get formattedSpeed => '$speedKbps KB/s';
  String get formattedConnectionTime => _formatDuration(connectionTime);

  // Format bytes to appropriate units (KB, MB, GB)
  static String _formatBytes(int bytes) {
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

  // Format duration to HH:MM:SS
  static String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }
}

class TrafficStatsService {
  // Singleton pattern
  static final TrafficStatsService _instance = TrafficStatsService._internal();
  factory TrafficStatsService() => _instance;
  TrafficStatsService._internal();

  // Native functions
  late GetDownloadedBytesDart _getDownloadedBytes;
  late GetUploadedBytesDart _getUploadedBytes;
  late GetConnectionSpeedDart _getConnectionSpeed;

  // Connection stats
  int _downloadedBytes = 0;
  int _uploadedBytes = 0;
  int _speedKbps = 0;
  DateTime? _connectionStartTime;
  Timer? _monitoringTimer;

  // Stream controller for traffic updates
  final _trafficStatsController = StreamController<TrafficStats>.broadcast();
  Stream<TrafficStats> get trafficStats => _trafficStatsController.stream;

  // Initialize with the native library
  void initialize(DynamicLibrary nativeLib) {
    try {
      LoggerService.info('Initializing Traffic Stats Service');
      
      // Bind FFI functions
      _getDownloadedBytes = nativeLib.lookupFunction<GetDownloadedBytesNativeFunction, GetDownloadedBytesDart>(
          'getDownloadedBytes');
      _getUploadedBytes = nativeLib.lookupFunction<GetUploadedBytesNativeFunction, GetUploadedBytesDart>(
          'getUploadedBytes');
      _getConnectionSpeed = nativeLib.lookupFunction<GetConnectionSpeedNativeFunction, GetConnectionSpeedDart>(
          'getConnectionSpeed');
      
      LoggerService.info('Traffic Stats Service initialized successfully');
    } catch (e) {
      LoggerService.error('Failed to initialize Traffic Stats Service', e);
    }
  }

  // For testing/development when native lib isn't available
  bool _useMockData = true;
  
  // Start monitoring traffic statistics
  void startMonitoring() {
    LoggerService.info('Starting traffic monitoring');
    
    // Reset stats
    _downloadedBytes = 0;
    _uploadedBytes = 0;
    _speedKbps = 0;
    _connectionStartTime = DateTime.now();
    
    // Stop existing timer if running
    _monitoringTimer?.cancel();
    
    // Start periodic monitoring
    _monitoringTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateStats();
    });
  }

  // Stop monitoring traffic
  void stopMonitoring() {
    LoggerService.info('Stopping traffic monitoring');
    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _connectionStartTime = null;
  }

  // Update traffic statistics
  void _updateStats() {
    try {
      if (_useMockData) {
        // Use mock data for testing
        _mockUpdateStats();
      } else {
        // Get stats from native code
        _downloadedBytes = _getDownloadedBytes();
        _uploadedBytes = _getUploadedBytes();
        _speedKbps = _getConnectionSpeed();
      }
      
      // Calculate connection time
      final connectionTime = _connectionStartTime != null
          ? DateTime.now().difference(_connectionStartTime!)
          : Duration.zero;
      
      // Emit updated stats
      _trafficStatsController.add(TrafficStats(
        downloadedBytes: _downloadedBytes,
        uploadedBytes: _uploadedBytes,
        speedKbps: _speedKbps,
        connectionTime: connectionTime,
      ));
    } catch (e) {
      LoggerService.error('Error updating traffic stats', e);
    }
  }

  // Simulate traffic stats for development/testing
  void _mockUpdateStats() {
    // Simulate increasing traffic
    _downloadedBytes += (100 + DateTime.now().millisecondsSinceEpoch % 5000).toInt();
    _uploadedBytes += (50 + DateTime.now().millisecondsSinceEpoch % 1000).toInt();
    _speedKbps = (50 + DateTime.now().millisecondsSinceEpoch % 950).toInt();
  }

  // Get current stats as a snapshot
  TrafficStats getCurrentStats() {
    final connectionTime = _connectionStartTime != null
        ? DateTime.now().difference(_connectionStartTime!)
        : Duration.zero;
    
    return TrafficStats(
      downloadedBytes: _downloadedBytes,
      uploadedBytes: _uploadedBytes,
      speedKbps: _speedKbps,
      connectionTime: connectionTime,
    );
  }

  // Cleanup resources
  void dispose() {
    stopMonitoring();
    _trafficStatsController.close();
  }
}