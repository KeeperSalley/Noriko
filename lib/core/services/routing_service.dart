import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import 'logger_service.dart';

class RouteRule {
  final String type; // 'domain', 'ip', 'port', etc.
  final String value; // The actual domain, IP, port value
  final String action; // 'proxy', 'direct', 'block'

  RouteRule({
    required this.type,
    required this.value,
    required this.action,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'value': value,
      'action': action,
    };
  }

  factory RouteRule.fromJson(Map<String, dynamic> json) {
    return RouteRule(
      type: json['type'],
      value: json['value'],
      action: json['action'],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RouteRule &&
        other.type == type &&
        other.value == value &&
        other.action == action;
  }

  @override
  int get hashCode => type.hashCode ^ value.hashCode ^ action.hashCode;
}

class RoutingProfile {
  final String name;
  final List<RouteRule> rules;
  final bool isSplitTunnelingEnabled;
  final bool isProxyOnlyEnabled; // Only proxy specific apps/sites

  RoutingProfile({
    required this.name,
    required this.rules,
    this.isSplitTunnelingEnabled = false,
    this.isProxyOnlyEnabled = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'rules': rules.map((rule) => rule.toJson()).toList(),
      'isSplitTunnelingEnabled': isSplitTunnelingEnabled,
      'isProxyOnlyEnabled': isProxyOnlyEnabled,
    };
  }

  factory RoutingProfile.fromJson(Map<String, dynamic> json) {
    return RoutingProfile(
      name: json['name'],
      rules: (json['rules'] as List)
          .map((rule) => RouteRule.fromJson(rule))
          .toList(),
      isSplitTunnelingEnabled: json['isSplitTunnelingEnabled'] ?? false,
      isProxyOnlyEnabled: json['isProxyOnlyEnabled'] ?? false,
    );
  }

  factory RoutingProfile.standard() {
    return RoutingProfile(
      name: 'Standard',
      rules: [
        RouteRule(type: 'ip', value: 'geoip:private', action: 'direct'),
        RouteRule(type: 'domain', value: 'geosite:category-ads', action: 'block'),
      ],
      isSplitTunnelingEnabled: false,
      isProxyOnlyEnabled: false,
    );
  }

  factory RoutingProfile.china() {
    return RoutingProfile(
      name: 'China',
      rules: [
        RouteRule(type: 'ip', value: 'geoip:private', action: 'direct'),
        RouteRule(type: 'ip', value: 'geoip:cn', action: 'direct'),
        RouteRule(type: 'domain', value: 'geosite:cn', action: 'direct'),
        RouteRule(type: 'domain', value: 'geosite:category-ads', action: 'block'),
      ],
      isSplitTunnelingEnabled: true,
      isProxyOnlyEnabled: false,
    );
  }

  factory RoutingProfile.gaming() {
    return RoutingProfile(
      name: 'Gaming',
      rules: [
        RouteRule(type: 'ip', value: 'geoip:private', action: 'direct'),
        RouteRule(type: 'domain', value: 'geosite:category-games', action: 'proxy'),
        // Common gaming platforms
        RouteRule(type: 'domain', value: 'steam', action: 'proxy'),
        RouteRule(type: 'domain', value: 'steampowered.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'epicgames.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'battlenet.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'ea.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'origin.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'riotgames.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'geosite:category-ads', action: 'block'),
      ],
      isSplitTunnelingEnabled: true,
      isProxyOnlyEnabled: true,
    );
  }

