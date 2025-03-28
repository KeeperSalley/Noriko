import 'dart:async';
import 'dart:io';
import 'dart:ffi';
import 'dart:convert';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

import '../../data/models/vpn_config.dart';
import '../constants/app_constants.dart';
import 'logger_service.dart';

class WindowsVpnService {
  // Singleton pattern
  static final WindowsVpnService _instance = WindowsVpnService._internal();
  factory WindowsVpnService() => _instance;
  WindowsVpnService._internal();

  bool _isInitialized = false;
  bool _isConnected = false;
  
  // DLL-функции для работы с WinDivert
  late DynamicLibrary _winDivertLib;
  late Function _winDivertOpen;
  late Function _winDivertClose;
  late Function _winDivertRecv;
  late Function _winDivertSend;
  late Function _winDivertSetParam;
  
  // Идентификаторы процессов для обработки
  final List<int> _processIds = [];
  
  // Инициализация сервиса
  Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    try {
      LoggerService.info('Инициализация Windows VPN сервиса');
      
      // Загрузка WinDivert DLL для перехвата и перенаправления сетевого трафика
      await _loadWinDivertLibrary();
      
      // Инициализация TAP-адаптера для туннелирования
      await _initializeTapAdapter();
      
      _isInitialized = true;
      return true;
    } catch (e) {
      LoggerService.error('Ошибка инициализации Windows VPN сервиса', e);
      return false;
    }
  }
  
  // Загрузка WinDivert библиотеки
  Future<void> _loadWinDivertLibrary() async {
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = path.dirname(exePath);
      String libPath = path.join(exeDir, 'lib', 'WinDivert.dll');
      
      LoggerService.info('Загрузка WinDivert из: $libPath');
      _winDivertLib = DynamicLibrary.open(libPath);
      
      // Инициализация функций
      _winDivertOpen = _winDivertLib.lookupFunction<
        IntPtr Function(Pointer<Utf8>, Int32, Int16, Int64),
        int Function(Pointer<Utf8>, int, int, int)>('WinDivertOpen');
        
      _winDivertClose = _winDivertLib.lookupFunction<
        Int32 Function(IntPtr),
        int Function(int)>('WinDivertClose');
        
      _winDivertRecv = _winDivertLib.lookupFunction<
        Int32 Function(IntPtr, Pointer<Void>, Uint32, Pointer<Void>, Pointer<Uint32>),
        int Function(int, Pointer<Void>, int, Pointer<Void>, Pointer<Uint32>)>('WinDivertRecv');
        
      _winDivertSend = _winDivertLib.lookupFunction<
        Int32 Function(IntPtr, Pointer<Void>, Uint32, Pointer<Void>, Pointer<Uint32>),
        int Function(int, Pointer<Void>, int, Pointer<Void>, Pointer<Uint32>)>('WinDivertSend');
        
      _winDivertSetParam = _winDivertLib.lookupFunction<
        Int32 Function(IntPtr, Int32, Uint64),
        int Function(int, int, int)>('WinDivertSetParam');
        
      LoggerService.info('WinDivert загружен успешно');
    } catch (e) {
      LoggerService.error('Ошибка загрузки WinDivert библиотеки', e);
      throw Exception('Не удалось загрузить WinDivert: $e');
    }
  }
  
  // Инициализация TAP-адаптера для туннелирования
  Future<void> _initializeTapAdapter() async {
    try {
      // Проверка наличия TAP-адаптера
      bool tapExists = await _checkTapAdapterExists();
      
      if (!tapExists) {
        LoggerService.warning('TAP-адаптер не обнаружен, установка...');
        await _installTapAdapter();
      } else {
        LoggerService.info('TAP-адаптер обнаружен');
      }
      
      // Настройка TAP-адаптера
      await _configureTapAdapter();
      
    } catch (e) {
      LoggerService.error('Ошибка инициализации TAP-адаптера', e);
      throw Exception('Не удалось инициализировать TAP-адаптер: $e');
    }
  }
  
  // Проверка наличия TAP-адаптера
  Future<bool> _checkTapAdapterExists() async {
    final result = await Process.run('netsh', ['interface', 'show', 'interface']);
    return result.stdout.toString().contains('TAP-Windows Adapter');
  }
  
  // Установка TAP-адаптера
  Future<void> _installTapAdapter() async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final tapInstallerPath = path.join(appDir.path, 'drivers', 'tap-windows-9.21.2.exe');
      
      // Проверка существования установщика
      if (!await File(tapInstallerPath).exists()) {
        // Если установщика нет, извлекаем его из ресурсов приложения
        await _extractTapInstaller(tapInstallerPath);
      }
      
      // Запуск установщика с правами администратора
      final result = await Process.run(
        'powershell', 
        ['-Command', 'Start-Process', '-FilePath', tapInstallerPath, 
         '-ArgumentList', '/S', '-Verb', 'RunAs', '-Wait'],
        runInShell: true
      );
      
      if (result.exitCode != 0) {
        LoggerService.error('Ошибка установки TAP-адаптера: ${result.stderr}');
        throw Exception('Не удалось установить TAP-адаптер');
      }
      
      LoggerService.info('TAP-адаптер успешно установлен');
    } catch (e) {
      LoggerService.error('Ошибка при установке TAP-адаптера', e);
      throw Exception('Не удалось установить TAP-адаптер: $e');
    }
  }
  
  // Извлечение установщика TAP-адаптера из ресурсов приложения
  Future<void> _extractTapInstaller(String destinationPath) async {
    try {
      final directory = path.dirname(destinationPath);
      await Directory(directory).create(recursive: true);
      
      // Здесь должен быть код для извлечения установщика из ресурсов
      // Но для этого примера мы просто создадим пустой файл
      await File(destinationPath).writeAsBytes([]);
      
      LoggerService.info('Установщик TAP-адаптера извлечен в: $destinationPath');
    } catch (e) {
      LoggerService.error('Ошибка при извлечении установщика TAP-адаптера', e);
      throw Exception('Не удалось извлечь установщик TAP-адаптера: $e');
    }
  }
  
  // Настройка TAP-адаптера
  Future<void> _configureTapAdapter() async {
    try {
      // Получение имени TAP-адаптера
      final result = await Process.run('netsh', ['interface', 'show', 'interface']);
      final output = result.stdout.toString();
      
      // Парсинг вывода для поиска TAP-адаптера
      final lines = output.split('\n');
      String tapAdapterName = '';
      
      for (var line in lines) {
        if (line.contains('TAP-Windows Adapter')) {
          final parts = line.trim().split(' ');
          tapAdapterName = parts.last;
          break;
        }
      }
      
      if (tapAdapterName.isEmpty) {
        throw Exception('Не удалось найти TAP-адаптер');
      }
      
      // Настройка IP-адреса TAP-адаптера
      final configResult = await Process.run(
        'netsh', 
        ['interface', 'ip', 'set', 'address', 
         'name=$tapAdapterName', 'static', '10.8.0.2', '255.255.255.0'],
        runInShell: true
      );
      
      if (configResult.exitCode != 0) {
        LoggerService.error('Ошибка настройки TAP-адаптера: ${configResult.stderr}');
        throw Exception('Не удалось настроить TAP-адаптер');
      }
      
      LoggerService.info('TAP-адаптер успешно настроен');
    } catch (e) {
      LoggerService.error('Ошибка при настройке TAP-адаптера', e);
      throw Exception('Не удалось настроить TAP-адаптер: $e');
    }
  }
  
  // Подключение VPN с определенной конфигурацией
  Future<bool> connect(VpnConfig config) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      LoggerService.info('Подключение к VPN: ${config.displayName}');
      
      // Генерация конфигурационного файла для выбранного протокола
      final configFile = await _generateConfigFile(config);
      
      // Запуск процесса VPN в зависимости от протокола
      bool success = false;
      
      switch (config.protocol.toLowerCase()) {
        case 'vless':
        case 'vmess':
          success = await _startV2Ray(configFile);
          break;
        case 'trojan':
          success = await _startTrojan(configFile);
          break;
        case 'shadowsocks':
        case 'ss':
          success = await _startShadowsocks(configFile);
          break;
        default:
          throw Exception('Неподдерживаемый протокол: ${config.protocol}');
      }
      
      if (success) {
        // Настройка маршрутизации для перенаправления трафика
        await _configureRouting(config);
        
        _isConnected = true;
        LoggerService.info('VPN подключен успешно');
        return true;
      } else {
        LoggerService.error('Ошибка подключения VPN');
        return false;
      }
    } catch (e) {
      LoggerService.error('Ошибка при подключении VPN', e);
      return false;
    }
  }
  
  // Генерация конфигурационного файла
  Future<String> _generateConfigFile(VpnConfig config) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final configDir = path.join(appDir.path, AppConstants.configDir);
      
      // Создаем директорию, если она не существует
      await Directory(configDir).create(recursive: true);
      
      final configFile = path.join(configDir, 'current_config.json');
      
      // Генерируем конфигурацию в зависимости от протокола
      String configContent = '';
      
      switch (config.protocol.toLowerCase()) {
        case 'vless':
        case 'vmess':
          configContent = _generateV2RayConfig(config);
          break;
        case 'trojan':
          configContent = _generateTrojanConfig(config);
          break;
        case 'shadowsocks':
        case 'ss':
          configContent = _generateShadowsocksConfig(config);
          break;
        default:
          throw Exception('Неподдерживаемый протокол: ${config.protocol}');
      }
      
      // Записываем конфигурацию в файл
      await File(configFile).writeAsString(configContent);
      
      LoggerService.info('Конфигурационный файл сгенерирован: $configFile');
      return configFile;
    } catch (e) {
      LoggerService.error('Ошибка при генерации конфигурационного файла', e);
      throw Exception('Не удалось сгенерировать конфигурационный файл: $e');
    }
  }
  
  // Генерация конфигурации V2Ray
  String _generateV2RayConfig(VpnConfig config) {
    // Создание базовой конфигурации V2Ray с улучшенной поддержкой UDP
    final Map<String, dynamic> v2rayConfig = {
      "log": {
        "loglevel": "warning",
        "access": "access.log",
        "error": "error.log"
      },
      "inbounds": [
        {
          "port": 10808,
          "listen": "127.0.0.1",
          "protocol": "socks",
          "settings": {
            "udp": true,
            "auth": "noauth"
          },
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"]
          }
        },
        {
          "port": 10809,
          "listen": "127.0.0.1",
          "protocol": "http",
          "settings": {},
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"]
          }
        },
        // Добавляем UDP порт для более надежного туннелирования UDP трафика
        {
          "port": 10810,
          "listen": "127.0.0.1",
          "protocol": "dokodemo-door",
          "settings": {
            "address": "1.1.1.1",
            "port": 53,
            "network": "udp",
            "timeout": 30,
            "followRedirect": true
          },
          "sniffing": {
            "enabled": true,
            "destOverride": ["http", "tls", "quic"]
          }
        }
      ],
      "outbounds": [
        {
          "protocol": config.protocol.toLowerCase(),
          "settings": {
            "vnext": [
              {
                "address": config.address,
                "port": config.port,
                "users": [
                  {
                    "id": config.id,
                    "encryption": config.params["encryption"] ?? "none",
                    "flow": config.params["flow"] ?? "",
                    "security": config.params["security"] ?? "none"
                  }
                ]
              }
            ]
          },
          "streamSettings": {
            "network": config.params["type"] ?? "tcp",
            "security": config.params["security"] ?? "none",
            "tlsSettings": config.params["security"] == "tls" ? {
              "serverName": config.params["sni"] ?? config.address,
              "allowInsecure": config.params["allowInsecure"] == "true"
            } : null,
            "wsSettings": config.params["type"] == "ws" ? {
              "path": config.params["path"] ?? "/",
              "headers": {
                "Host": config.params["host"] ?? config.address
              }
            } : null,
            "tcpSettings": config.params["type"] == "tcp" ? {
              "header": {
                "type": "none"
              }
            } : null,
            "kcpSettings": config.params["type"] == "kcp" ? {
              "mtu": 1350,
              "tti": 50,
              "uplinkCapacity": 12,
              "downlinkCapacity": 100,
              "congestion": false,
              "readBufferSize": 2,
              "writeBufferSize": 2,
              "header": {
                "type": "none"
              }
            } : null,
            "grpcSettings": config.params["type"] == "grpc" ? {
              "serviceName": config.params["serviceName"] ?? "",
              "multiMode": config.params["multiMode"] == "true"
            } : null
          },
          "mux": {
            "enabled": true,
            "concurrency": 8
          },
          "tag": "proxy"
        },
        {
          "protocol": "freedom",
          "settings": {
            "domainStrategy": "UseIP", // Использовать IP для доменов
            "redirect": ":0",
            "userLevel": 0
          },
          "tag": "direct"
        },
        {
          "protocol": "blackhole",
          "settings": {},
          "tag": "block"
        }
      ],
      "routing": {
        "domainStrategy": "IPIfNonMatch",
        "domainMatcher": "mph",
        "rules": [
          // Правило для DNS-запросов
          {
            "type": "field",
            "port": 53,
            "network": "udp",
            "outboundTag": "proxy"
          },
          // Правило для приватных IP-адресов
          {
            "type": "field",
            "ip": ["geoip:private"],
            "outboundTag": "direct"
          },
          // Правило для блокировки рекламы
          {
            "type": "field",
            "domain": ["geosite:category-ads"],
            "outboundTag": "block"
          },
          // Правило по умолчанию - всё через прокси
          {
            "type": "field",
            "outboundTag": "proxy"
          }
        ]
      },
      // DNS конфигурация для предотвращения утечек
      "dns": {
        "servers": [
          "8.8.8.8", // Google DNS через прокси
          "1.1.1.1", // Cloudflare DNS через прокси
          {
            "address": "114.114.114.114", // Китайский DNS напрямую
            "port": 53,
            "domains": ["geosite:cn"]
          },
          "localhost"
        ],
        "tag": "dns-out"
      },
    };
    
    return jsonEncode(v2rayConfig);
  }
  
  // Генерация конфигурации Trojan
  String _generateTrojanConfig(VpnConfig config) {
    // TODO: Реализовать генерацию конфигурации Trojan
    return '{}';
  }
  
  // Генерация конфигурации Shadowsocks
  String _generateShadowsocksConfig(VpnConfig config) {
    // TODO: Реализовать генерацию конфигурации Shadowsocks
    return '{}';
  }
  
  // Запуск V2Ray
  Future<bool> _startV2Ray(String configFile) async {
    try {
      final appDir = await getApplicationSupportDirectory();
      final v2rayExePath = path.join(appDir.path, 'bin', 'v2ray.exe');
      
      // Проверка существования исполняемого файла
      if (!await File(v2rayExePath).exists()) {
        LoggerService.error('V2Ray не найден: $v2rayExePath');
        throw Exception('V2Ray не найден');
      }
      
      // Запуск V2Ray процесса
      final process = await Process.start(
        v2rayExePath,
        ['-config', configFile],
        mode: ProcessStartMode.detached
      );
      
      // Сохраняем PID для последующего завершения
      _processIds.add(process.pid);
      
      LoggerService.info('V2Ray запущен с PID: ${process.pid}');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при запуске V2Ray', e);
      return false;
    }
  }
  
  // Запуск Trojan
  Future<bool> _startTrojan(String configFile) async {
    // TODO: Реализовать запуск Trojan
    return false;
  }
  
  // Запуск Shadowsocks
  Future<bool> _startShadowsocks(String configFile) async {
    // TODO: Реализовать запуск Shadowsocks
    return false;
  }
  
  // Настройка маршрутизации для перенаправления трафика через VPN
  Future<void> _configureRouting(VpnConfig config) async {
    try {
      LoggerService.info('Настройка маршрутизации для VPN');
      
      // Сохранение текущего шлюза по умолчанию
      final defaultGatewayResult = await Process.run(
        'powershell',
        ['-Command', '(Get-NetRoute -DestinationPrefix "0.0.0.0/0").NextHop'],
        runInShell: true
      );
      
      final defaultGateway = defaultGatewayResult.stdout.toString().trim();
      LoggerService.info('Текущий шлюз по умолчанию: $defaultGateway');
      
      // Добавление маршрута для сервера VPN через стандартный шлюз
      await Process.run(
        'route',
        ['add', config.address, 'mask', '255.255.255.255', defaultGateway, 'metric', '1'],
        runInShell: true
      );
      
      // Изменение маршрута по умолчанию на VPN-туннель
      await Process.run(
        'route',
        ['change', '0.0.0.0', 'mask', '0.0.0.0', '10.8.0.1', 'metric', '5'],
        runInShell: true
      );
      
      // Настройка DNS-серверов для предотвращения утечек
      await Process.run(
        'powershell',
        ['-Command', 'Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "1.1.1.1","8.8.8.8"'],
        runInShell: true
      );
      
      LoggerService.info('Маршрутизация настроена успешно');
    } catch (e) {
      LoggerService.error('Ошибка при настройке маршрутизации', e);
      throw Exception('Не удалось настроить маршрутизацию: $e');
    }
  }
  
  // Отключение VPN
  Future<bool> disconnect() async {
    if (!_isConnected) {
      return true;
    }
    
    try {
      LoggerService.info('Отключение VPN');
      
      // Остановка процессов VPN
      for (var pid in _processIds) {
        await Process.run(
          'taskkill',
          ['/F', '/PID', '$pid'],
          runInShell: true
        );
      }
      
      // Очистка списка процессов
      _processIds.clear();
      
      // Восстановление маршрутизации
      await _restoreRouting();
      
      _isConnected = false;
      LoggerService.info('VPN отключен успешно');
      return true;
    } catch (e) {
      LoggerService.error('Ошибка при отключении VPN', e);
      return false;
    }
  }
  
  // Восстановление маршрутизации
  Future<void> _restoreRouting() async {
    try {
      // Восстановление маршрута по умолчанию
      final defaultGatewayResult = await Process.run(
        'powershell',
        ['-Command', "(Get-NetIPConfiguration | Where-Object {\$_.IPv4DefaultGateway -ne \$null -and \$_.NetAdapter.Status -ne 'Disconnected'}).IPv4DefaultGateway.NextHop"],
        runInShell: true
      );
      
      final defaultGateway = defaultGatewayResult.stdout.toString().trim();
      
      if (defaultGateway.isNotEmpty) {
        // Восстановление маршрута по умолчанию
        await Process.run(
          'route',
          ['change', '0.0.0.0', 'mask', '0.0.0.0', defaultGateway, 'metric', '1'],
          runInShell: true
        );
        
        // Удаление всех маршрутов через VPN
        await Process.run(
          'route',
          ['delete', '10.8.0.1'],
          runInShell: true
        );
      }
      
      // Восстановление DNS-серверов
      await Process.run(
        'powershell',
        ['-Command', 'Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ResetServerAddresses'],
        runInShell: true
      );
      
      LoggerService.info('Маршрутизация восстановлена');
    } catch (e) {
      LoggerService.error('Ошибка при восстановлении маршрутизации', e);
      throw Exception('Не удалось восстановить маршрутизацию: $e');
    }
  }
  
  // Проверка статуса подключения
  bool isConnected() {
    return _isConnected;
  }
  
  // Освобождение ресурсов
  void dispose() {
    if (_isConnected) {
      disconnect();
    }
  }
}