import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'logger_service.dart';

/// Сервис для работы с нативными системными уведомлениями на десктопных платформах
class DesktopNotificationService {
  static const MethodChannel _channel = MethodChannel('com.noriko.vpn/notifications');
  
  static Future<bool> showNativeNotification({
    required String title,
    required String body,
    String? iconPath,
  }) async {
    try {
      if (Platform.isWindows) {
        return await _showWindowsNotification(title, body, iconPath);
      } else if (Platform.isMacOS) {
        return await _showMacOSNotification(title, body, iconPath);
      } else if (Platform.isLinux) {
        return await _showLinuxNotification(title, body, iconPath);
      } else {
        LoggerService.warning('Нативные уведомления не поддерживаются на данной платформе');
        return false;
      }
    } catch (e) {
      LoggerService.error('Ошибка при отображении нативного уведомления', e);
      return false;
    }
  }
  
  /// Отображение нативного уведомления в Windows
  static Future<bool> _showWindowsNotification(String title, String body, String? iconPath) async {
    try {
      // Windows 10 и выше поддерживает PowerShell для отправки уведомлений
      final script = '''
      [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
      [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
      [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

      \$template = @"
      <toast>
          <visual>
              <binding template="ToastGeneric">
                  <text>$title</text>
                  <text>$body</text>
              </binding>
          </visual>
      </toast>
      "@

      \$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
      \$xml.LoadXml(\$template)
      \$toast = New-Object Windows.UI.Notifications.ToastNotification \$xml
      [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Noriko VPN").Show(\$toast)
      ''';
      
      // Использование прямого вызова PowerShell
      final result = await Process.run('powershell', ['-Command', script], runInShell: true);
      
      if (result.exitCode != 0) {
        LoggerService.error('Ошибка PowerShell: ${result.stderr}');
        
        // Альтернативный метод для старых версий Windows
        // Используем CommandPrompt для отображения всплывающего уведомления
        final alternativeResult = await Process.run(
          'cmd', 
          ['/c', 'msg', '%username%', '$title: $body'], 
          runInShell: true
        );
        
        if (alternativeResult.exitCode != 0) {
          LoggerService.error('Альтернативный метод также не сработал: ${alternativeResult.stderr}');
          return false;
        }
      }
      
      LoggerService.info('Уведомление Windows отправлено успешно');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при отображении Windows-уведомления', e);
      return false;
    }
  }

  /// Отображение нативного уведомления в macOS
  static Future<bool> _showMacOSNotification(String title, String body, String? iconPath) async {
    try {
      // osascript для отправки нативных уведомлений
      final String escapedTitle = title.replaceAll('"', '\\"');
      final String escapedBody = body.replaceAll('"', '\\"');
      
      final String script = '''
      display notification "$escapedBody" with title "$escapedTitle"
      ''';
      
      final result = await Process.run('osascript', ['-e', script]);
      
      if (result.exitCode != 0) {
        LoggerService.error('Ошибка osascript: ${result.stderr}');
        return false;
      }
      
      LoggerService.info('Уведомление macOS отправлено успешно');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при отображении macOS-уведомления', e);
      return false;
    }
  }

  /// Отображение нативного уведомления в Linux
  static Future<bool> _showLinuxNotification(String title, String body, String? iconPath) async {
    try {
      // Проверяем наличие notify-send
      final checkResult = await Process.run('which', ['notify-send']);
      
      if (checkResult.exitCode != 0) {
        LoggerService.error('notify-send не найден на системе');
        return false;
      }
      
      final args = <String>[
        '--app-name=Noriko VPN',
        title,
        body,
      ];
      
      if (iconPath != null) {
        args.add('--icon=$iconPath');
      }
      
      final result = await Process.run('notify-send', args);
      
      if (result.exitCode != 0) {
        LoggerService.error('Ошибка notify-send: ${result.stderr}');
        return false;
      }
      
      LoggerService.info('Уведомление Linux отправлено успешно');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при отображении Linux-уведомления', e);
      return false;
    }
  }

  /// Для тестирования - просто выводит сообщение в консоль
  static Future<bool> testNotification(String message) async {
    try {
      LoggerService.info('ТЕСТОВОЕ УВЕДОМЛЕНИЕ: $message');
      
      // Для Windows создаем файл на рабочем столе в качестве индикатора
      if (Platform.isWindows) {
        final homeDir = Platform.environment['USERPROFILE'];
        if (homeDir != null) {
          final testFile = File('$homeDir\\Desktop\\vpn_notification_test.txt');
          await testFile.writeAsString('Тестовое уведомление: $message\nВремя: ${DateTime.now().toString()}');
        }
      }
      
      return true;
    } catch (e) {
      LoggerService.error('Ошибка тестового уведомления', e);
      return false;
    }
  }
}