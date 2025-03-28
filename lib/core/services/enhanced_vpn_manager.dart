import 'dart:async';

import '../../data/models/vpn_config.dart';
import 'vpn_connection_manager.dart';
import 'split_tunneling_service.dart';
import 'connection_health_monitor.dart';
import 'logger_service.dart';

/// Extension of the VPN Connection Manager that integrates with
/// split tunneling and connection health monitoring
class EnhancedVPNManager {
  // Singleton pattern
  static final EnhancedVPNManager _instance = EnhancedVPNManager._internal();
  factory EnhancedVPNManager() => _instance;
  EnhancedVPNManager._internal();

  // Core services
  final VPNConnectionManager _connectionManager = VPNConnectionManager();
  final SplitTunnelingService _splitTunnelingService = SplitTunnelingService();
  final ConnectionHealthMonitor _healthMonitor = ConnectionHealthMonitor();
  
  // Stream subscriptions
  StreamSubscription? _statusSubscription;
  StreamSubscription? _healthSubscription;
  StreamSubscription? _splitTunnelingSubscription;
  
  // Initialize the enhanced VPN manager
  Future<bool> initialize() async {
    try {
      LoggerService.info('Initializing Enhanced VPN Manager');
      
      // Initialize services
      await _connectionManager.initialize();
      await _splitTunnelingService.initialize();
      
      // Set up subscriptions
      _setupSubscriptions();
      
      return true;
    } catch (e) {
      LoggerService.error('Failed to initialize Enhanced VPN Manager', e);
      return false;
    }
  }

  // Set up stream subscriptions
  void _setupSubscriptions() {
    // Listen for VPN status changes
    _statusSubscription = _connectionManager.connectionStatus.listen((status) {
      // Start or stop health monitoring based on connection status
      if (status == VPNStatus.connected) {
        _healthMonitor.startMonitoring();
      } else if (status == VPNStatus.disconnected || status == VPNStatus.error) {
        _healthMonitor.stopMonitoring();
      }
    });
    
    // Listen for split tunneling configuration changes
    _splitTunnelingSubscription = _splitTunnelingService.onConfigChanged.listen((mode) {
      // Apply split tunneling configuration if connected
      if (_connectionManager.isConnected) {
        _applySplitTunnelingConfig();
      }
    });
    
    // Listen for health status changes
    _healthSubscription = _healthMonitor.healthStatus.listen((status) {
      // Handle connection health issues
      if (!status.isHealthy && _connectionManager.isConnected) {
        // Auto-reconnect if configured to do so and there's a connection issue
        _handleConnectionIssue(status);
      }
    });
  }

  // Connect to VPN with split tunneling
  Future<bool> connect(VpnConfig config) async {
    try {
      LoggerService.info('Connecting to VPN with split tunneling');
      
      // Connect using the core manager
      final connected = await _connectionManager.connect(config);
      
      if (connected) {
        // Apply split tunneling configuration
        await _applySplitTunnelingConfig();
        
        // Start health monitoring
        _healthMonitor.startMonitoring();
      }
      
      return connected;
    } catch (e) {
      LoggerService.error('Failed to connect with split tunneling', e);
      return false;
    }
  }

  // Disconnect from VPN
  Future<bool> disconnect() async {
    try {
      // Stop health monitoring
      _healthMonitor.stopMonitoring();
      
      // Disconnect using the core manager
      return await _connectionManager.disconnect();
    } catch (e) {
      LoggerService.error('Failed to disconnect', e);
      return false;
    }
  }

