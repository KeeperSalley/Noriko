import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';
import '../constants/app_constants.dart';
import 'logger_service.dart';
import 'app_settings_service.dart';
import 'tray_notification_service.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  static bool _isInitialized = false;
  
  // Ссылка на сервис уведомлений трея
  static TrayNotificationService? _trayNotificationService;
  
  // Установка сервиса уведомлений трея
  static void setTrayNotificationService(TrayNotificationService service) {
    _trayNotificationService = service;
  }
  
  // Инициализация сервиса уведомлений
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Инициализируем сервис уведомлений трея, если он доступен
      if (_trayNotificationService != null) {
        await _trayNotificationService!.initialize();
      }
      
      // Для мобильных платформ инициализируем локальные уведомления
      if (Platform.isAndroid || Platform.isIOS) {
        // Настройки для Android
        const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
        
        // Настройки для iOS
        const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        
        // Настройки для macOS
        const DarwinInitializationSettings macOSSettings = DarwinInitializationSettings();
        
        // Объединение настроек
        final InitializationSettings initSettings = InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
          macOS: macOSSettings,
        );
        
        // Инициализация плагина
        await _notificationsPlugin.initialize(
          initSettings,
          onDidReceiveNotificationResponse: _onNotificationTap,
        );
      }
      
      _isInitialized = true;
      LoggerService.info('Сервис уведомлений инициализирован');
    } catch (e) {
      LoggerService.error('Ошибка при инициализации сервиса уведомлений', e);
    }
  }
  
  // Обработка нажатия на уведомление
  static void _onNotificationTap(NotificationResponse details) async {
    try {
      LoggerService.info('Нажатие на уведомление: ${details.payload ?? "без данных"}');
      
      // Восстанавливаем окно из свернутого состояния при нажатии на уведомление
      final bool isVisible = await windowManager.isVisible();
      if (!isVisible) {
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (e) {
      LoggerService.error('Ошибка при обработке нажатия на уведомление', e);
    }
  }
  
  // Показ уведомления с проверкой настроек
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    int id = 0,
  }) async {
    try {
      // Проверяем, включены ли уведомления в настройках
      final bool enableNotifications = await AppSettingsService.areNotificationsEnabled();
      if (!enableNotifications) {
        LoggerService.info('Уведомления отключены в настройках. Уведомление не будет показано.');
        return;
      }
      
      // Инициализируем сервис, если еще не инициализирован
      if (!_isInitialized) {
        await initialize();
      }
      
      // На десктоп-платформах используем уведомления трея
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        if (_trayNotificationService != null) {
          await _trayNotificationService!.showNotification(
            title: title,
            body: body,
          );
          return;
        }
      }
      
      // На мобильных платформах используем обычные уведомления
      if (Platform.isAndroid || Platform.isIOS) {
        // Настройки для Android
        const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
          'vpn_notifications',
          'VPN Notifications',
          channelDescription: 'Уведомления о статусе VPN подключения',
          importance: Importance.high,
          priority: Priority.high,
          enableLights: true,
          enableVibration: true,
        );
        
        // Настройки для iOS/macOS
        const DarwinNotificationDetails darwinDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        );
        
        // Для мобильных платформ генерируем уникальный ID для уведомления
        final int notificationId = id > 0 ? id : DateTime.now().millisecondsSinceEpoch.remainder(100000);
        
        // Создаем детали уведомления в зависимости от платформы
        NotificationDetails? notificationDetails;
        
        if (Platform.isAndroid) {
          notificationDetails = const NotificationDetails(android: androidDetails);
        } else if (Platform.isIOS) {
          notificationDetails = const NotificationDetails(iOS: darwinDetails);
        }
        
        // Если есть подходящий способ показа уведомления, используем его
        if (notificationDetails != null) {
          await _notificationsPlugin.show(
            notificationId,
            title,
            body,
            notificationDetails,
            payload: payload,
          );
        }
      }
      
      LoggerService.info('Показано уведомление: $title - $body');
    } catch (e) {
      LoggerService.error('Ошибка при показе уведомления', e);
    }
  }
  
  // Показ уведомления о подключении к серверу
  static Future<void> showConnectionNotification(String serverName) async {
    await showNotification(
      title: 'Подключение VPN',
      body: 'Подключено к серверу $serverName',
      payload: 'connection_success',
    );
  }
  
  // Показ уведомления об отключении от сервера
  static Future<void> showDisconnectionNotification() async {
    await showNotification(
      title: 'Отключение VPN',
      body: 'VPN-соединение разорвано',
      payload: 'disconnection',
    );
  }
  
  // Показ уведомления о проблеме с подключением
  static Future<void> showConnectionErrorNotification(String error) async {
    await showNotification(
      title: 'Ошибка подключения',
      body: 'Не удалось подключиться: $error',
      payload: 'connection_error',
    );
  }
}