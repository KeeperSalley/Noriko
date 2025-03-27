import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../data/models/vpn_config.dart';
import '../../../core/services/server_storage_service.dart';
import '../../../core/services/logger_service.dart';
import '../../../main.dart';  // Для доступа к глобальной функции goToServersPage

// Глобальный кеш данных серверов, доступный в приложении
class ServerCache {
  static List<VpnConfig>? _cachedServers;
  static bool _isLoading = false;

  // Получение серверов с кешированием
  static Future<List<VpnConfig>> getServers() async {
    // Если данные уже загружены, возвращаем их
    if (_cachedServers != null) {
      return _cachedServers!;
    }
    
    // Если загрузка уже идет, ждем немного и проверяем снова
    if (_isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
      return getServers();
    }
    
    // Загружаем данные, если их еще нет
    _isLoading = true;
    try {
      _cachedServers = await ServerStorageService.loadServers();
      return _cachedServers!;
    } catch (e) {
      LoggerService.error('Ошибка при загрузке серверов', e);
      // В случае ошибки возвращаем пустой список
      return [];
    } finally {
      _isLoading = false;
    }
  }
  
  // Обновление кеша
  static Future<List<VpnConfig>> refreshServers() async {
    _isLoading = true;
    try {
      _cachedServers = await ServerStorageService.loadServers();
      return _cachedServers!;
    } catch (e) {
      LoggerService.error('Ошибка при обновлении серверов', e);
      return _cachedServers ?? [];
    } finally {
      _isLoading = false;
    }
  }
}

class HomePage extends StatefulWidget {
  final VpnConfig? selectedServer;

