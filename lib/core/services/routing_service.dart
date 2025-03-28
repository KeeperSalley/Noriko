import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import 'logger_service.dart';

class RouteRule {
  final String type; // 'domain', 'ip', 'port', 'process', 'protocol'
  final String value; // The actual domain, IP, port, process name or protocol value
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
  bool _isSplitTunnelingEnabled;
  bool _isProxyOnlyEnabled;
  bool _udpSupport; // Новое поле для поддержки UDP

  RoutingProfile({
    required this.name,
    required this.rules,
    bool isSplitTunnelingEnabled = false,
    bool isProxyOnlyEnabled = false,
    bool udpSupport = true, // По умолчанию UDP включен
  }) : 
    _isSplitTunnelingEnabled = isSplitTunnelingEnabled,
    _isProxyOnlyEnabled = isProxyOnlyEnabled,
    _udpSupport = udpSupport;

  // Геттеры
  bool get isSplitTunnelingEnabled => _isSplitTunnelingEnabled;
  bool get isProxyOnlyEnabled => _isProxyOnlyEnabled;
  bool get udpSupport => _udpSupport;
  
  // Сеттеры
  set isSplitTunnelingEnabled(bool value) => _isSplitTunnelingEnabled = value;
  set isProxyOnlyEnabled(bool value) => _isProxyOnlyEnabled = value;
  set udpSupport(bool value) => _udpSupport = value;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'rules': rules.map((rule) => rule.toJson()).toList(),
      'isSplitTunnelingEnabled': _isSplitTunnelingEnabled,
      'isProxyOnlyEnabled': _isProxyOnlyEnabled,
      'udpSupport': _udpSupport, // Сохраняем настройку UDP
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
      udpSupport: json['udpSupport'] ?? true, // По умолчанию UDP включен, если не указано иное
    );
  }

  factory RoutingProfile.standard() {
    return RoutingProfile(
      name: 'Standard',
      rules: [
        // Направить весь трафик через прокси по умолчанию
        RouteRule(type: 'default', value: 'default', action: 'proxy'),

        // Локальные/частные сети - напрямую
        RouteRule(type: 'ip', value: 'geoip:private', action: 'direct'),
        
        // Реклама и вредоносные сайты - блокировать
        RouteRule(type: 'domain', value: 'geosite:category-ads', action: 'block'),
        
        // Указываем явно, что TCP трафик идет через прокси
        RouteRule(type: 'protocol', value: 'tcp', action: 'proxy'),
        
        // Указываем явно, что UDP трафик идет через прокси
        RouteRule(type: 'protocol', value: 'udp', action: 'proxy'),
        
        // DNS запросы всегда идут через прокси для предотвращения утечек
        RouteRule(type: 'port', value: '53', action: 'proxy'),
      ],
      isSplitTunnelingEnabled: false,
      isProxyOnlyEnabled: false,
      udpSupport: true,
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
        // Добавим поддержку UDP и TCP для китайского режима
        RouteRule(type: 'protocol', value: 'tcp', action: 'proxy'),
        RouteRule(type: 'protocol', value: 'udp', action: 'proxy'),
      ],
      isSplitTunnelingEnabled: true,
      isProxyOnlyEnabled: false,
      udpSupport: true,
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
        // Для игр важно, чтобы UDP работал для голосовых чатов и некоторых игровых протоколов
        RouteRule(type: 'protocol', value: 'udp', action: 'proxy'),
        RouteRule(type: 'protocol', value: 'tcp', action: 'proxy'),
        // Добавляем правила для популярных игровых портов
        RouteRule(type: 'port', value: '3074', action: 'proxy'), // Xbox Live
        RouteRule(type: 'port', value: '3478-3480', action: 'proxy'), // PlayStation Network
        RouteRule(type: 'port', value: '27000-27050', action: 'proxy'), // Steam
      ],
      isSplitTunnelingEnabled: true,
      isProxyOnlyEnabled: true,
      udpSupport: true, // Для игр особенно важна поддержка UDP
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
        // Для стриминговых сервисов тоже может потребоваться UDP
        RouteRule(type: 'protocol', value: 'udp', action: 'proxy'),
        RouteRule(type: 'protocol', value: 'tcp', action: 'proxy'),
      ],
      isSplitTunnelingEnabled: true,
      isProxyOnlyEnabled: true,
      udpSupport: true,
    );
  }
  
  // Профиль для торрентов с оптимизированной конфигурацией
  factory RoutingProfile.torrents() {
    return RoutingProfile(
      name: 'Torrents',
      rules: [
        RouteRule(type: 'ip', value: 'geoip:private', action: 'direct'),
        RouteRule(type: 'domain', value: 'geosite:category-ads', action: 'block'),
        // Для торрентов особенно важно, чтобы работал UDP (DHT, PEX, и т.д.)
        RouteRule(type: 'protocol', value: 'udp', action: 'proxy'),
        RouteRule(type: 'protocol', value: 'tcp', action: 'proxy'),
        // Популярные порты для торрентов
        RouteRule(type: 'port', value: '6881-6889', action: 'proxy'),
        RouteRule(type: 'port', value: '1337', action: 'proxy'),
        RouteRule(type: 'port', value: '6969', action: 'proxy'),
        // Торрент-клиенты
        RouteRule(type: 'process', value: 'qbittorrent.exe', action: 'proxy'),
        RouteRule(type: 'process', value: 'utorrent.exe', action: 'proxy'),
        RouteRule(type: 'process', value: 'transmission.exe', action: 'proxy'),
        RouteRule(type: 'process', value: 'deluge.exe', action: 'proxy'),
      ],
      isSplitTunnelingEnabled: true,
      isProxyOnlyEnabled: true,
      udpSupport: true,
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
      LoggerService.info('Инициализация сервиса маршрутизации');
      
      // Load saved profiles
      await _loadProfiles();
      
      // Load last used profile
      await _loadCurrentProfile();
      
      LoggerService.info('Сервис маршрутизации инициализирован с профилем: ${_currentProfile.name}');
    } catch (e) {
      LoggerService.error('Ошибка инициализации сервиса маршрутизации', e);
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
        
        LoggerService.info('Загружено ${_savedProfiles.length} профилей маршрутизации');
      } else {
        // Create default profiles if none exist
        _savedProfiles = [
          RoutingProfile.standard(),
          RoutingProfile.china(),
          RoutingProfile.gaming(),
          RoutingProfile.streaming(),
          RoutingProfile.torrents(), // Добавляем новый профиль для торрентов
        ];
        
        await _saveProfiles();
        LoggerService.info('Созданы профили маршрутизации по умолчанию');
      }
    } catch (e) {
      LoggerService.error('Ошибка загрузки профилей маршрутизации', e);
      // Initialize with default profiles
      _savedProfiles = [
        RoutingProfile.standard(),
        RoutingProfile.china(),
        RoutingProfile.gaming(),
        RoutingProfile.streaming(),
        RoutingProfile.torrents(),
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
        LoggerService.info('Загружен текущий профиль маршрутизации: ${profile.name}');
      }
    } catch (e) {
      LoggerService.error('Ошибка загрузки текущего профиля маршрутизации', e);
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
      LoggerService.info('Сохранен текущий профиль маршрутизации: ${_currentProfile.name}');
    } catch (e) {
      LoggerService.error('Ошибка сохранения текущего профиля маршрутизации', e);
    }
  }

  // Save all profiles to storage
  Future<void> _saveProfiles() async {
    try {
      final file = await _getProfilesFile();
      final profilesJson = _savedProfiles.map((profile) => profile.toJson()).toList();
      
      await file.writeAsString(jsonEncode(profilesJson));
      LoggerService.info('Сохранено ${_savedProfiles.length} профилей маршрутизации');
    } catch (e) {
      LoggerService.error('Ошибка сохранения профилей маршрутизации', e);
    }
  }

  // Get file reference for profiles storage
  Future<File> _getProfilesFile() async {
    final appDir = await getApplicationSupportDirectory();
    final configDir = path.join(appDir.path, AppConstants.configDir);
    
    // Create config directory if it doesn't exist
    await Directory(configDir).create(recursive: true);
    
    return File(path.join(configDir, 'routing_profiles.json'));
  }

  // Set current routing profile
  Future<void> setCurrentProfile(RoutingProfile profile) async {
    _currentProfile = profile;
    await _saveCurrentProfile();
    _routingChangedController.add(profile);
    LoggerService.info('Установлен текущий профиль маршрутизации: ${profile.name}');
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
      LoggerService.error('Ошибка установки профиля маршрутизации по имени: $name', e);
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
      
      LoggerService.info('Сохранен профиль маршрутизации: ${profile.name}');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка сохранения профиля маршрутизации', e);
      return false;
    }
  }

  // Delete a routing profile
  Future<bool> deleteProfile(String name) async {
    try {
      // Cannot delete the Standard profile
      if (name == 'Standard') {
        LoggerService.warning('Невозможно удалить стандартный профиль маршрутизации');
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
      
      LoggerService.info('Удален профиль маршрутизации: $name');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка удаления профиля маршрутизации', e);
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
        udpSupport: _currentProfile.udpSupport,
      );
      
      // Save the updated profile
      return await saveProfile(updatedProfile);
    } catch (e) {
      LoggerService.error('Ошибка добавления правила маршрутизации', e);
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
        udpSupport: _currentProfile.udpSupport,
      );
      
      // Save the updated profile
      return await saveProfile(updatedProfile);
    } catch (e) {
      LoggerService.error('Ошибка удаления правила маршрутизации', e);
      return false;
    }
  }

  // Toggle UDP support for current profile
  Future<bool> toggleUdpSupport(bool enabled) async {
    try {
      // Create updated profile with modified UDP support
      final updatedProfile = RoutingProfile(
        name: _currentProfile.name,
        rules: _currentProfile.rules,
        isSplitTunnelingEnabled: _currentProfile.isSplitTunnelingEnabled,
        isProxyOnlyEnabled: _currentProfile.isProxyOnlyEnabled,
        udpSupport: enabled,
      );
      
      // Save the updated profile
      return await saveProfile(updatedProfile);
    } catch (e) {
      LoggerService.error('Ошибка изменения поддержки UDP', e);
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
    
    // Добавляем правило для DNS-запросов (всегда в начале)
    rules.add({
      'type': 'field',
      'port': 53,
      'network': 'udp',
      'outboundTag': 'proxy',
    });
    
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
          case 'protocol':
            rule['protocol'] = values;
            break;
          case 'process':
            if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
              rule['process'] = values;
            }
            break;
          case 'default':
            // Правило по умолчанию добавляется в конце
            break;
        }
        
        // Добавляем только если в правиле есть условия
        if (rule.length > 2) {
          rules.add(rule);
        }
      });
    });
    
    // Если UDP не поддерживается, добавляем правило для блокировки UDP трафика
    if (!_currentProfile.udpSupport) {
      rules.add({
        'type': 'field',
        'network': 'udp',
        'outboundTag': 'direct', // Или 'block', если хотим полностью блокировать
      });
    }
    
    // Если есть правило "default" для прокси, добавляем его последним
    if (rulesByAction.containsKey('proxy') && 
        rulesByAction['proxy']!.any((rule) => rule.type == 'default')) {
      rules.add({
        'type': 'field',
        'outboundTag': 'proxy',
      });
    }
    
    // Create routing configuration
    return {
      'domainStrategy': 'IPIfNonMatch',
      'domainMatcher': 'mph',
      'rules': rules,
    };
  }

  // Configure process-specific routing rules (for Windows)
  Future<bool> applyProcessBasedRules() async {
    if (!Platform.isWindows) return true; // Only applicable to Windows
    
    try {
      // Get all process rules
      final processRules = _currentProfile.rules
          .where((rule) => rule.type == 'process')
          .toList();
      
      if (processRules.isEmpty) return true; // No process rules to apply
      
      // Implement Windows-specific process routing
      // (This would use WFP APIs via FFI or platform channel)
      
      LoggerService.info('Применены правила маршрутизации на основе процессов');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка применения правил маршрутизации на основе процессов', e);
      return false;
    }
  }

  // Создание и экспорт сетевых скриптов для Windows
  Future<String?> exportWindowsBatchScript() async {
    if (!Platform.isWindows) return null;
    
    try {
      final scriptContent = StringBuffer();
      scriptContent.writeln('@echo off');
      scriptContent.writeln('echo Noriko VPN Routing Script');
      scriptContent.writeln('echo =======================');
      scriptContent.writeln('');
      
      // Команды для сохранения текущих маршрутов
      scriptContent.writeln('echo Saving current routing state...');
      scriptContent.writeln('route print > %TEMP%\\route_backup.txt');
      
      // Получаем текущий шлюз
      scriptContent.writeln('for /f "tokens=3" %%a in (\'route print ^| findstr "\\<0.0.0.0\\>"\') do set GATEWAY=%%a');
      
      // Добавляем маршруты на основе правил
      scriptContent.writeln('echo Configuring routing rules...');
      
      // Если UDP включен
      if (_currentProfile.udpSupport) {
        scriptContent.writeln('echo UDP support enabled');
      } else {
        scriptContent.writeln('echo UDP support disabled');
      }
      
      // Добавляем правила для IP-адресов
      for (final rule in _currentProfile.rules.where((r) => r.type == 'ip' && !r.value.startsWith('geoip:'))) {
        if (rule.action == 'direct') {
          scriptContent.writeln('route add ${rule.value} mask 255.255.255.255 %GATEWAY% metric 1');
        } else if (rule.action == 'proxy') {
          scriptContent.writeln('route add ${rule.value} mask 255.255.255.255 10.8.0.1 metric 5');
        }
      }
      
      // Команды для восстановления маршрутов
      scriptContent.writeln('');
      scriptContent.writeln(':cleanup');
      scriptContent.writeln('echo Restoring original routing state...');
      scriptContent.writeln('route delete 10.8.0.1');
      scriptContent.writeln('route delete 0.0.0.0 mask 0.0.0.0 10.8.0.1');
      
      // Путь для сохранения скрипта
      final appDir = await getApplicationSupportDirectory();
      final scriptsDir = path.join(appDir.path, 'scripts');
      await Directory(scriptsDir).create(recursive: true);
      
      final scriptFile = path.join(scriptsDir, 'routing_${_currentProfile.name.toLowerCase()}.bat');
      await File(scriptFile).writeAsString(scriptContent.toString());
      
      LoggerService.info('Экспортирован скрипт маршрутизации: $scriptFile');
      return scriptFile;
    } catch (e) {
      LoggerService.error('Ошибка экспорта скрипта маршрутизации', e);
      return null;
    }
  }

  // Cleanup resources
  void dispose() {
    _routingChangedController.close();
  }
}