import 'package:flutter/material.dart';
import '../../../core/services/app_settings_service.dart';
import '../../../core/services/logger_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Настройки приложения
  bool _autoStart = false;
  bool _autoConnect = false;
  bool _minimizeToTray = true;
  bool _enableLogging = true;
  bool _enableNotifications = true;
  
  // Настройки DNS
  bool _useCustomDNS = false;
  final TextEditingController _primaryDNSController = TextEditingController(text: '1.1.1.1');
  final TextEditingController _secondaryDNSController = TextEditingController(text: '8.8.8.8');
  
  bool _isLoading = true;
  bool _settingsChanged = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _primaryDNSController.dispose();
    _secondaryDNSController.dispose();
    super.dispose();
  }

  // Загрузка настроек
  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    try {
      final settings = await AppSettingsService.getSettings();
      
      setState(() {
        _autoStart = settings[AppSettingsService.keyAutoStart] ?? AppSettingsService.defaultAutoStart;
        _autoConnect = settings[AppSettingsService.keyAutoConnect] ?? AppSettingsService.defaultAutoConnect;
        _minimizeToTray = settings[AppSettingsService.keyMinimizeToTray] ?? AppSettingsService.defaultMinimizeToTray;
        _enableLogging = settings[AppSettingsService.keyEnableLogging] ?? AppSettingsService.defaultEnableLogging;
        _enableNotifications = settings[AppSettingsService.keyEnableNotifications] ?? AppSettingsService.defaultEnableNotifications;
        _useCustomDNS = settings[AppSettingsService.keyUseCustomDNS] ?? AppSettingsService.defaultUseCustomDNS;
        
        _primaryDNSController.text = settings[AppSettingsService.keyPrimaryDNS] ?? AppSettingsService.defaultPrimaryDNS;
        _secondaryDNSController.text = settings[AppSettingsService.keySecondaryDNS] ?? AppSettingsService.defaultSecondaryDNS;
        
        _isLoading = false;
        _settingsChanged = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Ошибка загрузки настроек: ${e.toString()}';
      });
      LoggerService.error('Ошибка загрузки настроек на странице настроек', e);
    }
  }

  // Сохранение настроек
  Future<void> _saveSettings() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    try {
      // Формируем объект настроек
      final settings = {
        AppSettingsService.keyAutoStart: _autoStart,
        AppSettingsService.keyAutoConnect: _autoConnect,
        AppSettingsService.keyMinimizeToTray: _minimizeToTray,
        AppSettingsService.keyEnableLogging: _enableLogging,
        AppSettingsService.keyEnableNotifications: _enableNotifications,
        AppSettingsService.keyUseCustomDNS: _useCustomDNS,
        AppSettingsService.keyPrimaryDNS: _primaryDNSController.text,
        AppSettingsService.keySecondaryDNS: _secondaryDNSController.text,
      };
      
      // Обновляем автозапуск
      if (_autoStart) {
        await AppSettingsService.setAutoStart(true);
      }
      
      // Сохраняем настройки
      final success = await AppSettingsService.saveSettings(settings);
      
      setState(() {
        _isLoading = false;
        _settingsChanged = false;
        _statusMessage = success ? 'Настройки успешно сохранены' : 'Ошибка при сохранении настроек';
      });
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки сохранены'))
        );
      } else {
        _showErrorSnackBar('Не удалось сохранить настройки');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Ошибка: ${e.toString()}';
      });
      _showErrorSnackBar('Ошибка сохранения настроек: ${e.toString()}');
      LoggerService.error('Ошибка сохранения настроек на странице настроек', e);
    }
  }
    // Сброс настроек до значений по умолчанию
  Future<void> _resetSettings() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    try {
      // Сбрасываем настройки через сервис
      final success = await AppSettingsService.resetToDefaults();
      
      if (success) {
        // Перезагружаем настройки
        await _loadSettings();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Настройки сброшены до значений по умолчанию'))
        );
      } else {
        setState(() {
          _isLoading = false;
          _statusMessage = 'Ошибка при сбросе настроек';
        });
        _showErrorSnackBar('Не удалось сбросить настройки');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Ошибка: ${e.toString()}';
      });
      _showErrorSnackBar('Ошибка сброса настроек: ${e.toString()}');
      LoggerService.error('Ошибка сброса настроек', e);
    }
  }

  // Очистка логов
  Future<void> _clearLogs() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '';
    });

    try {
      final success = await AppSettingsService.clearLogs();
      
      setState(() {
        _isLoading = false;
      });
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Логи очищены'))
        );
      } else {
        _showErrorSnackBar('Не удалось очистить логи');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Ошибка очистки логов: ${e.toString()}');
      LoggerService.error('Ошибка очистки логов', e);
    }
  }

  // Показ SnackBar с ошибкой
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Показ диалога подтверждения сброса настроек
  void _showResetConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Сброс настроек'),
          content: const Text('Вы уверены, что хотите сбросить все настройки до значений по умолчанию?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _resetSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.8),
                foregroundColor: Colors.white,
              ),
              child: const Text('Сбросить'),
            ),
          ],
        );
      },
    );
  }

  // Показ диалога подтверждения очистки логов
  void _showClearLogsConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Очистить логи'),
          content: const Text('Вы уверены, что хотите удалить все логи?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _clearLogs();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.8),
                foregroundColor: Colors.white,
              ),
              child: const Text('Очистить'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Настройки',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Основные настройки
                  _buildSectionHeader('Основные настройки'),
                  Card(
                    margin: const EdgeInsets.only(bottom: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildSwitchTile(
                            'Автозапуск при старте системы',
                            'Приложение будет запускаться автоматически при включении компьютера',
                            _autoStart,
                            (value) {
                              setState(() {
                                _autoStart = value;
                                _settingsChanged = true;
                              });
                            },
                          ),
                          const Divider(),
                          _buildSwitchTile(
                            'Автоподключение',
                            'Автоматически подключаться к последнему использованному серверу',
                            _autoConnect,
                            (value) {
                              setState(() {
                                _autoConnect = value;
                                _settingsChanged = true;
                              });
                            },
                          ),
                          const Divider(),
                          _buildSwitchTile(
                            'Сворачивать в трей',
                            'При закрытии окна приложение будет свёрнуто в трей',
                            _minimizeToTray,
                            (value) {
                              setState(() {
                                _minimizeToTray = value;
                                _settingsChanged = true;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Интерфейс (закомментирован)
                  // _buildSectionHeader('Интерфейс'),
                  // Card(
                  //   margin: const EdgeInsets.only(bottom: 24),
                  //   child: Padding(
                  //     padding: const EdgeInsets.all(16.0),
                  //     child: Column(
                  //       children: [
                  //         _buildDropdownTile(
                  //           'Тема оформления',
                  //           'Выберите тему для интерфейса приложения',
                  //           _selectedTheme,
                  //           _themes,
                  //           (value) {
                  //             setState(() {
                  //               _selectedTheme = value!;
                  //               _settingsChanged = true;
                  //             });
                  //           },
                  //         ),
                  //         const Divider(),
                  //         _buildDropdownTile(
                  //           'Язык',
                  //           'Выберите язык интерфейса',
                  //           _selectedLanguage,
                  //           _languages,
                  //           (value) {
                  //             setState(() {
                  //               _selectedLanguage = value!;
                  //               _settingsChanged = true;
                  //             });
                  //           },
                  //         ),
                  //       ],
                  //     ),
                  //   ),
                  // ),
                  
                  // Уведомления и логирование
                  _buildSectionHeader('Уведомления и логирование'),
                  Card(
                    margin: const EdgeInsets.only(bottom: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildSwitchTile(
                            'Показывать уведомления',
                            'Отображать уведомления о событиях приложения',
                            _enableNotifications,
                            (value) {
                              setState(() {
                                _enableNotifications = value;
                                _settingsChanged = true;
                              });
                            },
                          ),
                          const Divider(),
                          _buildSwitchTile(
                            'Вести логи',
                            'Записывать действия приложения в лог-файл',
                            _enableLogging,
                            (value) {
                              setState(() {
                                _enableLogging = value;
                                _settingsChanged = true;
                              });
                            },
                          ),
                          if (_enableLogging) 
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Очистить логи'),
                                  ElevatedButton(
                                    onPressed: _showClearLogsConfirmationDialog,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.withOpacity(0.8),
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Очистить'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Настройки подключения (маршрутизация закомментирована)
                  _buildSectionHeader('Настройки подключения'),
                  Card(
                    margin: const EdgeInsets.only(bottom: 24),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // _buildDropdownTile(
                          //   'Режим маршрутизации',
                          //   'Определяет какой трафик будет проходить через VPN',
                          //   _selectedRoutingMode,
                          //   _routingModes,
                          //   (value) {
                          //     setState(() {
                          //       _selectedRoutingMode = value!;
                          //       _settingsChanged = true;
                          //     });
                          //   },
                          // ),
                          // if (_selectedRoutingMode != 'Все сайты') 
                          //   Padding(
                          //     padding: const EdgeInsets.only(top: 16.0),
                          //     child: TextFormField(
                          //       decoration: const InputDecoration(
                          //         labelText: 'Список сайтов (по одному на строку)',
                          //         border: OutlineInputBorder(),
                          //       ),
                          //       maxLines: 4,
                          //     ),
                          //   ),
                          // const Divider(),
                          
                          _buildSwitchTile(
                            'Пользовательские DNS серверы',
                            'Использовать свои DNS сервера вместо серверов провайдера',
                            _useCustomDNS,
                            (value) {
                              setState(() {
                                _useCustomDNS = value;
                                _settingsChanged = true;
                              });
                            },
                          ),
                          if (_useCustomDNS) 
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _primaryDNSController,
                                      decoration: const InputDecoration(
                                        labelText: 'Основной DNS',
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (_) => setState(() => _settingsChanged = true),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _secondaryDNSController,
                                      decoration: const InputDecoration(
                                        labelText: 'Вторичный DNS',
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (_) => setState(() => _settingsChanged = true),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  // О программе
                  _buildSectionHeader('О программе'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Noriko VPN',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text('Версия: 1.0.0'),
                          const SizedBox(height: 16),
                          const Text(
                            'Кроссплатформенный VPN-клиент с открытым исходным кодом. '
                            'Поддерживает протоколы V2Ray, Trojan и Shadowsocks.',
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              ElevatedButton(
                                onPressed: () {
                                  // Действие для проверки обновлений
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Проверка обновлений...'))
                                  );
                                },
                                child: const Text('Проверить обновления'),
                              ),
                              TextButton(
                                onPressed: () {
                                  // Действие для открытия сайта
                                },
                                child: const Text('Посетить сайт'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Отображение статуса
                  if (_statusMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _statusMessage.contains('Ошибка') ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  
                  // Нижние кнопки
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        onPressed: _showResetConfirmationDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Сбросить настройки'),
                      ),
                      ElevatedButton(
                        onPressed: _settingsChanged ? _saveSettings : null,
                        child: const Text('Сохранить настройки'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
        ),
      ),
      value: value,
      onChanged: onChanged,
      dense: false,
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
    );
  }

  Widget _buildDropdownTile(String title, String subtitle, String value, List<String> items, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: value,
            isExpanded: true,
            underline: Container(
              height: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
            onChanged: onChanged,
            items: items.map<DropdownMenuItem<String>>((String itemValue) {
              return DropdownMenuItem<String>(
                value: itemValue,
                child: Text(itemValue),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}