import 'dart:async';
import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

import '../../data/models/vpn_config.dart';
import '../constants/app_constants.dart';
import 'logger_service.dart';

// Определение нативных функций из DLL
typedef InitializeWinDivertFunc = int Function();
typedef AddUdpFiltersFunc = int Function();
typedef StartUdpProxyFunc = int Function(int proxyPort);
typedef CleanupWinDivertFunc = int Function();
typedef ConfigureVpnRoutingFunc = int Function(Pointer<Utf8> serverAddress, Pointer<Utf8> tapGateway);
typedef RestoreRoutingFunc = int Function();

class WindowsVpnService {
  // Singleton pattern
  static final WindowsVpnService _instance = WindowsVpnService._internal();
  factory WindowsVpnService() => _instance;
  WindowsVpnService._internal();

  // DLL и функции
  late DynamicLibrary _windivertHelper;
  late InitializeWinDivertFunc _initializeWinDivert;
  late AddUdpFiltersFunc _addUdpFilters;
  late StartUdpProxyFunc _startUdpProxy;
  late CleanupWinDivertFunc _cleanupWinDivert;
  late ConfigureVpnRoutingFunc _configureVpnRouting;
  late RestoreRoutingFunc _restoreRouting;

  bool _isInitialized = false;
  bool _isConnected = false;
  
  // Идентификаторы процессов VPN
  final List<int> _vpnProcessIds = [];
  
  // Mocked statistics for development (will be replaced with actual stats)
  final Map<String, int> _stats = {
    'downloadedBytes': 0,
    'uploadedBytes': 0,
    'ping': 30,
  };
  Timer? _statsTimer;
  
  // Initialize the service
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      LoggerService.info('Инициализация Windows VPN Service');
      
      // Load WinDivert helper DLL
      await _loadWinDivertHelper();
      
      // Check and ensure TAP adapter is installed
      await _ensureTapAdapter();
      
