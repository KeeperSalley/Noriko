import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';

class AppSettingsService {
  static const String _fileName = 'settings.json';
  
  // Ключи для настроек
  static const String keyAutoStart = 'autoStart';
  static const String keyAutoConnect = 'autoConnect';
  static const String keyMinimizeToTray = 'minimizeToTray';
  static const String keyEnableLogging = 'enableLogging';
  static const String keyEnableNotifications = 'enableNotifications';
  static const String keyUseCustomDNS = 'useCustomDNS';
  static const String keyPrimaryDNS = 'primaryDNS';
  static const String keySecondaryDNS = 'secondaryDNS';
  
  // Значения по умолчанию
  static const bool defaultAutoStart = false;
  static const bool defaultAutoConnect = false;
  static const bool defaultMinimizeToTray = true;
  static const bool defaultEnableLogging = true;
  static const bool defaultEnableNotifications = true;
  static const bool defaultUseCustomDNS = false;
  static const String defaultPrimaryDNS = '1.1.1.1';
  static const String defaultSecondaryDNS = '8.8.8.8';
  
  // Метод для получения настроек
  static Future<Map<String, dynamic>> getSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Читаем настройки из SharedPreferences, или используем значения по умолчанию
      return {
        keyAutoStart: prefs.getBool(keyAutoStart) ?? defaultAutoStart,
        keyAutoConnect: prefs.getBool(keyAutoConnect) ?? defaultAutoConnect,
        keyMinimizeToTray: prefs.getBool(keyMinimizeToTray) ?? defaultMinimizeToTray,
        keyEnableLogging: prefs.getBool(keyEnableLogging) ?? defaultEnableLogging,
        keyEnableNotifications: prefs.getBool(keyEnableNotifications) ?? defaultEnableNotifications,
        keyUseCustomDNS: prefs.getBool(keyUseCustomDNS) ?? defaultUseCustomDNS,
        keyPrimaryDNS: prefs.getString(keyPrimaryDNS) ?? defaultPrimaryDNS,
        keySecondaryDNS: prefs.getString(keySecondaryDNS) ?? defaultSecondaryDNS,
      };
    } catch (e) {
      LoggerService.error('Ошибка при загрузке настроек', e);
      // В случае ошибки возвращаем настройки по умолчанию
      return _getDefaultSettings();
    }
  }
  
  // Сохранение настроек
  static Future<bool> saveSettings(Map<String, dynamic> settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Сохраняем каждую настройку
      for (final entry in settings.entries) {
        final key = entry.key;
        final value = entry.value;
        
        if (value is bool) {
          await prefs.setBool(key, value);
        } else if (value is String) {
          await prefs.setString(key, value);
        } else if (value is int) {
          await prefs.setInt(key, value);
        } else if (value is double) {
          await prefs.setDouble(key, value);
        } else if (value is List<String>) {
          await prefs.setStringList(key, value);
        }
      }
      
      // Записываем копию настроек в JSON-файл для резервного копирования
      await _saveToJsonFile(settings);
      
      LoggerService.info('Настройки приложения успешно сохранены');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при сохранении настроек', e);
      return false;
    }
  }
  
  // Сброс настроек до значений по умолчанию
  static Future<bool> resetToDefaults() async {
    try {
      final defaults = _getDefaultSettings();
      return await saveSettings(defaults);
    } catch (e) {
      LoggerService.error('Ошибка при сбросе настроек', e);
      return false;
    }
  }
  
  // Настройки по умолчанию
  static Map<String, dynamic> _getDefaultSettings() {
    return {
      keyAutoStart: defaultAutoStart,
      keyAutoConnect: defaultAutoConnect,
      keyMinimizeToTray: defaultMinimizeToTray,
      keyEnableLogging: defaultEnableLogging,
      keyEnableNotifications: defaultEnableNotifications,
      keyUseCustomDNS: defaultUseCustomDNS,
      keyPrimaryDNS: defaultPrimaryDNS,
      keySecondaryDNS: defaultSecondaryDNS,
    };
  }
  
  // Экспорт настроек в JSON
  static Future<String?> exportSettingsToJson() async {
    try {
      final settings = await getSettings();
      return jsonEncode(settings);
    } catch (e) {
      LoggerService.error('Ошибка при экспорте настроек', e);
      return null;
    }
  }
  
  // Импорт настроек из JSON
  static Future<bool> importSettingsFromJson(String jsonString) async {
    try {
      final Map<String, dynamic> settings = jsonDecode(jsonString);
      return await saveSettings(settings);
    } catch (e) {
      LoggerService.error('Ошибка при импорте настроек', e);
      return false;
    }
  }
  
  // Сохранение настроек в JSON-файл (для бэкапа)
  static Future<void> _saveToJsonFile(Map<String, dynamic> settings) async {
    try {
      final directory = await _getStorageDirectory();
      final file = File('${directory.path}/$_fileName');
      
      final jsonString = jsonEncode(settings);
      await file.writeAsString(jsonString);
    } catch (e) {
      LoggerService.error('Ошибка при сохранении настроек в файл', e);
    }
  }
  
  // Очистка логов
  static Future<bool> clearLogs() async {
    try {
      final directory = await _getStorageDirectory();
      final logsDir = Directory('${directory.path}/logs');
      
      if (await logsDir.exists()) {
        await logsDir.delete(recursive: true);
        LoggerService.info('Логи успешно очищены');
      }
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при очистке логов', e);
      return false;
    }
  }
  
  // Получение директории для хранения данных
  static Future<Directory> _getStorageDirectory() async {
    try {
      // На Windows, macOS и Linux используем директорию приложения
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        return await getApplicationSupportDirectory();
      }
      // На Android используем внешнюю директорию
      else if (Platform.isAndroid) {
        return await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      }
      // На других платформах используем директорию документов
      else {
        return await getApplicationDocumentsDirectory();
      }
    } catch (e) {
      LoggerService.error('Ошибка при получении директории хранения', e);
      // Запасной вариант - временная директория
      return await getTemporaryDirectory();
    }
  }
  
  // Настройка автозапуска (специфично для платформы)
  static Future<bool> setAutoStart(bool enabled) async {
    try {
      // Обновляем настройку в памяти
      final settings = await getSettings();
      settings[keyAutoStart] = enabled;
      await saveSettings(settings);
      
      // Платформенно-зависимая логика
      if (Platform.isWindows) {
        // Для Windows используем реестр (требуется дополнительный плагин)
        LoggerService.info('Автозапуск для Windows ${enabled ? "включен" : "отключен"}');
        // TODO: Реализовать через registry_helper или другой плагин
      } else if (Platform.isLinux) {
        // Для Linux создаем .desktop файл
        LoggerService.info('Автозапуск для Linux ${enabled ? "включен" : "отключен"}');
        // TODO: Реализовать через создание .desktop файла
      } else if (Platform.isMacOS) {
        // Для macOS используем LaunchAgent
        LoggerService.info('Автозапуск для macOS ${enabled ? "включен" : "отключен"}');
        // TODO: Реализовать через LaunchAgent
      }
      
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при настройке автозапуска', e);
      return false;
    }
  }
}