import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/server_storage_service.dart';
import '../../../data/models/vpn_config.dart';
import '../../widgets/import_config_dialog.dart';
import '../../../main.dart';  // Для доступа к глобальной функции goToHomeWithServer
import '../home/home_page.dart'; // Для доступа к ServerCache

class ServersPage extends StatefulWidget {
  // Добавим возможность передачи начального выбранного сервера
  final VpnConfig? initialSelectedServer;
  
  const ServersPage({Key? key, this.initialSelectedServer}) : super(key: key);

  @override
  _ServersPageState createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  // Список серверов
  List<VpnConfig> _servers = [];
  bool _isLoading = true;

  String _searchQuery = '';
  String _filterProtocol = 'Все';
  
  // Возможные протоколы для фильтрации
  final List<String> _availableProtocols = ['Все', 'VLESS', 'VMess', 'Trojan', 'Shadowsocks'];

  // Метод для обновления UI при изменении глобального состояния
  void _updateFromGlobalState() {
    if (mounted) {
      setState(() {
        // Мы просто вызываем setState, чтобы обновить UI
        // так как логика выделения серверов использует AppGlobals.selectedServer
      });
    }
  }

  @override
  void initState() {
    super.initState();
    
    // Добавляем слушатель глобального состояния
    AppGlobals.addListener(_updateFromGlobalState);
    
    _loadServers();
  }
  
  @override
  void dispose() {
    // Удаляем слушатель при уничтожении
    AppGlobals.removeListener(_updateFromGlobalState);
    super.dispose();
  }

  // Загрузка серверов при инициализации - используем кеш
  Future<void> _loadServers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Используем кеш для получения серверов
      final loadedServers = await ServerCache.getServers();
      setState(() {
        _servers = loadedServers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Ошибка загрузки серверов: ${e.toString()}');
    }
  }

  // Обновление серверов (принудительная перезагрузка)
  Future<void> _refreshServers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Принудительное обновление кеша
      final loadedServers = await ServerCache.refreshServers();
      setState(() {
        _servers = loadedServers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Ошибка загрузки серверов: ${e.toString()}');
    }
  }

  // Сохранение серверов
  Future<void> _saveServers() async {
    try {
      await ServerStorageService.saveServers(_servers);
      // Обновляем кеш после сохранения
      await ServerCache.refreshServers();
    } catch (e) {
      _showErrorSnackBar('Ошибка сохранения серверов: ${e.toString()}');
    }
  }

