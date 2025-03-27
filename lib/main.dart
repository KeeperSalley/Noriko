import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
// Импорт всех страниц
import 'data/models/vpn_config.dart';
import 'presentation/pages/home/home_page.dart';
import 'presentation/pages/servers/servers_page.dart';
import 'presentation/pages/logs/logs_page.dart';
import 'presentation/pages/settings/settings_page.dart';
import 'presentation/themes/app_theme.dart';
import 'presentation/widgets/custom_title_bar.dart';

// Глобальный класс для управления навигацией и данными
class AppGlobals {
  // Выбранный сервер для передачи между вкладками
  static VpnConfig? selectedServer;
  
  // Ключ навигатора для глобального доступа
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // Хранение текущего IP-адреса
  static String? currentIP;
  static bool isLoadingIP = false;
  
  // Добавляем флаг состояния подключения
  static bool isConnected = false;
  
  // Добавляем таймер подключения
  static Timer? connectionTimer;
  static Duration connectionDuration = Duration.zero;
  static String connectionTimeText = "00:00:00";
  
  // Добавляем список слушателей для отслеживания изменений состояния
  static final List<Function()> _listeners = [];
  
  // Метод для добавления слушателя
  static void addListener(Function() listener) {
    _listeners.add(listener);
  }
  
  // Метод для удаления слушателя
  static void removeListener(Function() listener) {
    _listeners.remove(listener);
  }
  
  // Метод для уведомления всех слушателей об изменениях
  static void notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }
  
  // Функция для обновления и сохранения выбранного сервера
  static void updateSelectedServer(VpnConfig server) {
    selectedServer = server;
    // Уведомляем всех слушателей об изменении
    notifyListeners();
  }
  
  // Обновляем метод для изменения состояния подключения
  static void setConnected(bool value) {
    isConnected = value;
    
    if (value) {
      // Запускаем таймер подключения
      connectionDuration = Duration.zero;
      connectionTimeText = "00:00:00";
      connectionTimer?.cancel();
      connectionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        connectionDuration = connectionDuration + const Duration(seconds: 1);
        connectionTimeText = _formatDuration(connectionDuration);
        notifyListeners();
      });
    } else {
      // Останавливаем таймер
      connectionTimer?.cancel();
      connectionTimer = null;
    }
    
    notifyListeners();
  }
  
  // Метод для форматирования длительности в читаемый формат
  static String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String hours = twoDigits(duration.inHours);
    String minutes = twoDigits(duration.inMinutes.remainder(60));
    String seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }
  
  // Функция для получения текущего IP-адреса
  static Future<String> getCurrentIP() async {
    // Если уже загружаем IP, возвращаем текущее значение или "Загрузка..."
    if (isLoadingIP) {
      return currentIP ?? "Загрузка...";
    }
    
    // Если IP уже получен и не требуется обновление, возвращаем его
    if (currentIP != null) {
      return currentIP!;
    }
    
    // Начинаем загрузку
    isLoadingIP = true;
    
    try {
      // Пробуем основной API
      final response = await http.get(Uri.parse('https://api.ipify.org'));
      if (response.statusCode == 200) {
        currentIP = response.body.trim();
        return currentIP!;
      }
      
      // Запасной API 
      final fallbackResponse = await http.get(Uri.parse('https://api.my-ip.io/ip'));
      if (fallbackResponse.statusCode == 200) {
        currentIP = fallbackResponse.body.trim();
        return currentIP!;
      }
      
      // Еще один запасной вариант
      final thirdOption = await http.get(Uri.parse('https://checkip.amazonaws.com'));
      if (thirdOption.statusCode == 200) {
        currentIP = thirdOption.body.trim();
        return currentIP!;
      }
      
      currentIP = "Недоступно";
      return currentIP!;
    } catch (e) {
      currentIP = "Ошибка";
      return currentIP!;
    } finally {
      isLoadingIP = false;
    }
  }
  
  // Сброс IP при подключении/отключении, чтобы принудительно обновить
  static void resetIP() {
    currentIP = null;
  }
  
  // Метод для освобождения ресурсов при закрытии приложения
  static void cleanupResources() {
    // Отменяем таймер
    connectionTimer?.cancel();
    connectionTimer = null;
    
    // Сбрасываем слушателей
    _listeners.clear();
    
    // Сбрасываем остальные ресурсы
    currentIP = null;
    isLoadingIP = false;
  }
}

