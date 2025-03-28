import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({Key? key}) : super(key: key);

  @override
  _LogsPageState createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  // Моковые данные для логов
  final List<Map<String, dynamic>> _logs = [
    {
      'timestamp': '2025-03-26 10:15:23',
      'level': 'INFO',
      'message': 'Приложение запущено',
    },
    {
      'timestamp': '2025-03-26 10:15:24',
      'level': 'INFO',
      'message': 'Инициализация конфигурации...',
    },
    {
      'timestamp': '2025-03-26 10:15:25',
      'level': 'INFO',
      'message': 'Загружены настройки пользователя',
    },
    {
      'timestamp': '2025-03-26 10:16:01',
      'level': 'INFO',
      'message': 'Подключение к серверу "Сервер 1 (Германия)"',
    },
    {
      'timestamp': '2025-03-26 10:16:02',
      'level': 'INFO',
      'message': 'Открытие TCP соединения с 65.21.108.12:443',
    },
    {
      'timestamp': '2025-03-26 10:16:05',
      'level': 'INFO',
      'message': 'Соединение установлено успешно',
    },
    {
      'timestamp': '2025-03-26 10:20:45',
      'level': 'WARNING',
      'message': 'Высокая загрузка канала: 5MB/s',
    },
    {
      'timestamp': '2025-03-26 10:45:12',
      'level': 'ERROR',
      'message': 'Потеря соединения с сервером',
    },
  ];

  String _searchQuery = '';
  String _logLevel = 'Все';
  
  // Возможные уровни логов для фильтрации
  final List<String> _logLevels = ['Все', 'INFO', 'WARNING', 'ERROR'];

  @override
  Widget build(BuildContext context) {
    // Фильтрация логов
    List<Map<String, dynamic>> filteredLogs = _logs.where((log) {
      bool matchesSearch = log['message'].toString().toLowerCase().contains(_searchQuery.toLowerCase());
      bool matchesLevel = _logLevel == 'Все' || log['level'] == _logLevel;
      
      return matchesSearch && matchesLevel;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Логи',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              // Копируем логи в буфер обмена
              final String logsText = filteredLogs
                  .map((log) => '[${log['timestamp']}] [${log['level']}] ${log['message']}')
                  .join('\n');
              Clipboard.setData(ClipboardData(text: logsText));
              
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Логи скопированы в буфер обмена')),
              );
            },
            tooltip: 'Копировать логи',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              // Показываем диалог подтверждения очистки логов
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Очистка логов'),
                  content: const Text('Вы уверены, что хотите очистить все логи?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        // Очищаем логи
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Логи очищены')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('Очистить'),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'Очистить логи',
          ),
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
                      hintText: 'Поиск в логах...',
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
                
                // Выпадающий список для фильтрации по уровню логов
                DropdownButton<String>(
                  value: _logLevel,
                  icon: const Icon(Icons.filter_list),
                  elevation: 16,
                  underline: Container(
                    height: 2,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onChanged: (String? newValue) {
                    setState(() {
                      _logLevel = newValue!;
                    });
                  },
                  items: _logLevels.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          
          // Список логов
          Expanded(
            child: filteredLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 64,
                          color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Логи не найдены',
                          style: TextStyle(
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121212),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.grey.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: ListView.builder(
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        final log = filteredLogs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Timestamp
                              SizedBox(
                                width: 160,
                                child: Text(
                                  log['timestamp'],
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onBackground.withOpacity(0.7),
                                  ),
                                ),
                              ),
                              
                              // Log level with color
                              SizedBox(
                                width: 70,
                                child: Text(
                                  '[${log['level']}]',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _getLogLevelColor(log['level']),
                                  ),
                                ),
                              ),
                              
                              // Log message
                              Expanded(
                                child: Text(
                                  log['message'],
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Color _getLogLevelColor(String level) {
    switch (level) {
      case 'INFO':
        return Colors.blue;
      case 'WARNING':
        return Colors.orange;
      case 'ERROR':
        return Colors.red;
      default:
        return Colors.white;
    }
  }
}