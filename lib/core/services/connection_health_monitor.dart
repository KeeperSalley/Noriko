import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

import 'logger_service.dart';
import 'notification_service.dart';
import 'vpn_connection_manager.dart';

/// Health check status
class HealthStatus {
  final bool isHealthy;
  final String message;
  final int latency;
  final bool isConnected;
  final bool hasInternet;
  final bool hasLeaks;
  final List<String> leakDetails;

  HealthStatus({
    required this.isHealthy,
    required this.message,
    required this.latency,
    required this.isConnected,
    required this.hasInternet,
    this.hasLeaks = false,
    this.leakDetails = const [],
  });

  @override
  String toString() {
    return 'HealthStatus(isHealthy: $isHealthy, message: $message, latency: $latency ms, isConnected: $isConnected, hasInternet: $hasInternet, hasLeaks: $hasLeaks)';
  }
}

/// A service for monitoring VPN connection health
class ConnectionHealthMonitor {
  // Singleton pattern
  static final ConnectionHealthMonitor _instance = ConnectionHealthMonitor._internal();
  factory ConnectionHealthMonitor() => _instance;
  ConnectionHealthMonitor._internal();

  // Connection manager
  final VPNConnectionManager _connectionManager = VPNConnectionManager();
  
  // Connectivity checker
  final Connectivity _connectivity = Connectivity();
  
  // Health check configuration
  static const int _checkIntervalSeconds = 30;
  static const int _maxPing = 500; // ms
  static const int _pingTimeout = 5000; // ms
  static const List<String> _healthCheckUrls = [
    'https://www.google.com',
    'https://www.cloudflare.com',
    'https://www.apple.com',
  ];
  
  // For DNS leak test
  static const List<String> _dnsLeakCheckServers = [
    'https://dnsleaktest.com/api/v1/standard-test',
    'https://www.dnsleaktest.com/api/v1/standard-test',
  ];
  
  // Timer for health checks
  Timer? _healthCheckTimer;
  
  // Latest health status
  HealthStatus? _lastStatus;
  
  // Stream controllers for health updates
  final _healthStatusController = StreamController<HealthStatus>.broadcast();
  Stream<HealthStatus> get healthStatus => _healthStatusController.stream;
  
  // Getters
  HealthStatus? get lastStatus => _lastStatus;
  bool get isMonitoring => _healthCheckTimer != null && _healthCheckTimer!.isActive;
  
  // Start health monitoring
  void startMonitoring() {
    if (isMonitoring) return;
    
    LoggerService.info('Starting connection health monitoring');
    
    // Run an immediate check
    checkHealth();
    
    // Start periodic checks
    _healthCheckTimer = Timer.periodic(
      const Duration(seconds: _checkIntervalSeconds),
      (_) => checkHealth(),
    );
  }
  
  // Stop health monitoring
  void stopMonitoring() {
    LoggerService.info('Stopping connection health monitoring');
    
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }
  