// Глобальные функции для более удобного вызова в коде
void goToHomeWithServer(BuildContext context, VpnConfig server) {
  // Сохраняем сервер глобально
  AppGlobals.updateSelectedServer(server);
  
  // Находим состояние AppLayout
  final state = context.findAncestorStateOfType<_AppLayoutState>();
  
  if (state != null) {
    // Используем метод состояния для обновления UI и перехода
    state.goToHomeWithServer(server);
  } else {
    // Запасной вариант - прямая навигация
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => HomePage(selectedServer: server)),
    );
  }
}

void goToServersPage(BuildContext context) {
  final state = context.findAncestorStateOfType<_AppLayoutState>();
  
  if (state != null) {
    state.goToServersPage();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация WindowManager
  await windowManager.ensureInitialized();
  
  // Сначала скрываем окно
  await windowManager.hide();
  
  // Настройка параметров окна
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1200, 700),
    center: true,
    backgroundColor: Color(0xFF1C091C), // Непрозрачный цвет во время инициализации
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: "Noriko VPN",
  );
  
  // Настраиваем окно
  await windowManager.setPreventClose(true);
  await windowManager.waitUntilReadyToShow(windowOptions);
  
  // Инициализация прозрачного эффекта окна
  await Window.initialize();
  await Window.setEffect(
    effect: WindowEffect.acrylic,
    color: const Color(0xFF1C091C).withOpacity(0.8),
  );

  // Предварительно загружаем IP
  AppGlobals.getCurrentIP();
  
  // Запускаем приложение
  runApp(const MyApp());
  
  // Даем время для инициализации UI
  await Future.delayed(const Duration(milliseconds: 300));
  
  // После всей инициализации показываем окно
  await windowManager.show();
  await windowManager.focus();
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noriko VPN',
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      navigatorKey: AppGlobals.navigatorKey,
      home: const AppLayout(),
    );
  }
}

class AppLayout extends StatefulWidget {
  const AppLayout({Key? key}) : super(key: key);

  @override
  _AppLayoutState createState() => _AppLayoutState();
}

class _AppLayoutState extends State<AppLayout> with WindowListener, TickerProviderStateMixin {
  late TabController _tabController;
  final Duration _animationDuration = const Duration(milliseconds: 300); // Длительность анимации для плавности
  
  // Создаем страницы по требованию, чтобы избежать потери состояния при обновлении главной страницы
  HomePage? _homePage;
  ServersPage? _serversPage; // Убрали const
  final LogsPage _logsPage = const LogsPage();
  final SettingsPage _settingsPage = const SettingsPage();

  List<Widget> get _pages => [
    _homePage ?? HomePage(selectedServer: AppGlobals.selectedServer),
    _serversPage ?? ServersPage(initialSelectedServer: AppGlobals.selectedServer),
    _logsPage,
    _settingsPage,
  ];

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _tabController = TabController(length: 4, vsync: this);
    
    // Слушаем изменение вкладок для обновления UI
    _tabController.addListener(_handleTabSelection);
    
    // Добавляем слушатель изменений глобального состояния
    AppGlobals.addListener(_forceUpdatePages);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    
    // Удаляем слушатель при уничтожении
    AppGlobals.removeListener(_forceUpdatePages);
    
    // Очищаем ресурсы
    AppGlobals.cleanupResources();
    
