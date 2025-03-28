import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../constants/app_constants.dart';
import 'logger_service.dart';

/// Split tunneling mode
enum SplitTunnelMode {
  /// Tunnel all traffic through VPN
  disabled,
  
  /// Exclude apps from VPN tunnel (tunnel all except specified)
  exclude,
  
  /// Include only specified apps in VPN tunnel (bypass all except specified)
  include,
}

/// App information for split tunneling
class AppInfo {
  final String packageName;
  final String name;
  final String? icon;
  final bool isSystemApp;
  bool enabled;

  AppInfo({
    required this.packageName,
    required this.name,
    this.icon,
    required this.isSystemApp,
    this.enabled = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'name': name,
      'icon': icon,
      'isSystemApp': isSystemApp,
      'enabled': enabled,
    };
  }

  factory AppInfo.fromJson(Map<String, dynamic> json) {
    return AppInfo(
      packageName: json['packageName'],
      name: json['name'],
      icon: json['icon'],
      isSystemApp: json['isSystemApp'] ?? false,
      enabled: json['enabled'] ?? false,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppInfo && other.packageName == packageName;
  }

  @override
  int get hashCode => packageName.hashCode;
}

/// A service for managing split tunneling configuration
class SplitTunnelingService {
  // Singleton pattern
  static final SplitTunnelingService _instance = SplitTunnelingService._internal();
  factory SplitTunnelingService() => _instance;
  SplitTunnelingService._internal();

  // Split tunneling configuration
  SplitTunnelMode _mode = SplitTunnelMode.disabled;
  final List<AppInfo> _apps = [];
  
  // Stream controller for configuration changes
  final _configChangedController = StreamController<SplitTunnelMode>.broadcast();
  Stream<SplitTunnelMode> get onConfigChanged => _configChangedController.stream;
  
  // Getters
  SplitTunnelMode get mode => _mode;
  List<AppInfo> get apps => List.unmodifiable(_apps);
  List<AppInfo> get enabledApps => _apps.where((app) => app.enabled).toList();
  List<String> get enabledPackageNames => _apps.where((app) => app.enabled).map((app) => app.packageName).toList();
  
  // Initialize the service
  Future<void> initialize() async {
    try {
      LoggerService.info('Initializing Split Tunneling Service');
      
      // Load configuration
      await _loadConfig();
      
      // Load installed apps if on Android
      if (Platform.isAndroid) {
        await _loadInstalledApps();
      }
      
      LoggerService.info('Split Tunneling Service initialized with mode: ${_mode.toString().split('.').last}');
    } catch (e) {
      LoggerService.error('Failed to initialize Split Tunneling Service', e);
      // Default to disabled mode
      _mode = SplitTunnelMode.disabled;
    }
  }

  // Load split tunneling configuration
  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load mode
      final modeIndex = prefs.getInt('splitTunnelMode') ?? SplitTunnelMode.disabled.index;
      _mode = SplitTunnelMode.values[modeIndex];
      
      // Load app list from file
      final file = await _getAppsFile();
      
      if (await file.exists()) {
        final jsonContent = await file.readAsString();
        final List<dynamic> appsJson = jsonDecode(jsonContent);
        
        _apps.clear();
        _apps.addAll(appsJson.map((appJson) => AppInfo.fromJson(appJson)));
        
        LoggerService.info('Loaded ${_apps.length} apps for split tunneling');
      }
    } catch (e) {
      LoggerService.error('Failed to load split tunneling configuration', e);
      // Default to disabled mode
      _mode = SplitTunnelMode.disabled;
    }
  }

  // Save split tunneling configuration
  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Save mode
      await prefs.setInt('splitTunnelMode', _mode.index);
      
      // Save app list to file
      final file = await _getAppsFile();
      final appsJson = _apps.map((app) => app.toJson()).toList();
      
      await file.writeAsString(jsonEncode(appsJson));
      
      LoggerService.info('Saved split tunneling configuration with ${_apps.length} apps');
    } catch (e) {
      LoggerService.error('Failed to save split tunneling configuration', e);
    }
  }

  // Get file reference for apps storage
  Future<File> _getAppsFile() async {
    final appDir = await getApplicationSupportDirectory();
    final configDir = path.join(appDir.path, AppConstants.configDir);
    
    // Create config directory if it doesn't exist
    final configDirObj = Directory(configDir);
    if (!await configDirObj.exists()) {
      await configDirObj.create(recursive: true);
    }
    
    return File(path.join(configDir, 'split_tunnel_apps.json'));
  }

  // Load installed apps (Android only)
  Future<void> _loadInstalledApps() async {
    try {
      // This would typically call a platform channel to get installed apps
      // For now, we'll add a placeholder for the current app
      final packageInfo = await PackageInfo.fromPlatform();
      
      // Check if the app is already in the list
      final existingIndex = _apps.indexWhere((app) => app.packageName == packageInfo.packageName);
      
      if (existingIndex < 0) {
        _apps.add(AppInfo(
          packageName: packageInfo.packageName,
          name: packageInfo.appName,
          isSystemApp: false,
          enabled: false,
        ));
      }
      
      LoggerService.info('Loaded installed apps for split tunneling');
    } catch (e) {
      LoggerService.error('Failed to load installed apps', e);
    }
  }

  // Set split tunneling mode
  Future<void> setMode(SplitTunnelMode mode) async {
    if (_mode == mode) return;
    
    _mode = mode;
    await _saveConfig();
    
    LoggerService.info('Set split tunneling mode to: ${mode.toString().split('.').last}');
    _configChangedController.add(mode);
  }

  // Add an app to the split tunneling list
  Future<void> addApp(AppInfo app) async {
    final existingIndex = _apps.indexWhere((a) => a.packageName == app.packageName);
    
    if (existingIndex >= 0) {
      // Update existing app
      _apps[existingIndex] = app;
    } else {
      // Add new app
      _apps.add(app);
    }
    
    await _saveConfig();
    
    LoggerService.info('Added app to split tunneling: ${app.packageName}');
    _configChangedController.add(_mode);
  }

  // Remove an app from the split tunneling list
  Future<void> removeApp(String packageName) async {
    _apps.removeWhere((app) => app.packageName == packageName);
    await _saveConfig();
    
    LoggerService.info('Removed app from split tunneling: $packageName');
    _configChangedController.add(_mode);
  }

  // Enable an app for split tunneling
  Future<void> enableApp(String packageName) async {
    final app = _apps.firstWhere(
      (app) => app.packageName == packageName,
      orElse: () => throw Exception('App not found: $packageName'),
    );
    
    app.enabled = true;
    await _saveConfig();
    
    LoggerService.info('Enabled app for split tunneling: $packageName');
    _configChangedController.add(_mode);
  }

  // Disable an app for split tunneling
  Future<void> disableApp(String packageName) async {
    final app = _apps.firstWhere(
      (app) => app.packageName == packageName,
      orElse: () => throw Exception('App not found: $packageName'),
    );
    
    app.enabled = false;
    await _saveConfig();
    
    LoggerService.info('Disabled app for split tunneling: $packageName');
    _configChangedController.add(_mode);
  }

  // Get apps by category (system or user)
  List<AppInfo> getAppsByCategory(bool systemApps) {
    return _apps.where((app) => app.isSystemApp == systemApps).toList();
  }

  // Clean up resources
  void dispose() {
    _configChangedController.close();
  }
}