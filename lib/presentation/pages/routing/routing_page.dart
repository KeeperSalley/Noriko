import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/routing_service.dart';
import '../../widgets/hover_effect.dart';

class RoutingPage extends StatefulWidget {
  const RoutingPage({Key? key}) : super(key: key);

  @override
  _RoutingPageState createState() => _RoutingPageState();
}

class _RoutingPageState extends State<RoutingPage> {
  // Сервис маршрутизации
  final RoutingService _routingService = RoutingService();
  
  // Состояние страницы
  late RoutingProfile _currentProfile;
  List<RoutingProfile> _availableProfiles = [];
  bool _isLoading = true;
  
  // Текущий редактируемый профиль
  RoutingProfile? _editingProfile;
  
  // Контроллер для создания нового правила
  final TextEditingController _ruleValueController = TextEditingController();
  String _ruleType = 'domain';
  String _ruleAction = 'proxy';
  
  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }
  
  @override
  void dispose() {
    _ruleValueController.dispose();
    super.dispose();
  }
  
  // Загрузка профилей маршрутизации
  Future<void> _loadProfiles() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Инициализируем сервис, если он еще не инициализирован
      if (_routingService.currentProfile == null) {
        await _routingService.initialize();
      }
      
      setState(() {
        _currentProfile = _routingService.currentProfile;
        _availableProfiles = _routingService.savedProfiles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Ошибка загрузки профилей маршрутизации: $e');
    }
  }
  
  // Установка выбранного профиля
  Future<void> _setProfile(RoutingProfile profile) async {
    try {
      await _routingService.setCurrentProfile(profile);
      setState(() {
        _currentProfile = profile;
      });
      _showSuccessSnackBar('Профиль маршрутизации "${profile.name}" установлен');
    } catch (e) {
      _showErrorSnackBar('Ошибка установки профиля: $e');
    }
  }
  
  // Начать редактирование профиля
  void _startEditingProfile(RoutingProfile profile) {
    // Создаем копию профиля для редактирования, чтобы не менять оригинал
    setState(() {
      _editingProfile = RoutingProfile(
        name: profile.name,
        rules: List.from(profile.rules), // Создаем копию списка правил
        isSplitTunnelingEnabled: profile.isSplitTunnelingEnabled,
        isProxyOnlyEnabled: profile.isProxyOnlyEnabled,
      );
    });
  }
  
  // Сохранение отредактированного профиля
  Future<void> _saveEditingProfile() async {
    if (_editingProfile == null) return;
    
    try {
      await _routingService.saveProfile(_editingProfile!);
      
      // Обновляем список профилей и текущий профиль, если был выбран редактируемый
      setState(() {
        _availableProfiles = _routingService.savedProfiles;
        if (_currentProfile.name == _editingProfile!.name) {
          _currentProfile = _editingProfile!;
        }
        _editingProfile = null; // Закрываем режим редактирования
      });
      
      _showSuccessSnackBar('Профиль успешно сохранен');
    } catch (e) {
      _showErrorSnackBar('Ошибка сохранения профиля: $e');
    }
  }
  
  // Отмена редактирования профиля
  void _cancelEditingProfile() {
    setState(() {
      _editingProfile = null;
      _ruleValueController.clear();
    });
  }
  
  // Добавление нового правила в редактируемый профиль
  void _addRuleToEditingProfile() {
    if (_editingProfile == null) return;
    
    final value = _ruleValueController.text.trim();
    if (value.isEmpty) {
      _showErrorSnackBar('Введите значение для правила');
      return;
    }
    
    // Добавляем новое правило
    setState(() {
      _editingProfile!.rules.add(
        RouteRule(
          type: _ruleType,
          value: value,
          action: _ruleAction,
        ),
      );
      _ruleValueController.clear(); // Очищаем поле ввода
    });
  }
  
  // Удаление правила из редактируемого профиля
  void _removeRuleFromEditingProfile(int index) {
    if (_editingProfile == null || index < 0 || index >= _editingProfile!.rules.length) return;
    
    setState(() {
      _editingProfile!.rules.removeAt(index);
    });
  }
  
  // Создание нового профиля
  void _showCreateProfileDialog() {
    final TextEditingController nameController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Создание профиля маршрутизации'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Название профиля',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Выберите базовый профиль:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                isExpanded: true,
                value: 'Standard',
                items: const [
                  DropdownMenuItem(
                    value: 'Standard',
                    child: Text('Стандартный'),
                  ),
                  DropdownMenuItem(
                    value: 'China',
                    child: Text('Китай'),
                  ),
                  DropdownMenuItem(
                    value: 'Gaming',
                    child: Text('Игровой'),
                  ),
                  DropdownMenuItem(
                    value: 'Streaming',
                    child: Text('Стриминг'),
                  ),
                ],
                onChanged: (value) {
                  // Используется только при создании в диалоге
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Введите название профиля')),
                  );
                  return;
                }
                
                // Создаем новый профиль на основе стандартного
                final newProfile = RoutingProfile(
                  name: name,
                  rules: List.from(RoutingProfile.standard().rules),
                  isSplitTunnelingEnabled: false,
                  isProxyOnlyEnabled: false,
                );
                
                // Начинаем редактирование этого профиля
                Navigator.of(context).pop();
                setState(() {
                  _editingProfile = newProfile;
                });
              },
              child: const Text('Создать'),
            ),
          ],
        );
      },
    ).then((_) => nameController.dispose());
  }
  
  // Показать диалог удаления профиля
  void _showDeleteProfileDialog(RoutingProfile profile) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Удаление профиля'),
          content: Text('Вы уверены, что хотите удалить профиль "${profile.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await _routingService.deleteProfile(profile.name);
                  
                  // Обновляем список профилей
                  setState(() {
                    _availableProfiles = _routingService.savedProfiles;
                    _currentProfile = _routingService.currentProfile;
                  });
                  
                  _showSuccessSnackBar('Профиль успешно удален');
                } catch (e) {
                  _showErrorSnackBar('Ошибка удаления профиля: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
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
  
  // Показать SnackBar с успешным действием
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Маршрутизация',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: _loadProfiles,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Создать профиль',
            onPressed: _showCreateProfileDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _editingProfile != null
              ? _buildProfileEditor()
              : _buildProfilesList(),
    );
  }
  
  // Виджет для отображения списка профилей
  Widget _buildProfilesList() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Текущий профиль
          Text(
            'Текущий профиль маршрутизации',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          
          // Карточка текущего профиля
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _currentProfile.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      _buildProfileBadge(_currentProfile),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Количество правил: ${_currentProfile.rules.length}',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.edit),
                        label: const Text('Редактировать'),
                        onPressed: () => _startEditingProfile(_currentProfile),
                      ),
                      if (_currentProfile.name != 'Standard')
                        OutlinedButton.icon(
                          icon: const Icon(Icons.delete),
                          label: const Text('Удалить'),
                          onPressed: () => _showDeleteProfileDialog(_currentProfile),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Список других профилей
          Text(
            'Доступные профили',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: ListView.builder(
              itemCount: _availableProfiles.length,
              itemBuilder: (context, index) {
                final profile = _availableProfiles[index];
                
                // Пропускаем текущий профиль, так как он уже отображен выше
                if (profile.name == _currentProfile.name) {
                  return const SizedBox.shrink();
                }
                
                return BlurredHover(
                  borderRadius: BorderRadius.circular(8),
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(
                        profile.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('Правила: ${profile.rules.length}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildProfileBadge(profile),
                          const SizedBox(width: 16),
                          ElevatedButton(
                            onPressed: () => _setProfile(profile),
                            child: const Text('Использовать'),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: 'Редактировать',
                            onPressed: () => _startEditingProfile(profile),
                          ),
                          if (profile.name != 'Standard')
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Удалить',
                              onPressed: () => _showDeleteProfileDialog(profile),
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
    );
  }
  
  // Виджет для редактирования профиля
  Widget _buildProfileEditor() {
    if (_editingProfile == null) return const SizedBox.shrink();
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Заголовок с названием профиля
          Row(
            children: [
              Text(
                'Редактирование профиля "${_editingProfile!.name}"',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              // Переключатели опций
              Row(
                children: [
                  const Text('Split Tunneling:'),
                  Switch(
                    value: _editingProfile!.isSplitTunnelingEnabled,
                    onChanged: (value) {
                      setState(() {
                        _editingProfile!.isSplitTunnelingEnabled = value;
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(width: 16),
              Row(
                children: [
                  const Text('Proxy Only:'),
                  Switch(
                    value: _editingProfile!.isProxyOnlyEnabled,
                    onChanged: (value) {
                      setState(() {
                        _editingProfile!.isProxyOnlyEnabled = value;
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Список правил
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Правила маршрутизации (${_editingProfile!.rules.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                
                // Форма добавления нового правила
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Добавить новое правило',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            // Тип правила
                            Expanded(
                              flex: 1,
                              child: DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Тип',
                                  border: OutlineInputBorder(),
                                ),
                                value: _ruleType,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'domain',
                                    child: Text('Домен'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'ip',
                                    child: Text('IP'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _ruleType = value;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            
                            // Значение правила
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: _ruleValueController,
                                decoration: InputDecoration(
                                  labelText: 'Значение',
                                  hintText: _ruleType == 'domain' ? 'example.com' : '192.168.1.0/24',
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            
                            // Действие
                            Expanded(
                              flex: 1,
                              child: DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Действие',
                                  border: OutlineInputBorder(),
                                ),
                                value: _ruleAction,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'proxy',
                                    child: Text('Через VPN'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'direct',
                                    child: Text('Напрямую'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'block',
                                    child: Text('Блокировать'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _ruleAction = value;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 16),
                            
                            // Кнопка добавления
                            ElevatedButton(
                              onPressed: _addRuleToEditingProfile,
                              child: const Text('Добавить'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Список правил
                Expanded(
                  child: _editingProfile!.rules.isEmpty
                      ? const Center(
                          child: Text(
                            'Нет правил. Добавьте первое правило выше.',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _editingProfile!.rules.length,
                          itemBuilder: (context, index) {
                            final rule = _editingProfile!.rules[index];
                            
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Row(
                                  children: [
                                    _buildRuleTypeBadge(rule.type),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        rule.value,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _buildRuleActionBadge(rule.action),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _removeRuleFromEditingProfile(index),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                
                const SizedBox(height: 16),
                
                // Кнопки управления
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _cancelEditingProfile,
                      child: const Text('Отмена'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      onPressed: _saveEditingProfile,
                      child: const Text('Сохранить профиль'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Виджет для отображения типа профиля
  Widget _buildProfileBadge(RoutingProfile profile) {
    Color color = Colors.blue;
    String text = 'Стандартный';
    
    if (profile.isSplitTunnelingEnabled) {
      if (profile.isProxyOnlyEnabled) {
        color = Colors.purple;
        text = 'Выборочный';
      } else {
        color = Colors.orange;
        text = 'Раздельный';
      }
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
        ),
      ),
    );
  }
  
  // Виджет для отображения типа правила
  Widget _buildRuleTypeBadge(String type) {
    Color color;
    String text;
    
    switch (type) {
      case 'domain':
        color = Colors.blue;
        text = 'Домен';
        break;
      case 'ip':
        color = Colors.green;
        text = 'IP';
        break;
      default:
        color = Colors.grey;
        text = type;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
        ),
      ),
    );
  }
  
  // Виджет для отображения действия правила
  Widget _buildRuleActionBadge(String action) {
    Color color;
    String text;
    IconData icon;
    
    switch (action) {
      case 'proxy':
        color = Colors.blue;
        text = 'VPN';
        icon = Icons.vpn_lock;
        break;
      case 'direct':
        color = Colors.green;
        text = 'Напрямую';
        icon = Icons.public;
        break;
      case 'block':
        color = Colors.red;
        text = 'Блок';
        icon = Icons.block;
        break;
      default:
        color = Colors.grey;
        text = action;
        icon = Icons.help_outline;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}