      _isInitialized = true;
      return true;
    } catch (e) {
      LoggerService.error('Ошибка инициализации Windows VPN Service', e);
      return false;
    }
  }
  
  // Load WinDivert helper DLL
  Future<void> _loadWinDivertHelper() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final dllPath = path.join(exeDir, 'windivert_helper.dll');
      
      LoggerService.info('Загрузка WinDivert helper из: $dllPath');
      
      if (!File(dllPath).existsSync()) {
        throw Exception('WinDivert helper DLL не найден: $dllPath');
      }
      
      _windivertHelper = DynamicLibrary.open(dllPath);
      
      // Bind functions
      _initializeWinDivert = _windivertHelper
          .lookupFunction<Int32 Function(), int Function()>('InitializeWinDivert');
      
      _addUdpFilters = _windivertHelper
          .lookupFunction<Int32 Function(), int Function()>('AddUdpFilters');
      
      _startUdpProxy = _windivertHelper
          .lookupFunction<Int32 Function(Int32), int Function(int)>('StartUdpProxy');
      
      _cleanupWinDivert = _windivertHelper
          .lookupFunction<Int32 Function(), int Function()>('CleanupWinDivert');
      
      _configureVpnRouting = _windivertHelper
          .lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
              int Function(Pointer<Utf8>, Pointer<Utf8>)>('ConfigureVpnRouting');
      
      _restoreRouting = _windivertHelper
          .lookupFunction<Int32 Function(), int Function()>('RestoreRouting');
      
      LoggerService.info('WinDivert helper загружен успешно');
    } catch (e) {
      LoggerService.error('Ошибка загрузки WinDivert helper', e);
      throw Exception('Не удалось загрузить WinDivert helper: $e');
    }
  }
  
  // Проверка и установка TAP-адаптера при необходимости
  Future<void> _ensureTapAdapter() async {
    try {
      // Проверка наличия TAP-адаптера
      final result = await Process.run('netsh', ['interface', 'show', 'interface']);
      
      if (!result.stdout.toString().contains('TAP-Windows Adapter')) {
        LoggerService.warning('TAP адаптер не обнаружен, установка...');
        
        // Путь к установщику
        final appDir = await getApplicationSupportDirectory();
        final installerPath = path.join(appDir.path, 'drivers', 'tap-windows-9.21.2.exe');
        
        // Проверка существования установщика
        if (!File(installerPath).existsSync()) {
          // Если установщика нет, копируем его из ресурсов
          await _extractTapInstaller(installerPath);
        }
        
        // Запуск установщика с правами администратора
        final installResult = await Process.run(
          'powershell',
          [
            '-Command',
            'Start-Process',
            '-FilePath',
            installerPath,
            '-ArgumentList',
            '/S',
            '-Verb',
            'RunAs',
            '-Wait'
          ],
          runInShell: true
        );
        
        if (installResult.exitCode != 0) {
          throw Exception('Ошибка установки TAP адаптера');
        }
        
        LoggerService.info('TAP адаптер установлен успешно');
      } else {
        LoggerService.info('TAP адаптер уже установлен');
      }
    } catch (e) {
      LoggerService.error('Ошибка проверки/установки TAP адаптера', e);
      throw Exception('Не удалось обеспечить наличие TAP адаптера: $e');
    }
  }
  
  // Извлечение установщика TAP из ресурсов
  Future<void> _extractTapInstaller(String destinationPath) async {
    try {
      // Создаем директорию, если не существует
      await Directory(path.dirname(destinationPath)).create(recursive: true);
      
      // Здесь должен быть код для извлечения файла из ресурсов
      // В реальном приложении нужно использовать Flutter asset bundle
      
      LoggerService.warning('Извлечение TAP установщика не реализовано');
      throw Exception('Извлечение TAP установщика не реализовано');
    } catch (e) {
      LoggerService.error('Ошибка извлечения TAP установщика', e);
      throw Exception('Ошибка извлечения TAP установщика: $e');
    }
  }
  
  // Подключение к VPN серверу
  Future<bool> connect(VpnConfig config) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) return false;
    }
    
    if (_isConnected) {
      LoggerService.warning('VPN уже подключен');
      return true;
    }
    
    try {
      LoggerService.info('Подключение к VPN серверу: ${config.displayName}');
      
      // Генерация конфигурационного файла для V2Ray/Trojan/Shadowsocks
      final configFile = await _generateConfigFile(config);
      
      // Запуск соответствующего клиента в зависимости от протокола
      bool clientStarted = false;
      
      switch (config.protocol.toLowerCase()) {
        case 'vless':
        case 'vmess':
          clientStarted = await _startV2Ray(configFile);
          break;
        case 'trojan':
          clientStarted = await _startTrojan(configFile);
          break;
        case 'shadowsocks':
        case 'ss':
          clientStarted = await _startShadowsocks(configFile);
          break;
        default:
          throw Exception('Неподдерживаемый протокол: ${config.protocol}');
      }
      
      if (!clientStarted) {
        throw Exception('Не удалось запустить VPN клиент');
      }
      
      // Инициализация WinDivert для перехвата UDP трафика
      final winDivertResult = _initializeWinDivert();
      if (winDivertResult != 1) {
        throw Exception('Ошибка инициализации WinDivert: $winDivertResult');
      }
      
      // Добавление фильтров для UDP
      final filtersResult = _addUdpFilters();
      if (filtersResult != 1) {
        throw Exception('Ошибка добавления UDP фильтров: $filtersResult');
      }
      
      // Запуск UDP прокси
      final udpProxyResult = _startUdpProxy(10810); // Порт для UDP
      if (udpProxyResult != 1) {
        throw Exception('Ошибка запуска UDP прокси: $udpProxyResult');
      }
      
      // Настройка маршрутизации
      final serverAddrPtr = config.address.toNativeUtf8();
      final tapGatewayPtr = '10.8.0.1'.toNativeUtf8();
      
      final routingResult = _configureVpnRouting(serverAddrPtr, tapGatewayPtr);
      
      malloc.free(serverAddrPtr);
      malloc.free(tapGatewayPtr);
      
      if (routingResult != 1) {
        throw Exception('Ошибка настройки маршрутизации: $routingResult');
      }
      
      // Запуск таймера для обновления статистики
      _startStatsTimer();
      
      _isConnected = true;
      LoggerService.info('VPN подключен успешно');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка подключения к VPN', e);
      // Выполняем очистку в случае ошибки
      await _cleanupOnError();
      return false;
    }
  }
  
  // Генерация конфигурационного файла
  Future<String> _generateConfigFile(VpnConfig config) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final configDir = path.join(appDir.path, AppConstants.configDir);
      
      // Создаем директорию, если не существует
      await Directory(configDir).create(recursive: true);
      
      final configFile = path.join(configDir, 'current_config.json');
      
      // Здесь должен быть код генерации конфигурации
      // Мы предполагаем, что этот код реализован в VpnConnectionManager
      
      return configFile;
    } catch (e) {
      LoggerService.error('Ошибка генерации конфигурационного файла', e);
      throw Exception('Ошибка генерации конфигурационного файла: $e');
    }
  }
  
  // Запуск V2Ray
  Future<bool> _startV2Ray(String configFile) async {
    try {
      // Путь к исполняемому файлу V2Ray
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final v2rayPath = path.join(exeDir, 'bin', 'v2ray', 'v2ray.exe');
      
      // Проверка существования исполняемого файла
      if (!File(v2rayPath).existsSync()) {
        throw Exception('V2Ray исполняемый файл не найден: $v2rayPath');
      }
      
      // Запуск процесса
      final process = await Process.start(
        v2rayPath,
        ['-config', configFile],
        mode: ProcessStartMode.detached
      );
      
      // Сохраняем PID для последующего завершения
      _vpnProcessIds.add(process.pid);
      
      LoggerService.info('V2Ray запущен с PID: ${process.pid}');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка запуска V2Ray', e);
      return false;
    }
  }
  
  // Запуск Trojan
  Future<bool> _startTrojan(String configFile) async {
    try {
      // Путь к исполняемому файлу Trojan
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final trojanPath = path.join(exeDir, 'bin', 'trojan', 'trojan.exe');
      
      // Проверка существования исполняемого файла
      if (!File(trojanPath).existsSync()) {
        throw Exception('Trojan исполняемый файл не найден: $trojanPath');
      }
      
      // Запуск процесса
      final process = await Process.start(
        trojanPath,
        ['-c', configFile],
        mode: ProcessStartMode.detached
      );
      
      // Сохраняем PID для последующего завершения
      _vpnProcessIds.add(process.pid);
      
      LoggerService.info('Trojan запущен с PID: ${process.pid}');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка запуска Trojan', e);
      return false;
    }
  }
  
  // Запуск Shadowsocks
  Future<bool> _startShadowsocks(String configFile) async {
    try {
      // Путь к исполняемому файлу Shadowsocks
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      final ssPath = path.join(exeDir, 'bin', 'shadowsocks', 'ss-local.exe');
      
      // Проверка существования исполняемого файла
      if (!File(ssPath).existsSync()) {
        throw Exception('Shadowsocks исполняемый файл не найден: $ssPath');
      }
      
      // Запуск процесса
      final process = await Process.start(
        ssPath,
        ['-c', configFile],
        mode: ProcessStartMode.detached
      );
      
      // Сохраняем PID для последующего завершения
      _vpnProcessIds.add(process.pid);
      
      LoggerService.info('Shadowsocks запущен с PID: ${process.pid}');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка запуска Shadowsocks', e);
      return false;
    }
  }
  
  // Отключение от VPN
  Future<bool> disconnect() async {
    if (!_isConnected) {
      return true;
    }
    
    try {
      LoggerService.info('Отключение от VPN');
      
      // Остановка таймера
      _stopStatsTimer();
      
      // Восстановление маршрутизации
      final routingResult = _restoreRouting();
      if (routingResult != 1) {
        LoggerService.error('Ошибка восстановления маршрутизации: $routingResult');
      }
      
      // Очистка WinDivert
      final cleanupResult = _cleanupWinDivert();
      if (cleanupResult != 1) {
        LoggerService.error('Ошибка очистки WinDivert: $cleanupResult');
      }
      
      // Завершение процессов
      for (final pid in _vpnProcessIds) {
        try {
          await Process.run('taskkill', ['/F', '/PID', '$pid']);
          LoggerService.info('Процесс с PID $pid завершен');
        } catch (e) {
          LoggerService.error('Ошибка завершения процесса с PID $pid', e);
        }
      }
      
      // Очистка списка процессов
      _vpnProcessIds.clear();
      
      _isConnected = false;
      LoggerService.info('VPN отключен успешно');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка отключения от VPN', e);
      return false;
    }
  }
  
  // Очистка ресурсов при ошибке
  Future<void> _cleanupOnError() async {
    try {
      // Остановка всех процессов
      for (final pid in _vpnProcessIds) {
        try {
          await Process.run('taskkill', ['/F', '/PID', '$pid']);
        } catch (e) {
          // Игнорируем ошибки при очистке
        }
      }
      
      // Очистка списка процессов
      _vpnProcessIds.clear();
      
      // Попытка очистки WinDivert
      try {
        _cleanupWinDivert();
      } catch (e) {
        // Игнорируем ошибки при очистке
      }
      
      // Попытка восстановления маршрутизации
      try {
        _restoreRouting();
      } catch (e) {
        // Игнорируем ошибки при очистке
      }
    } catch (e) {
      // Игнорируем любые ошибки в очистке
    }
  }
  
  // Проверка состояния подключения
  bool isConnected() {
    return _isConnected;
  }
  
  // Запуск таймера для симуляции обновления статистики
  void _startStatsTimer() {
    _statsTimer?.cancel();
    
    // Сброс статистики
    _stats['downloadedBytes'] = 0;
    _stats['uploadedBytes'] = 0;
    
    // Запуск таймера для обновления статистики каждую секунду
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // Увеличиваем статистику загрузки и выгрузки случайным образом
      _stats['downloadedBytes'] = (_stats['downloadedBytes']! + 
          (5000 + (DateTime.now().millisecondsSinceEpoch % 10000))).clamp(0, 1000000000);
      
      _stats['uploadedBytes'] = (_stats['uploadedBytes']! + 
          (1000 + (DateTime.now().millisecondsSinceEpoch % 5000))).clamp(0, 1000000000);
      
      // Случайный пинг от 30 до 130 мс
      _stats['ping'] = 30 + (DateTime.now().millisecondsSinceEpoch % 100);
    });
  }
  
  // Остановка таймера статистики
  void _stopStatsTimer() {
    _statsTimer?.cancel();
    _statsTimer = null;
  }
  
  // Получение статистики трафика
  Map<String, dynamic> getTrafficStats() {
    return {
      'downloadedBytes': _stats['downloadedBytes'] ?? 0,
      'uploadedBytes': _stats['uploadedBytes'] ?? 0,
      'ping': _stats['ping'] ?? 0,
    };
  }
  
  // Освобождение ресурсов
  void dispose() {
    // Отключаем VPN если подключен
    if (_isConnected) {
      disconnect();
    }
    
    // Останавливаем таймер
    _stopStatsTimer();
  }
}