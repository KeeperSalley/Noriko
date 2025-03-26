import 'package:flutter/material.dart';
import '../../../data/models/vpn_config.dart';
import '../../../core/services/server_storage_service.dart';
import '../../../core/services/logger_service.dart';
import '../../../main.dart';  // Для доступа к глобальной функции goToServersPage

class HomePage extends StatefulWidget {
  final VpnConfig? selectedServer;

  const HomePage({Key? key, this.selectedServer}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _isConnected = false;
  VpnConfig? _currentServer;
  
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
    // Если передан сервер, используем его
    if (widget.selectedServer != null) {
      _currentServer = widget.selectedServer;
      // Можно автоматически запустить подключение
      // _connectToServer();
    } else {
      // Иначе загружаем последний использованный сервер
      _loadLastServer();
    }
  }

  // Загрузка последнего использованного сервера
  Future<void> _loadLastServer() async {
    try {
      final servers = await ServerStorageService.loadServers();
      if (servers.isNotEmpty) {
        setState(() {
          // Для примера берем первый сервер, в реальности можно хранить ID последнего активного
          _currentServer = servers.first;
        });
      }
    } catch (e) {
      LoggerService.error('Ошибка при загрузке последнего сервера', e);
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
      if (_isConnected) {
        // Обновляем статистику (в реальном приложении здесь будет настоящая логика)
        _statistics['Время соединения'] = '00:00:00';
        _statistics['Загружено'] = '0 KB';
        _statistics['Выгружено'] = '0 KB';
        _statistics['Ping'] = '0 ms';
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Отключено'))
        );
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
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              // Действие для уведомлений
            },
          ),
          const SizedBox(width: 16),
        ],
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
                                
                                // IP адреса (перемещены под кнопку)
                                const SizedBox(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Ваш IP',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        const Text(
                                          '127.0.0.1',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'IP Сервера',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _isConnected && _currentServer != null 
                                              ? _currentServer!.address 
                                              : '-',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
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
            
            // Исправленный горизонтальный слайдер-карусель серверов для быстрого выбора
            FutureBuilder<List<VpnConfig>>(
              future: ServerStorageService.loadServers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Ошибка загрузки серверов',
                      style: TextStyle(color: Colors.red[400]),
                    ),
                  );
                }
                
                final servers = snapshot.data ?? [];
                
                if (servers.isEmpty) {
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
                              // Используем правильный метод для перехода к серверам
                              goToServersPage(context);
                            },
                            child: const Text('Добавить сервер'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                
                // Улучшенная версия со свайпом через PageView
                return Container(
                  height: 150,
                  child: PageView.builder(
                    controller: PageController(viewportFraction: 0.3),
                    scrollDirection: Axis.horizontal,
                    itemCount: servers.length,
                    itemBuilder: (context, index) {
                      final server = servers[index];
                      final isSelected = _currentServer != null && 
                          _currentServer!.address == server.address && 
                          _currentServer!.port == server.port &&
                          _currentServer!.id == server.id;
                      
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _currentServer = server;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.all(5.0),
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
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
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