  // Apply split tunneling configuration
  Future<void> _applySplitTunnelingConfig() async {
    try {
      // Only proceed if connected
      if (!_connectionManager.isConnected) return;
      
      final mode = _splitTunnelingService.mode;
      
      // Convert mode to platform-specific format
      int platformMode;
      switch (mode) {
        case SplitTunnelMode.disabled:
          platformMode = 0;
          break;
        case SplitTunnelMode.exclude:
          platformMode = 1;
          break;
        case SplitTunnelMode.include:
          platformMode = 2;
          break;
      }
      
      // Set the mode
      await _connectionManager.setSplitTunnelMode(platformMode);
      
      // Get enabled apps
      final enabledApps = _splitTunnelingService.enabledPackageNames;
      
      // Clear existing apps first (to handle removed apps)
      final currentApps = await _connectionManager.getSplitTunnelApps();
      for (final app in currentApps) {
        await _connectionManager.removeAppFromSplitTunnel(app);
      }
      
      // Add enabled apps
      for (final app in enabledApps) {
        await _connectionManager.addAppToSplitTunnel(app);
      }
      
      LoggerService.info('Applied split tunneling configuration: ${mode.toString().split('.').last}, ${enabledApps.length} apps');
    } catch (e) {
      LoggerService.error('Failed to apply split tunneling configuration', e);
    }
  }

  // Handle connection health issues
  Future<void> _handleConnectionIssue(HealthStatus status) async {
    try {
      LoggerService.warning('Handling connection issue: ${status.message}');
      
      // Get current connection info
      final config = _connectionManager.currentConfig;
      if (config == null) return;
      
      // Attempt to reconnect if there are connectivity issues
      if (!status.hasInternet || status.latency < 0) {
        LoggerService.info('Auto-reconnecting due to connectivity issues');
        
        // Disconnect and reconnect
        await disconnect();
        
        // Wait a moment before reconnecting
        await Future.delayed(const Duration(seconds: 2));
        
        // Reconnect
        await connect(config);
      }
      // For other issues like DNS leaks or high latency, we just log for now
      else if (status.hasLeaks) {
        LoggerService.warning('DNS leak detected: ${status.leakDetails.join(', ')}');
      } else if (status.latency > 0 && status.latency > 500) {
        LoggerService.warning('High latency: ${status.latency} ms');
      }
    } catch (e) {
      LoggerService.error('Failed to handle connection issue', e);
    }
  }

  // Set split tunneling mode
  Future<void> setSplitTunnelMode(SplitTunnelMode mode) async {
    await _splitTunnelingService.setMode(mode);
  }

  // Enable an app for split tunneling
  Future<void> enableAppForSplitTunnel(String packageName) async {
    await _splitTunnelingService.enableApp(packageName);
  }

  // Disable an app for split tunneling
  Future<void> disableAppForSplitTunnel(String packageName) async {
    await _splitTunnelingService.disableApp(packageName);
  }

  // Get all apps for split tunneling
  List<AppInfo> getAppsForSplitTunnel() {
    return _splitTunnelingService.apps;
  }

  // Get the current health status
  HealthStatus? getCurrentHealthStatus() {
    return _healthMonitor.lastStatus;
  }

  // Forward methods to the core VPN connection manager
  int get status => _connectionManager.status;
  bool get isConnected => _connectionManager.isConnected;
  bool get isConnecting => _connectionManager.isConnecting;
  VpnConfig? get currentConfig => _connectionManager.currentConfig;
  SplitTunnelMode get splitTunnelMode => _splitTunnelingService.mode;
  
  Stream<int> get connectionStatus => _connectionManager.connectionStatus;
  Stream<String> get connectionErrors => _connectionManager.connectionErrors;
  Stream<HealthStatus> get healthStatus => _healthMonitor.healthStatus;

  // Get traffic statistics
  Future<Map<String, dynamic>> getTrafficStats() {
    return _connectionManager.getTrafficStats();
  }

  // Format methods
  String formatBytes(int bytes) {
    return _connectionManager.formatBytes(bytes);
  }

  String formatDuration(Duration duration) {
    return _connectionManager.formatDuration(duration);
  }

  // Clean up resources
  void dispose() {
    _statusSubscription?.cancel();
    _healthSubscription?.cancel();
    _splitTunnelingSubscription?.cancel();
    
    _healthMonitor.dispose();
    _splitTunnelingService.dispose();
    _connectionManager.dispose();
  }
}