  // Perform a health check
  Future<HealthStatus> checkHealth() async {
    LoggerService.info('Performing connection health check');
    
    HealthStatus status;
    
    try {
      // Check if VPN is connected
      final isConnected = _connectionManager.isConnected;
      
      // Check if device has internet connectivity
      final connectivityResult = await _connectivity.checkConnectivity();
      final hasInternet = connectivityResult != ConnectivityResult.none;
      
      if (!hasInternet) {
        status = HealthStatus(
          isHealthy: false,
          message: 'No internet connection',
          latency: -1,
          isConnected: isConnected,
          hasInternet: false,
        );
      } else if (!isConnected) {
        status = HealthStatus(
          isHealthy: true,
          message: 'VPN not connected',
          latency: -1,
          isConnected: false,
          hasInternet: true,
        );
      } else {
        // Measure latency to health check servers
        final latencies = await _measureLatencies();
        
        // Calculate average latency (excluding timeouts)
        final validLatencies = latencies.where((l) => l > 0).toList();
        final avgLatency = validLatencies.isEmpty
            ? -1
            : validLatencies.reduce((a, b) => a + b) ~/ validLatencies.length;
        
        // Check for DNS leaks if VPN is connected
        final leakCheck = await _checkForDnsLeaks();
        
        if (avgLatency == -1 || validLatencies.isEmpty) {
          status = HealthStatus(
            isHealthy: false,
            message: 'Connection timeout',
            latency: -1,
            isConnected: true,
            hasInternet: false,
            hasLeaks: leakCheck.item1,
            leakDetails: leakCheck.item2,
          );
        } else if (avgLatency > _maxPing) {
          status = HealthStatus(
            isHealthy: false,
            message: 'High latency: $avgLatency ms',
            latency: avgLatency,
            isConnected: true,
            hasInternet: true,
            hasLeaks: leakCheck.item1,
            leakDetails: leakCheck.item2,
          );
        } else if (leakCheck.item1) {
          status = HealthStatus(
            isHealthy: false,
            message: 'DNS leak detected',
            latency: avgLatency,
            isConnected: true,
            hasInternet: true,
            hasLeaks: true,
            leakDetails: leakCheck.item2,
          );
        } else {
          status = HealthStatus(
            isHealthy: true,
            message: 'Connection is healthy',
            latency: avgLatency,
            isConnected: true,
            hasInternet: true,
            hasLeaks: false,
          );
        }
      }
      
      LoggerService.info('Health check result: $status');
    } catch (e) {
      LoggerService.error('Health check failed', e);
      
      status = HealthStatus(
        isHealthy: false,
        message: 'Health check error: ${e.toString()}',
        latency: -1,
        isConnected: _connectionManager.isConnected,
        hasInternet: false,
      );
    }
    
    // Update last status
    _lastStatus = status;
    
    // Notify listeners
    _healthStatusController.add(status);
    
    // Show notification if there's a problem and VPN is connected
    if (!status.isHealthy && status.isConnected) {
      NotificationService.showVpnHealthNotification(
        title: 'VPN Health Alert',
        body: status.message,
      );
    }
    
    return status;
  }
  
  // Measure latencies to health check servers
  Future<List<int>> _measureLatencies() async {
    final latencies = <int>[];
    
    for (final url in _healthCheckUrls) {
      try {
        final stopwatch = Stopwatch()..start();
        
        final response = await http.get(Uri.parse(url)).timeout(
          const Duration(milliseconds: _pingTimeout),
          onTimeout: () => http.Response('Timeout', 408),
        );
        
        stopwatch.stop();
        
        if (response.statusCode == 200) {
          latencies.add(stopwatch.elapsedMilliseconds);
        } else {
          latencies.add(-1); // Error response
        }
      } catch (e) {
        latencies.add(-1); // Connection error
      }
    }
    
    return latencies;
  }
  
  // Check for DNS leaks
  Future<(bool, List<String>)> _checkForDnsLeaks() async {
    if (!_connectionManager.isConnected) {
      return (false, []);
    }
    
    try {
      // Try to get DNS servers from system or VPN config
      List<String> expectedDns = [];
      
      // Randomly choose a leak test server
      final random = Random();
      final serverUrl = _dnsLeakCheckServers[random.nextInt(_dnsLeakCheckServers.length)];
      
      // Send request to DNS leak test service
      final response = await http.get(Uri.parse(serverUrl)).timeout(
        const Duration(seconds: 10),
        onTimeout: () => http.Response('Timeout', 408),
      );
      
      if (response.statusCode != 200) {
        // Couldn't check for leaks
        return (false, []);
      }
      
      try {
        // Parse the response (depends on the API format used)
        final leakData = jsonDecode(response.body);
        final detectedServers = leakData['dns_servers'] as List<dynamic>? ?? [];
        
        // Extract server IPs
        final detectedIps = detectedServers
            .map((server) => server['ip'] as String)
            .toList();
        
        // Check if any of the detected IPs are not in expected DNS servers
        final unexpectedServers = detectedIps
            .where((ip) => !expectedDns.contains(ip))
            .toList();
        
        // Consider it a leak if we have unexpected servers
        return (unexpectedServers.isNotEmpty, unexpectedServers);
      } catch (e) {
        // Parsing error
        LoggerService.error('Error parsing DNS leak test response', e);
        return (false, []);
      }
    } catch (e) {
      LoggerService.error('DNS leak test failed', e);
      return (false, []);
    }
  }
  
  // Clean up resources
  void dispose() {
    stopMonitoring();
    _healthStatusController.close();
  }
}

// Extension to add VPN health notification method to NotificationService
extension VpnHealthNotification on NotificationService {
  static Future<void> showVpnHealthNotification({
    required String title,
    required String body,
  }) async {
    try {
      await NotificationService.showNotification(
        title: title,
        body: body,
        payload: 'vpn_health',
      );
    } catch (e) {
      LoggerService.error('Failed to show VPN health notification', e);
    }
  }
}