  // Обработка успешного импорта
  void _handleImportSuccess(List<VpnConfig> configs) {
    setState(() {
      _servers.addAll(configs);
      _saveServers();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Успешно импортировано ${configs.length} ${_getPluralForm(configs.length, "сервер", "сервера", "серверов")}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  // Удаление сервера
  Future<void> _deleteServer(int index) async {
    final server = _servers[index];
    final serverName = server.displayName;

    try {
      setState(() {
        _servers.removeAt(index);
      });
      await _saveServers();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Сервер "$serverName" удален'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () {
              setState(() {
                _servers.insert(index, server);
                _saveServers();
              });
            },
          ),
        ),
      );
    } catch (e) {
      _showErrorSnackBar('Ошибка удаления сервера: ${e.toString()}');
      // Восстанавливаем сервер в случае ошибки
      setState(() {
        if (index < _servers.length) {
          _servers.insert(index, server);
        } else {
          _servers.add(server);
        }
      });
    }
  }

  // Подключение к серверу
  void _connectToServer(VpnConfig server) {
    // Сохраняем выбранный сервер глобально прежде чем перейти на главную страницу
    AppGlobals.updateSelectedServer(server);
    
    // Добавляем небольшую задержку, чтобы завершились все текущие операции UI
    Future.delayed(const Duration(milliseconds: 100), () {
      // Переход на главную страницу через глобальную функцию
      goToHomeWithServer(context, server);
    });
  }

  // Показать диалог подтверждения удаления
  void _showDeleteConfirmation(int index) {
    final server = _servers[index];
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Удаление сервера'),
          content: Text('Вы уверены, что хотите удалить сервер "${server.displayName}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _deleteServer(index);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
  }

  // Функция для правильного выбора формы слова в зависимости от числа
  String _getPluralForm(int number, String form1, String form2, String form5) {
    final num = number % 100;
    if (num >= 11 && num <= 19) {
      return form5;
    }
    
    final n = num % 10;
    if (n == 1) {
      return form1;
    }
    if (n >= 2 && n <= 4) {
      return form2;
    }
    return form5;
  }

  // Показать SnackBar с ошибкой
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Показать диалог импорта
  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ImportConfigDialog(
          onImportSuccess: _handleImportSuccess,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Фильтрация серверов
    List<VpnConfig> filteredServers = _servers.where((server) {
      bool matchesSearch = server.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                           server.address.toLowerCase().contains(_searchQuery.toLowerCase());
      
      bool matchesProtocol = _filterProtocol == 'Все' || 
                             server.protocol.toUpperCase() == _filterProtocol;
      
      return matchesSearch && matchesProtocol;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Серверы',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Кнопка импорта
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            tooltip: 'Импортировать из ссылки',
            onPressed: _showImportDialog,
          ),
          // Кнопка обновления
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshServers,
            tooltip: 'Обновить список',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Поиск и фильтры
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Поле поиска
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Поиск серверов...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                
                // Выпадающий список для фильтрации по протоколу
                DropdownButton<String>(
                  value: _filterProtocol,
                  icon: const Icon(Icons.filter_list),
                  elevation: 16,
                  underline: Container(
                    height: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onChanged: (String? newValue) {
                    setState(() {
                      _filterProtocol = newValue!;
                    });
                  },
                  items: _availableProtocols
                      .map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          
          // Список серверов
          Expanded(
            child: _isLoading 
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : filteredServers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.dns_outlined,
                              size: 64,
                              color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Серверы не найдены',
                              style: TextStyle(
                                fontSize: 18,
                                color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: _showImportDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Добавить сервер'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(itemCount: filteredServers.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemBuilder: (context, index) {
                          final server = filteredServers[index];
                          // Находим индекс в оригинальном списке для правильного удаления
                          final originalIndex = _servers.indexOf(server);
                          
                          // Проверяем, является ли этот сервер выбранным в глобальном состоянии
                          final bool isSelected = AppGlobals.selectedServer != null &&
                              AppGlobals.selectedServer!.id == server.id &&
                              AppGlobals.selectedServer!.address == server.address &&
                              AppGlobals.selectedServer!.port == server.port;
                          
                          return Dismissible(
                            key: Key('${server.id}-${server.address}-${server.port}'),
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20.0),
                              color: Colors.red,
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (direction) async {
                              _showDeleteConfirmation(originalIndex);
                              return false; // Сами обрабатываем удаление
                            },
                            child: Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              // Выделяем карточку, если это выбранный сервер
                              color: isSelected 
                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                                  : null,
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  backgroundColor: isSelected && AppGlobals.isConnected
                                      ? Colors.green // Зеленый фон, если сервер выбран и подключен
                                      : Theme.of(context).colorScheme.primary,
                                  child: Icon(
                                    _getProtocolIcon(server.protocol),
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  server.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _buildInfoChip(
                                          server.protocol.toUpperCase(),
                                          Colors.blue.withOpacity(0.2),
                                        ),
                                        const SizedBox(width: 8),
                                        _buildInfoChip(
                                          server.params['security'] ?? 'Standard',
                                          Colors.green.withOpacity(0.2),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${server.address}:${server.port}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.copy),
                                      tooltip: 'Копировать ссылку',
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: server.toUrl()));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Ссылка скопирована в буфер обмена'))
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: 'Удалить сервер',
                                      onPressed: () => _showDeleteConfirmation(originalIndex),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: () => _connectToServer(server),
                                      child: const Text('Подключить'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showImportDialog,
        tooltip: 'Добавить сервер',
        child: const Icon(Icons.add),
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

  Widget _buildInfoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}