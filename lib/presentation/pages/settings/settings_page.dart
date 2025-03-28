import 'package:flutter/material.dart';
import '../../../core/services/app_settings_service.dart';
import '../../../core/services/logger_service.dart';
import '../../../core/services/notification_service.dart';
import '../routing/routing_page.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

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
        AppSettingsService.keyUseCustomDNS: _useCustomDNS,
        AppSettingsService.keyPrimaryDNS: _primaryDNSController.text,
        AppSettingsService.keySecondaryDNS: _secondaryDNSController.text,
      };
      
      // Обновляем автозапуск на уровне системы
      if (_autoStart) {
        await AppSettingsService.setAutoStart(true);
      } else {
        await AppSettingsService.setAutoStart(false);
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
        // Также отключаем автозапуск на уровне системы
        await AppSettingsService.setAutoStart(false);
        
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
                backgroundColor: const Color(0xFFC60E7A),
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
                backgroundColor: const Color(0xFFC60E7A),
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
    // Константы для отступов для унификации
    const double pagePadding = 16.0;
    const double sectionSpacing = 24.0;
    const double cardPadding = 16.0;
    const double itemSpacing = 16.0;
    const double smallSpacing = 8.0;
    const double buttonSpacing = 16.0;
    
    return Scaffold(
      appBar: AppBar(
        title: const Padding(
          padding: EdgeInsets.only(left: 8.0),
          child: Text(
            'Настройки',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Основные настройки
                  _buildSectionHeader('Основные настройки'),
                  Card(
                    margin: const EdgeInsets.only(bottom: sectionSpacing),
                    child: Padding(
                      padding: const EdgeInsets.all(cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHoverSwitchTile(
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
                          const Divider(height: itemSpacing, thickness: 1),
                          _buildHoverSwitchTile(
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
                          const Divider(height: itemSpacing, thickness: 1),
                          _buildHoverSwitchTile(
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
                  
                  // Уведомления и логирование
                  _buildSectionHeader('Уведомления и логирование'),
                  Card(
                    margin: const EdgeInsets.only(bottom: sectionSpacing),
                    child: Padding(
                      padding: const EdgeInsets.all(cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [ 
                          _buildHoverSwitchTile(
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
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Очистить логи',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                  _buildHoverButton(
                                    onPressed: _showClearLogsConfirmationDialog,
                                    backgroundColor: const Color(0xFFC60E7A),
                                    child: const Text('Очистить'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Настройки подключения
                  _buildSectionHeader('Настройки подключения'),
                  Card(
                    margin: const EdgeInsets.only(bottom: sectionSpacing),
                    child: Padding(
                      padding: const EdgeInsets.all(cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHoverSwitchTile(
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
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                                  const SizedBox(width: itemSpacing),
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
                    margin: const EdgeInsets.only(bottom: sectionSpacing),
                    child: Padding(
                      padding: const EdgeInsets.all(cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'VPN-клиент',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: smallSpacing),
                                Text('Версия: 1.0.0'),
                              ],
                            ),
                          ),
                          const SizedBox(height: itemSpacing),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Кроссплатформенный VPN-клиент с открытым исходным кодом. '
                              'Поддерживает протоколы V2Ray, Trojan и Shadowsocks.',
                            ),
                          ),
                          const SizedBox(height: itemSpacing),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildHoverButton(
                                  onPressed: () {
                                    // Действие для проверки обновлений
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Проверка обновлений...'))
                                    );
                                  },
                                  backgroundColor: const Color(0xFFC60E7A),
                                  child: const Text('Проверить обновления'),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    // Открыть сайт
                                    final Uri url = Uri.parse('https://noriko.pro');
                                    try {
                                      await url_launcher.launchUrl(url);
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Не удалось открыть сайт'))
                                      );
                                    }
                                  },
                                  child: const Text('Посетить сайт'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Отображение статуса
                  if (_statusMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: itemSpacing, left: 16, right: 16),
                      child: Text(
                        _statusMessage,
                        style: TextStyle(
                          color: _statusMessage.contains('Ошибка') ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  
                  // Нижние кнопки
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildHoverButton(
                          onPressed: _showResetConfirmationDialog,
                          backgroundColor: Colors.grey[700],
                          child: const Text('Сбросить настройки'),
                        ),
                        const SizedBox(width: buttonSpacing),
                        _buildHoverButton(
                          onPressed: _settingsChanged ? _saveSettings : null,
                          backgroundColor: const Color(0xFFC60E7A),
                          child: const Text('Сохранить настройки'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0, left: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // Виджет с hover-эффектом для SwitchListTile
  Widget _buildHoverSwitchTile(String title, String subtitle, bool value, Function(bool) onChanged) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: isHovered 
                ? Theme.of(context).colorScheme.primary.withOpacity(0.03) 
                : Colors.transparent,
              boxShadow: isHovered
                ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                      blurRadius: 15,
                      spreadRadius: -5,
                    ),
                  ]
                : [],
            ),
            child: SwitchListTile(
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
              contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            ),
          ),
        );
      },
    );
  }

  // Виджет для кнопок с hover-эффектом
  Widget _buildHoverButton({
    required VoidCallback? onPressed, 
    required Widget child, 
    Color? backgroundColor
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: isHovered && onPressed != null
                ? [
                    BoxShadow(
                      color: (backgroundColor ?? Theme.of(context).colorScheme.primary).withOpacity(0.2),
                      blurRadius: 12,
                      spreadRadius: -4,
                    ),
                  ]
                : [],
            ),
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: backgroundColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: backgroundColor?.withOpacity(0.5) ??
                    Theme.of(context).colorScheme.primary.withOpacity(0.5),
                elevation: isHovered ? 4 : 2,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Widget _buildDropdownTile(String title, String subtitle, String value, List<String> items, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: StatefulBuilder(
        builder: (context, setState) {
          bool isHovered = false;
          return MouseRegion(
            onEnter: (_) => setState(() => isHovered = true),
            onExit: (_) => setState(() => isHovered = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: isHovered 
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.03) 
                  : Colors.transparent,
                boxShadow: isHovered
                  ? [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
                        blurRadius: 15,
                        spreadRadius: -5,
                      ),
                    ]
                  : [],
              ),
              padding: const EdgeInsets.all(8),
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
            ),
          );
        },
      ),
    );
  }
}