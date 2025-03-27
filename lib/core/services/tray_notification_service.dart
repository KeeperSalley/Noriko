import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'logger_service.dart';
import 'app_settings_service.dart';
import '../constants/app_constants.dart';
import 'system_tray_service.dart';

/// Сервис для отображения уведомлений через системный трей
class TrayNotificationService {
  // Ссылка на экземпляр сервиса трея
  final SystemTrayService _systemTrayService;
  
  // Флаг инициализации
  bool _initialized = false;
  
  // Исходное значение подсказки
  String _originalTooltip = AppConstants.appName;
  
  // Очередь уведомлений
  final List<Map<String, String>> _notificationQueue = [];
  
  // Флаг, показывающий, отображается ли уведомление
  bool _isShowingNotification = false;
  
  // Флаг для отслеживания, была ли восстановлена оригинальная подсказка
  bool _tooltipRestored = true;
  
  // Длительность показа уведомления
  final Duration _notificationDuration = const Duration(seconds: 5);
  
  // Конструктор
  TrayNotificationService(this._systemTrayService);
  
  /// Инициализация сервиса
  Future<void> initialize() async {
    if (_initialized) return;
    
    try {
      // Сохраняем исходное значение подсказки
      _originalTooltip = AppConstants.appName;
      
      _initialized = true;
      LoggerService.info('Сервис уведомлений через трей инициализирован');
    } catch (e) {
      LoggerService.error('Ошибка при инициализации сервиса уведомлений через трей', e);
    }
  }
  
  /// Показать уведомление через подсказку в трее
  Future<void> showNotification({
    required String title,
    required String body,
    Duration? duration,
  }) async {
    // Если не на десктопной платформе, просто выходим
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      return;
    }
    
    try {
      // Проверяем, включены ли уведомления в настройках
      final bool enableNotifications = await AppSettingsService.areNotificationsEnabled();
      if (!enableNotifications) {
        LoggerService.info('Уведомления отключены в настройках. Уведомление не будет показано.');
        return;
      }
      
      // Инициализируем, если не инициализировано
      if (!_initialized) {
        await initialize();
      }
      
      // Формируем текст уведомления
      final String notificationText = '$title: $body';
      
      // Добавляем уведомление в очередь
      _notificationQueue.add({
        'text': notificationText,
        'duration': (duration ?? _notificationDuration).inMilliseconds.toString(),
      });
      
      // Если уже показывается уведомление, то просто выходим
      // Следующее уведомление будет показано после завершения текущего
      if (_isShowingNotification) {
        LoggerService.info('Уведомление добавлено в очередь: $notificationText');
        return;
      }
      
      // Запускаем обработку очереди
      _processNotificationQueue();
      
    } catch (e) {
      LoggerService.error('Ошибка при показе уведомления через трей', e);
    }
  }
  
  /// Обработка очереди уведомлений
  Future<void> _processNotificationQueue() async {
    if (_notificationQueue.isEmpty) {
      _isShowingNotification = false;
      return;
    }
    
    _isShowingNotification = true;
    
    try {
      // Берем первое уведомление из очереди
      final notification = _notificationQueue.removeAt(0);
      final text = notification['text']!;
      final duration = Duration(milliseconds: int.parse(notification['duration']!));
      
      // Обновляем подсказку
      await _systemTrayService.updateTooltip(text);
      _tooltipRestored = false;
      
      // Ждем заданное время
      await Future.delayed(duration);
      
      // Восстанавливаем исходную подсказку, если подсказка не была изменена другим уведомлением
      if (!_tooltipRestored) {
        await _systemTrayService.updateTooltip(_originalTooltip);
        _tooltipRestored = true;
      }
      
      // Обрабатываем следующее уведомление в очереди
      await _processNotificationQueue();
      
    } catch (e) {
      LoggerService.error('Ошибка при обработке очереди уведомлений', e);
      _isShowingNotification = false;
      
      // Восстанавливаем подсказку при ошибке
      if (!_tooltipRestored) {
        await _systemTrayService.updateTooltip(_originalTooltip);
        _tooltipRestored = true;
      }
    }
  }
  
  /// Сброс всех уведомлений и возврат к исходной подсказке
  Future<void> resetTooltip() async {
    try {
      _notificationQueue.clear();
      await _systemTrayService.updateTooltip(_originalTooltip);
      _tooltipRestored = true;
      _isShowingNotification = false;
    } catch (e) {
      LoggerService.error('Ошибка при сбросе подсказки', e);
    }
  }
}