  factory RoutingProfile.streaming() {
    return RoutingProfile(
      name: 'Streaming',
      rules: [
        RouteRule(type: 'ip', value: 'geoip:private', action: 'direct'),
        // Major streaming platforms
        RouteRule(type: 'domain', value: 'netflix.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'netflix.net', action: 'proxy'),
        RouteRule(type: 'domain', value: 'nflxvideo.net', action: 'proxy'),
        RouteRule(type: 'domain', value: 'hulu.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'disney-plus.net', action: 'proxy'),
        RouteRule(type: 'domain', value: 'disneyplus.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'dssott.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'bamgrid.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'hbo.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'hbomax.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'amazonprime.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'primevideo.com', action: 'proxy'),
        RouteRule(type: 'domain', value: 'aiv-cdn.net', action: 'proxy'),
        RouteRule(type: 'domain', value: 'geosite:category-ads', action: 'block'),
      ],
      isSplitTunnelingEnabled: true,
      isProxyOnlyEnabled: true,
    );
  }
}

class RoutingService {
  // Singleton pattern
  static final RoutingService _instance = RoutingService._internal();
  factory RoutingService() => _instance;
  RoutingService._internal();

  // Current routing profile
  RoutingProfile _currentProfile = RoutingProfile.standard();
  List<RoutingProfile> _savedProfiles = [];
  
  // Stream controller for routing updates
  final _routingChangedController = StreamController<RoutingProfile>.broadcast();
  Stream<RoutingProfile> get onRoutingChanged => _routingChangedController.stream;
  
  // Getters
  RoutingProfile get currentProfile => _currentProfile;
  List<RoutingProfile> get savedProfiles => _savedProfiles;
  
  // Initialize the routing service
  Future<void> initialize() async {
    try {
      LoggerService.info('Initializing Routing Service');
      
      // Load saved profiles
      await _loadProfiles();
      
      // Load last used profile
      await _loadCurrentProfile();
      
      LoggerService.info('Routing Service initialized with profile: ${_currentProfile.name}');
    } catch (e) {
      LoggerService.error('Failed to initialize Routing Service', e);
      // Fallback to standard profile if initialization fails
      _currentProfile = RoutingProfile.standard();
    }
  }

  // Load routing profiles from storage
  Future<void> _loadProfiles() async {
    try {
      final file = await _getProfilesFile();
      
      if (await file.exists()) {
        final jsonContent = await file.readAsString();
        final List<dynamic> profilesJson = jsonDecode(jsonContent);
        
        _savedProfiles = profilesJson
            .map((profileJson) => RoutingProfile.fromJson(profileJson))
            .toList();
        
        LoggerService.info('Loaded ${_savedProfiles.length} routing profiles');
      } else {
        // Create default profiles if none exist
        _savedProfiles = [
          RoutingProfile.standard(),
          RoutingProfile.china(),
          RoutingProfile.gaming(),
          RoutingProfile.streaming(),
        ];
        
        await _saveProfiles();
        LoggerService.info('Created default routing profiles');
      }
    } catch (e) {
      LoggerService.error('Failed to load routing profiles', e);
      // Initialize with default profiles
      _savedProfiles = [
        RoutingProfile.standard(),
        RoutingProfile.china(),
        RoutingProfile.gaming(),
        RoutingProfile.streaming(),
      ];
    }
  }

  // Load current routing profile
  Future<void> _loadCurrentProfile() async {
    try {
      final prefsDir = await getApplicationSupportDirectory();
      final prefsFile = File(path.join(prefsDir.path, 'routing_prefs.json'));
      
      if (await prefsFile.exists()) {
        final jsonContent = await prefsFile.readAsString();
        final Map<String, dynamic> prefs = jsonDecode(jsonContent);
        
        final String profileName = prefs['currentProfile'] ?? 'Standard';
        final profile = _savedProfiles.firstWhere(
          (profile) => profile.name == profileName,
          orElse: () => RoutingProfile.standard(),
        );
        
        _currentProfile = profile;
        LoggerService.info('Loaded current routing profile: ${profile.name}');
      }
    } catch (e) {
      LoggerService.error('Failed to load current routing profile', e);
      // Keep default if fails
    }
  }

  // Save current profile preference
  Future<void> _saveCurrentProfile() async {
    try {
      final prefsDir = await getApplicationSupportDirectory();
      final prefsFile = File(path.join(prefsDir.path, 'routing_prefs.json'));
      
      final prefs = {
        'currentProfile': _currentProfile.name,
      };
      
      await prefsFile.writeAsString(jsonEncode(prefs));
      LoggerService.info('Saved current routing profile: ${_currentProfile.name}');
    } catch (e) {
      LoggerService.error('Failed to save current routing profile', e);
    }
  }

  // Save all profiles to storage
  Future<void> _saveProfiles() async {
    try {
      final file = await _getProfilesFile();
      final profilesJson = _savedProfiles.map((profile) => profile.toJson()).toList();
      
      await file.writeAsString(jsonEncode(profilesJson));
      LoggerService.info('Saved ${_savedProfiles.length} routing profiles');
    } catch (e) {
      LoggerService.error('Failed to save routing profiles', e);
    }
  }

  // Get file reference for profiles storage
  Future<File> _getProfilesFile() async {
    final appDir = await getApplicationSupportDirectory();
    return File(path.join(appDir.path, AppConstants.configDir, 'routing_profiles.json'));
  }

  // Set current routing profile
  Future<void> setCurrentProfile(RoutingProfile profile) async {
    _currentProfile = profile;
    await _saveCurrentProfile();
    _routingChangedController.add(profile);
    LoggerService.info('Set current routing profile to: ${profile.name}');
  }

  // Set current routing profile by name
  Future<bool> setCurrentProfileByName(String name) async {
    try {
      final profile = _savedProfiles.firstWhere(
        (profile) => profile.name == name,
      );
      
      await setCurrentProfile(profile);
      return true;
    } catch (e) {
      LoggerService.error('Failed to set routing profile by name: $name', e);
      return false;
    }
  }

  // Add or update a routing profile
  Future<bool> saveProfile(RoutingProfile profile) async {
    try {
      // Check if profile with this name already exists
      final existingIndex = _savedProfiles.indexWhere((p) => p.name == profile.name);
      
      if (existingIndex >= 0) {
        // Update existing profile
        _savedProfiles[existingIndex] = profile;
      } else {
        // Add new profile
        _savedProfiles.add(profile);
      }
      
      // Save profiles to storage
      await _saveProfiles();
      
      // If this is the current profile, update it
      if (_currentProfile.name == profile.name) {
        await setCurrentProfile(profile);
      }
      
      LoggerService.info('Saved routing profile: ${profile.name}');
      return true;
    } catch (e) {
      LoggerService.error('Failed to save routing profile', e);
      return false;
    }
  }

  // Delete a routing profile
  Future<bool> deleteProfile(String name) async {
    try {
      // Cannot delete the Standard profile
      if (name == 'Standard') {
        LoggerService.warning('Cannot delete the Standard routing profile');
        return false;
      }
      
      // Remove the profile
      _savedProfiles.removeWhere((profile) => profile.name == name);
      
      // Save profiles to storage
      await _saveProfiles();
      
      // If this was the current profile, switch to Standard
      if (_currentProfile.name == name) {
        final standardProfile = _savedProfiles.firstWhere(
          (profile) => profile.name == 'Standard',
          orElse: () => RoutingProfile.standard(),
        );
        
        await setCurrentProfile(standardProfile);
      }
      
      LoggerService.info('Deleted routing profile: $name');
      return true;
    } catch (e) {
      LoggerService.error('Failed to delete routing profile', e);
      return false;
    }
  }

  // Add a rule to the current profile
  Future<bool> addRule(RouteRule rule) async {
    try {
      // Create a copy of the current profile with the new rule
      final updatedRules = List<RouteRule>.from(_currentProfile.rules);
      
      // Check if rule already exists
      final existingIndex = updatedRules.indexWhere(
        (r) => r.type == rule.type && r.value == rule.value,
      );
      
      if (existingIndex >= 0) {
        // Update existing rule
        updatedRules[existingIndex] = rule;
      } else {
        // Add new rule
        updatedRules.add(rule);
      }
      
      // Create updated profile
      final updatedProfile = RoutingProfile(
        name: _currentProfile.name,
        rules: updatedRules,
        isSplitTunnelingEnabled: _currentProfile.isSplitTunnelingEnabled,
        isProxyOnlyEnabled: _currentProfile.isProxyOnlyEnabled,
      );
      
      // Save the updated profile
      return await saveProfile(updatedProfile);
    } catch (e) {
      LoggerService.error('Failed to add routing rule', e);
      return false;
    }
  }

  // Remove a rule from the current profile
  Future<bool> removeRule(RouteRule rule) async {
    try {
      // Create a copy of the current profile without the rule
      final updatedRules = List<RouteRule>.from(_currentProfile.rules)
          .where((r) => !(r.type == rule.type && r.value == rule.value))
          .toList();
      
      // Create updated profile
      final updatedProfile = RoutingProfile(
        name: _currentProfile.name,
        rules: updatedRules,
        isSplitTunnelingEnabled: _currentProfile.isSplitTunnelingEnabled,
        isProxyOnlyEnabled: _currentProfile.isProxyOnlyEnabled,
      );
      
      // Save the updated profile
      return await saveProfile(updatedProfile);
    } catch (e) {
      LoggerService.error('Failed to remove routing rule', e);
      return false;
    }
  }

  // Generate V2Ray routing configuration
  Map<String, dynamic> generateV2RayRouting() {
    final rules = <Map<String, dynamic>>[];
    
    // Group rules by action
    final Map<String, List<RouteRule>> rulesByAction = {};
    
    for (final rule in _currentProfile.rules) {
      if (!rulesByAction.containsKey(rule.action)) {
        rulesByAction[rule.action] = [];
      }
      rulesByAction[rule.action]!.add(rule);
    }
    
    // Process rules by action
    rulesByAction.forEach((action, actionRules) {
      // Group rules by type
      final Map<String, List<String>> valuesByType = {};
      
      for (final rule in actionRules) {
        if (!valuesByType.containsKey(rule.type)) {
          valuesByType[rule.type] = [];
        }
        valuesByType[rule.type]!.add(rule.value);
      }
      
      // Create rule for each type
      valuesByType.forEach((type, values) {
        final rule = <String, dynamic>{
          'type': 'field',
          'outboundTag': action,
        };
        
        // Set appropriate field based on type
        switch (type) {
          case 'domain':
            rule['domain'] = values;
            break;
          case 'ip':
            rule['ip'] = values;
            break;
          case 'port':
            rule['port'] = values.join(',');
            break;
        }
        
        rules.add(rule);
      });
    });
    
    // Create routing configuration
    return {
      'domainStrategy': 'IPIfNonMatch',
      'rules': rules,
    };
  }

  // Cleanup resources
  void dispose() {
    _routingChangedController.close();
  }
}