    super.dispose();
  }
  
  // Метод для принудительного обновления всех страниц
  void _forceUpdatePages() {
    if (!mounted) return;
    
    setState(() {
      // Пересоздаем все страницы с текущим глобальным состоянием
      _homePage = HomePage(selectedServer: AppGlobals.selectedServer);
      _serversPage = ServersPage(initialSelectedServer: AppGlobals.selectedServer);
      // Страницы _logsPage и _settingsPage не нуждаются в обновлении
    });
  }
  
  // Обработчик смены вкладки
  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      // Пересоздаем страницы при переключении для актуального состояния
      if (_tabController.index == 0) {
        setState(() {
          // Важно: передаем выбранный сервер при создании страницы
          _homePage = HomePage(selectedServer: AppGlobals.selectedServer);
        });
      } else if (_tabController.index == 1) {
        setState(() {
          // Также передаем выбранный сервер в ServersPage
          _serversPage = ServersPage(initialSelectedServer: AppGlobals.selectedServer);
        });
      }
    }
  }
  
  // Метод для перехода на домашнюю страницу с выбранным сервером
  void goToHomeWithServer(VpnConfig server) {
    // КРИТИЧЕСКОЕ ИЗМЕНЕНИЕ: Сначала пересоздаем домашнюю страницу, затем анимируем вкладку
    
    // 1. Сохраняем сервер в глобальное состояние
    AppGlobals.selectedServer = server;
    
    // 2. Пересоздаем страницу Home с новым выбранным сервером
    setState(() {
      _homePage = HomePage(selectedServer: server);
    });
    
    // 3. После обновления UI переключаемся на вкладку Главная с плавной анимацией
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _tabController.animateTo(
          0,
          duration: _animationDuration,
          curve: Curves.easeInOut, // Плавная кривая анимации
        );
      }
    });
  }
  
  // Метод для перехода на страницу серверов
  void goToServersPage() {
    setState(() {
      _serversPage = ServersPage(initialSelectedServer: AppGlobals.selectedServer);
      _tabController.animateTo(
        1,
        duration: _animationDuration,
        curve: Curves.easeInOut, // Плавная кривая анимации
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        body: Column(
          children: [
            // Добавляем кастомный заголовок окна
            const CustomTitleBar(
              title: 'Noriko VPN',
              backgroundColor: Color(0xFF1C091C),
              iconColor: Colors.white,
            ),
            
            // Основное содержимое
            Expanded(
              child: Row(
                children: [
                  // Боковая навигация с улучшенной стилизацией
                  NavigationRail(
                    selectedIndex: _tabController.index,
                    onDestinationSelected: (int index) {
                      // Переключаем вкладку при выборе пункта меню с плавной анимацией
                      setState(() {
                        _tabController.animateTo(
                          index,
                          duration: _animationDuration,
                          curve: Curves.easeInOut, // Плавная кривая анимации
                        );
                      });
                    },
                    minWidth: 70,
                    extended: false,
                    backgroundColor: Theme.of(context).colorScheme.background,
                    unselectedIconTheme: IconThemeData(
                      color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                      size: 24,
                    ),
                    selectedIconTheme: IconThemeData(
                      color: Theme.of(context).colorScheme.primary,
                      size: 24,
                    ),
                    unselectedLabelTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                      fontSize: 12,
                    ),
                    selectedLabelTextStyle: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    // Добавляем индикатор выделения
                    useIndicator: true,
                    indicatorColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home),
                        label: Text('Главная'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.dns_outlined),
                        selectedIcon: Icon(Icons.dns),
                        label: Text('Серверы'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        selectedIcon: Icon(Icons.receipt_long),
                        label: Text('Логи'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: Text('Настройки'),
                      ),
                    ],
                  ),
                  
                  // Линия разделителя
                  VerticalDivider(
                    thickness: 1,
                    width: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                  
                  // Область содержимого с TabBarView и плавным переходом
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _tabController,
                      builder: (context, child) {
                        return TabBarView(
                          controller: _tabController,
                          physics: const NeverScrollableScrollPhysics(), // Отключаем свайп между вкладками
                          children: _pages,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Обработчики окна для WindowManager
  @override
  void onWindowClose() async {
    // Отменяем таймер перед показом диалога, чтобы он не тратил ресурсы
    AppGlobals.connectionTimer?.cancel();
    
    // Проверяем, требуется ли предотвращение закрытия
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      showDialog(
        context: context,
        barrierDismissible: false, // Пользователь должен сделать выбор
        builder: (_) {
          return AlertDialog(
            title: const Text('Подтверждение'),
            content: const Text('Вы уверены, что хотите закрыть приложение?'),
            actions: [
              TextButton(
                child: const Text('Свернуть'),
                onPressed: () {
                  // Если отменили закрытие, восстанавливаем таймер если нужно
                  if (AppGlobals.isConnected && AppGlobals.connectionTimer == null) {
                    AppGlobals.setConnected(true); // Пересоздаст таймер
                  }
                  Navigator.of(context).pop();
                  windowManager.minimize();
                },
              ),
              TextButton(
                child: const Text('Закрыть'),
                onPressed: () {
                  // Очищаем ресурсы и закрываем приложение
                  AppGlobals.cleanupResources();
                  Navigator.of(context).pop();
                  windowManager.destroy();
                },
              ),
            ],
          );
        },
      );
    } else {
      // Если предотвращение закрытия не требуется, просто закрываем окно
      AppGlobals.cleanupResources();
      await windowManager.destroy();
    }
  }
}