  const HomePage({Key? key, this.selectedServer}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isConnected = false;
  VpnConfig? _currentServer;
  List<VpnConfig> _servers = [];
  bool _isLoading = true;
  String _currentIP = "Получение...";
  bool _isLoadingIP = true;
  
  // Моковые данные для статистики
  final Map<String, String> _statistics = {
    'Время соединения': '00:00:00',
    'Загружено': '0 KB',
    'Выгружено': '0 KB',
    'Ping': '0 ms',
  };

  @override
  void initState() {
    super.initState();
    
    // Приоритет выбора сервера:
    // 1. Сервер, переданный через props (widget.selectedServer)
    // 2. Сервер из глобального состояния (AppGlobals.selectedServer)
    // 3. Первый сервер из кеша
    
    if (widget.selectedServer != null) {
      _currentServer = widget.selectedServer;
    } 
    else if (AppGlobals.selectedServer != null) {
      _currentServer = AppGlobals.selectedServer;
    }
    
    // Загружаем IP адрес
    _loadCurrentIP();
    
    // Загружаем список серверов
    _loadServers();
  }

  // Получение текущего IP адреса
  Future<void> _loadCurrentIP() async {
    setState(() {
      _isLoadingIP = true;
    });
    
    try {
      final ip = await getCurrentIP();
      setState(() {
        _currentIP = ip;
        _isLoadingIP = false;
      });
    } catch (e) {
      setState(() {
        _currentIP = "Недоступно";
        _isLoadingIP = false;
      });
    }
  }
  
  // Функция для получения текущего IP адреса
  Future<String> getCurrentIP() async {
    try {
      // Пробуем основной API
      final response = await http.get(Uri.parse('https://api.ipify.org'));
      if (response.statusCode == 200) {
        return response.body.trim();
      }
      
      // Запасной API 
      final fallbackResponse = await http.get(Uri.parse('https://api.my-ip.io/ip'));
      if (fallbackResponse.statusCode == 200) {
        return fallbackResponse.body.trim();
      }
      
      // Еще один запасной вариант
      final thirdOption = await http.get(Uri.parse('https://checkip.amazonaws.com'));
      if (thirdOption.statusCode == 200) {
        return thirdOption.body.trim();
      }
      
      return "Недоступно";
    } catch (e) {
      LoggerService.error('Ошибка получения IP', e);
      return "Ошибка";
    }
  }

  // Загрузка серверов с кешированием
  Future<void> _loadServers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Получаем серверы из кеша (или загружаем, если их нет)
      final servers = await ServerCache.getServers();
      
      // Обновляем состояние
      setState(() {
        _servers = servers;
        _isLoading = false;
        
        // Если не выбран сервер, но есть серверы в списке, выбираем первый
        if (_currentServer == null && servers.isNotEmpty) {
          _currentServer = servers.first;
        }
      });
    } catch (e) {
      LoggerService.error('Ошибка при загрузке серверов', e);
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Подключение к серверу
  void _connectToServer() {
    if (_currentServer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сервер не выбран'))
      );
      return;
    }

    setState(() {
      _isConnected = !_isConnected;

      AppGlobals.resetIP();

      if (_isConnected) {
        // Обновляем статистику (в реальном приложении здесь будет настоящая логика)
        _statistics['Время соединения'] = '00:00:01';
        _statistics['Загружено'] = '0 KB';
        _statistics['Выгружено'] = '0 KB';
        _statistics['Ping'] = '${_getRandomPing()} ms';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Подключение к серверу ${_currentServer!.displayName}'))
        );
        AppGlobals.getCurrentIP();
      } else {
        // Сбрасываем статистику
        _statistics['Время соединения'] = '00:00:00';
        _statistics['Загружено'] = '0 KB';
        _statistics['Выгружено'] = '0 KB';
        _statistics['Ping'] = '0 ms';
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Отключено'))
        );
        AppGlobals.getCurrentIP();
      }
    });
  }

  // Для демонстрации генерируем случайный пинг
  int _getRandomPing() {
    return 30 + (DateTime.now().millisecondsSinceEpoch % 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Noriko VPN',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true, // Центрирование заголовка
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Основная область с информацией о подключении и статистикой (в строку)
            IntrinsicHeight(  // Это обеспечит одинаковую высоту обеих колонок
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch, // Растягиваем по высоте
                children: [
                  // Левая часть - карточка с информацией о подключении (50% ширины)
                  Expanded(
                    flex: 1,
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween, // Равномерное распределение
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Информация о статусе и сервере
                            Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Статус',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _isConnected ? 'Подключено' : 'Отключено',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: _isConnected ? Colors.green : Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                            
                                // Информация о сервере
                                if (_currentServer != null)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Theme.of(context).colorScheme.primary,
                                        radius: 32,
                                        child: Icon(
                                          _getProtocolIcon(_currentServer!.protocol),
                                          color: Colors.white,
                                          size: 32,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _currentServer!.displayName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _currentServer!.protocol.toUpperCase(),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_currentServer!.address}:${_currentServer!.port}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  const Text(
                                    'Сервер не выбран',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                                
                            // Средний блок с кнопкой
                            Column(
                              children: [
                                // Кнопка подключения
                                ElevatedButton.icon(
                                  onPressed: _currentServer == null ? null : _connectToServer,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isConnected 
                                      ? Colors.red.withOpacity(0.8) 
                                      : Theme.of(context).colorScheme.primary,
                                    minimumSize: const Size.fromHeight(50),
                                  ),
                                  icon: Icon(_isConnected ? Icons.power_settings_new : Icons.power_settings_new_outlined),
                                  label: Text(_isConnected ? 'Отключить' : 'Подключить'),
                                ),
                                
                                Row(
                                  children: [
                                    Text(
                                      'Ваш IP:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Кнопка обновления IP
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          AppGlobals.resetIP();
                                        });
                                      },
                                      child: Icon(
                                        Icons.refresh,
                                        size: 14,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Использовать StatefulBuilder для локального управления состоянием
                                    StatefulBuilder(
                                      builder: (context, setInnerState) {
                                        // Локальное состояние для отслеживания загрузки
                                        bool isLoading = false;
                                        String displayIP = AppGlobals.currentIP ?? "Получение...";
                                        
                                        // Функция для получения IP с таймаутом
                                        void getIPWithTimeout() {
                                          // Устанавливаем флаг загрузки
                                          setInnerState(() {
                                            isLoading = true;
                                          });
                                          
                                          // Устанавливаем таймаут в 5 секунд
                                          Future.delayed(const Duration(seconds: 5), () {
                                            if (isLoading) {
                                              setInnerState(() {
                                                isLoading = false;
                                                displayIP = AppGlobals.currentIP ?? "Таймаут";
                                              });
                                            }
                                          });
                                          
                                          // Запускаем получение IP
                                          AppGlobals.getCurrentIP().then((ip) {
                                            setInnerState(() {
                                              isLoading = false;
                                              displayIP = ip;
                                            });
                                          }).catchError((_) {
                                            setInnerState(() {
                                              isLoading = false;
                                              displayIP = "Ошибка";
                                            });
                                          });
                                        }
                                        
                                        // Запускаем получение IP при первом построении
                                        if (AppGlobals.currentIP == null && !isLoading) {
                                          getIPWithTimeout();
                                        }
                                        
                                        return Row(
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            isLoading 
                                                ? SizedBox(
                                                    height: 12,
                                                    width: 12,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor: AlwaysStoppedAnimation<Color>(
                                                        Theme.of(context).colorScheme.primary,
                                                      ),
                                                    ),
                                                  )
                                                : Container(), // Пустой контейнер, если не загружается
                                            SizedBox(width: isLoading ? 8 : 0),
                                            Text(
                                              displayIP,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: 16),
                  
                  // Правая часть - статистика (50% ширины)
                  Expanded(
                    flex: 1,
                    child: Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Статистика',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onBackground,
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            // Статистика в столбик
                            ..._statistics.entries.map((entry) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      entry.value,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Divider(),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Быстрый выбор сервера
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Быстрый выбор сервера',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onBackground,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Используем правильный метод для перехода к серверам
                    goToServersPage(context);
                  },
                  child: const Text('Все серверы'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Улучшенная горизонтальная прокрутка с ScrollConfiguration
            _buildImprovedServerList(),
          ],
        ),
      ),
    );
  }
  
  // Улучшенная прокрутка серверов
  Widget _buildImprovedServerList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    if (_servers.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text(
                'Нет доступных серверов',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  goToServersPage(context);
                },
                child: const Text('Добавить сервер'),
              ),
            ],
          ),
        ),
      );
    }

    // Возвращаем Column, содержащую и слайдер, и подсказку
    return Column(
      children: [
        // Основная прокрутка с картами серверов
        SizedBox(
          height: 150,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch, 
                PointerDeviceKind.mouse,
              },
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: _servers.map((server) {
                  final isSelected = _currentServer != null && 
                    _currentServer!.id == server.id &&
                    _currentServer!.address == server.address && 
                    _currentServer!.port == server.port;
                  
                  return Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _currentServer = server;
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Card(
                        elevation: isSelected ? 8 : 2,
                        color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.2) : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isSelected 
                            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2) 
                            : BorderSide.none,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _getProtocolIcon(server.protocol),
                                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
                                size: 24,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                server.displayName,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isSelected ? Theme.of(context).colorScheme.primary : null,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                server.protocol.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        
        // Добавляем подсказку для пользователя, если серверов больше 3
        if (_servers.length > 3)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Прокрутите для просмотра всех серверов',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ],
            ),
          ),
      ],
    );
  }
  
  IconData _getProtocolIcon(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'vless':
        return Icons.bolt;
      case 'vmess':
        return Icons.shield;
      case 'trojan':
        return Icons.security;
      case 'shadowsocks':
      case 'ss':
        return Icons.vpn_key;
      default:
        return Icons.language;
    }
  }
}