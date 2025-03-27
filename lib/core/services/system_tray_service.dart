import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../constants/app_constants.dart';
import 'logger_service.dart';
import 'app_settings_service.dart';

class SystemTrayService {
  final SystemTray _systemTray = SystemTray();
  final AppWindow _appWindow = AppWindow();
  final Menu _contextMenu = Menu();
  
  // Флаг, показывающий, инициализирован ли системный трей
  bool _isInitialized = false;
  
  // Инициализация системного трея
  Future<void> initSystemTray() async {
    if (_isInitialized) return;
    
    try {
      // Получаем путь к иконке в зависимости от платформы
      String iconPath;
      if (Platform.isWindows) {
        // Для Windows используем .ico файл
        iconPath = path.join(path.dirname(Platform.resolvedExecutable), 'data', 'flutter_assets', 'assets', 'icons', 'app_icon.ico');
      } else if (Platform.isLinux) {
        // Для Linux используем .png файл
        iconPath = path.join(path.dirname(Platform.resolvedExecutable), 'data', 'flutter_assets', 'assets', 'icons', 'app_icon.png');
      } else if (Platform.isMacOS) {
        // Для macOS используем .png файл в зависимости от темы
        final isDarkMode = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
        iconPath = path.join(path.dirname(Platform.resolvedExecutable), 'Resources', 'flutter_assets', 'assets', 'icons', 
          isDarkMode ? 'app_icon.png' : 'app_icon.png');
      } else {
        // Для других платформ (если вдруг потребуется)
        throw UnsupportedError('Системный трей не поддерживается на данной платформе');
      }
      
      // Инициализируем системный трей с заданной иконкой
      await _systemTray.initSystemTray(
        title: AppConstants.appName,
        iconPath: iconPath,
        toolTip: AppConstants.appName,
      );
      
      // Создаем контекстное меню для системного трея
      await _contextMenu.buildFrom([
        MenuItemLabel(
          label: 'Показать ${AppConstants.appName}',
          onClicked: (menuItem) async {
            await windowManager.show();
            await windowManager.focus();
          },
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: 'Выход',
          onClicked: (menuItem) async {
            await windowManager.destroy();
          },
        ),
      ]);
      
      // Устанавливаем созданное контекстное меню для системного трея
      await _systemTray.setContextMenu(_contextMenu);
      
      // Устанавливаем обработчик событий системного трея
      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          // По левому клику на иконку трея показываем окно
          _handleTrayIconClick();
        } else if (eventName == kSystemTrayEventRightClick) {
          // По правому клику показываем контекстное меню
          _systemTray.popUpContextMenu();
        }
      });
      
      LoggerService.info('Системный трей успешно инициализирован');
      _isInitialized = true;
    } catch (e) {
      LoggerService.error('Ошибка при инициализации системного трея', e);
    }
  }
  
  // Обработчик клика по иконке в системном трее
  Future<void> _handleTrayIconClick() async {
    try {
      // При клике на иконку трея показываем окно
      final isVisible = await windowManager.isVisible();
      if (isVisible) {
        // Если окно уже видимо, просто даем ему фокус
        await windowManager.focus();
      } else {
        // Если окно скрыто, показываем его и даем фокус
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (e) {
      LoggerService.error('Ошибка при обработке клика по иконке трея', e);
    }
  }
  
  // Сворачивание приложения в трей
  Future<void> minimizeToTray() async {
    try {
      if (!_isInitialized) {
        await initSystemTray();
      }
      
      await windowManager.hide();
      LoggerService.info('Приложение свернуто в трей');
    } catch (e) {
      LoggerService.error('Ошибка при сворачивании в трей', e);
    }
  }
  
  // Проверка, активна ли настройка сворачивания в трей
  static Future<bool> isMinimizeToTrayEnabled() async {
    try {
      final settings = await AppSettingsService.getSettings();
      return settings[AppSettingsService.keyMinimizeToTray] ?? AppSettingsService.defaultMinimizeToTray;
    } catch (e) {
      LoggerService.error('Ошибка при проверке настройки сворачивания в трей', e);
      // По умолчанию возвращаем true, если не удалось получить настройку
      return true;
    }
  }
  
  // Метод для обновления подсказки в трее
  Future<void> updateTooltip(String message) async {
    try {
      if (!_isInitialized) {
        await initSystemTray();
      }
      
      // Обновляем подсказку с новым сообщением
      await _systemTray.setToolTip(message);
      
      LoggerService.info('Обновлена подсказка в трее: $message');
    } catch (e) {
      LoggerService.error('Ошибка при обновлении подсказки в трее', e);
    }
  }
  
  // Освобождение ресурсов
  Future<void> dispose() async {
    try {
      if (_isInitialized) {
        await _systemTray.destroy();
        _isInitialized = false;
      }
    } catch (e) {
      LoggerService.error('Ошибка при освобождении ресурсов системного трея', e);
    }
  }
}