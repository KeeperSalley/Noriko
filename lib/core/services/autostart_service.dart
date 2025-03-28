import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';
import 'logger_service.dart';

/// Сервис для управления автозапуском приложения при старте системы
class AutostartService {
  // Путь к исполняемому файлу приложения (актуально для Windows и macOS)
  static String? _executablePath;
  
  /// Установка автозапуска в зависимости от платформы
  static Future<bool> setAutostart(bool enable) async {
    try {
      // Получаем путь к исполняемому файлу, если еще не получен
      if (_executablePath == null) {
        _executablePath = await _getExecutablePath();
      }
      
      if (Platform.isWindows) {
        return await _setWindowsAutostart(enable);
      } else if (Platform.isLinux) {
        return await _setLinuxAutostart(enable);
      } else if (Platform.isMacOS) {
        return await _setMacOSAutostart(enable);
      } else {
        // Для Android автозапуск реализуется через system_intent, но это не часть текущей задачи
        LoggerService.warning('Автозапуск не поддерживается для данной платформы');
        return false;
      }
    } catch (e) {
      LoggerService.error('Ошибка при настройке автозапуска', e);
      return false;
    }
  }
  
  /// Получение пути к исполняемому файлу приложения
  static Future<String> _getExecutablePath() async {
    try {
      if (Platform.isWindows) {
        // Для Windows используем путь к exe-файлу
        return Platform.resolvedExecutable;
      } else if (Platform.isLinux) {
        // Для Linux используем путь к исполняемому файлу
        return Platform.resolvedExecutable;
      } else if (Platform.isMacOS) {
        // Для macOS получаем путь к .app пакету
        String executable = Platform.resolvedExecutable;
        // Получаем родительскую директорию три раза, чтобы получить путь к .app
        // Например: /Applications/MyApp.app/Contents/MacOS/myapp -> /Applications/MyApp.app
        String appPath = path.dirname(path.dirname(path.dirname(executable)));
        return appPath;
      } else {
        return Platform.resolvedExecutable;
      }
    } catch (e) {
      LoggerService.error('Ошибка при получении пути к исполняемому файлу', e);
      return Platform.resolvedExecutable;
    }
  }
  
  /// Настройка автозапуска в Windows через реестр
  static Future<bool> _setWindowsAutostart(bool enable) async {
    try {
      // На Windows используем скрипт PowerShell для работы с реестром
      final String appName = AppConstants.appName.replaceAll(' ', '');
      final String regPath = 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run';
      final String execPath = _executablePath!.replaceAll('\\', '\\\\'); // Экранирование для PowerShell
      
      String script;
      if (enable) {
        // Добавление записи в реестр
        script = 'New-ItemProperty -Path "$regPath" -Name "$appName" -Value "$execPath" -PropertyType String -Force';
      } else {
        // Удаление записи из реестра
        script = 'Remove-ItemProperty -Path "$regPath" -Name "$appName" -ErrorAction SilentlyContinue';
      }
      
      // Выполнение скрипта PowerShell
      final ProcessResult result = await Process.run('powershell', ['-Command', script], runInShell: true);
      
      if (result.exitCode != 0) {
        LoggerService.error('Ошибка при выполнении PowerShell скрипта: ${result.stderr}');
        return false;
      }
      
      LoggerService.info('Автозапуск для Windows ${enable ? "включен" : "отключен"}');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при настройке автозапуска для Windows', e);
      return false;
    }
  }
  
  /// Настройка автозапуска в Linux через .desktop файл
  static Future<bool> _setLinuxAutostart(bool enable) async {
    try {
      // Путь к .desktop файлу в автозапуске
      final Directory homeDir = await getHomeDirectory();
      final String autostartDir = path.join(homeDir.path, '.config', 'autostart');
      final String desktopFilePath = path.join(autostartDir, '${AppConstants.appName.toLowerCase().replaceAll(' ', '-')}.desktop');
      
      if (enable) {
        // Создаем директорию автозапуска, если она не существует
        final Directory autostartDirObj = Directory(autostartDir);
        if (!await autostartDirObj.exists()) {
          await autostartDirObj.create(recursive: true);
        }
        
        // Создаем .desktop файл для автозапуска
        final File desktopFile = File(desktopFilePath);
        final String desktopContent = '''[Desktop Entry]
Type=Application
Name=${AppConstants.appName}
Exec=${_executablePath}
Terminal=false
X-GNOME-Autostart-enabled=true
''';
        
        await desktopFile.writeAsString(desktopContent);
        LoggerService.info('Автозапуск для Linux включен');
      } else {
        // Удаляем .desktop файл, если он существует
        final File desktopFile = File(desktopFilePath);
        if (await desktopFile.exists()) {
          await desktopFile.delete();
        }
        LoggerService.info('Автозапуск для Linux отключен');
      }
      
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при настройке автозапуска для Linux', e);
      return false;
    }
  }
  
  /// Настройка автозапуска в macOS через Launch Agents
  static Future<bool> _setMacOSAutostart(bool enable) async {
    try {
      // Путь к plist файлу в LaunchAgents
      final Directory homeDir = await getHomeDirectory();
      final String launchAgentsDir = path.join(homeDir.path, 'Library', 'LaunchAgents');
      final String bundleIdentifier = 'com.noriko.vpn'; // Идентификатор приложения
      final String plistFilePath = path.join(launchAgentsDir, '$bundleIdentifier.plist');
      
      if (enable) {
        // Создаем директорию LaunchAgents, если она не существует
        final Directory launchAgentsDirObj = Directory(launchAgentsDir);
        if (!await launchAgentsDirObj.exists()) {
          await launchAgentsDirObj.create(recursive: true);
        }
        
        // Создаем plist файл для автозапуска
        final File plistFile = File(plistFilePath);
        final String plistContent = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$bundleIdentifier</string>
    <key>ProgramArguments</key>
    <array>
        <string>${_executablePath}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>''';
        
        await plistFile.writeAsString(plistContent);
        
        // Загружаем агент в систему
        await Process.run('launchctl', ['load', plistFilePath]);
        LoggerService.info('Автозапуск для macOS включен');
      } else {
        // Выгружаем агент из системы, если он существует
        final File plistFile = File(plistFilePath);
        if (await plistFile.exists()) {
          await Process.run('launchctl', ['unload', plistFilePath]);
          await plistFile.delete();
        }
        LoggerService.info('Автозапуск для macOS отключен');
      }
      
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при настройке автозапуска для macOS', e);
      return false;
    }
  }
  
  /// Получение домашней директории пользователя
  static Future<Directory> getHomeDirectory() async {
    try {
      if (Platform.isWindows) {
        // Для Windows используем переменную окружения USERPROFILE
        final String? userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null) {
          return Directory(userProfile);
        }
      } else if (Platform.isLinux || Platform.isMacOS) {
        // Для Linux и macOS используем переменную окружения HOME
        final String? home = Platform.environment['HOME'];
        if (home != null) {
          return Directory(home);
        }
      }
      
      // Запасной вариант - используем getApplicationDocumentsDirectory
      return await getApplicationDocumentsDirectory();
    } catch (e) {
      LoggerService.error('Ошибка при получении домашней директории', e);
      // В крайнем случае, просто возвращаем текущую директорию
      return Directory.current;
    }
  }
}