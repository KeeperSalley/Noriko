import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

// Импорт всех страниц
import 'data/models/vpn_config.dart';
import 'presentation/pages/home/home_page.dart';
import 'presentation/pages/servers/servers_page.dart';
import 'presentation/pages/logs/logs_page.dart';
import 'presentation/pages/settings/settings_page.dart';
import 'presentation/themes/app_theme.dart';
import 'presentation/widgets/custom_title_bar.dart';

// Глобальный объект для хранения данных приложения
class AppGlobals {
  static VpnConfig? selectedServer;
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Инициализация WindowManager для десктопной версии
  await windowManager.ensureInitialized();
  
  WindowOptions windowOptions = const WindowOptions(
    size: Size(1000, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: "Noriko VPN",
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  
  // Инициализация прозрачного эффекта окна (только для Windows)
  await Window.initialize();
  await Window.setEffect(
    effect: WindowEffect.acrylic,
    color: Colors.black.withOpacity(0.8),
  );
  
  runApp(const MyApp());
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
  
  // Создаем страницы по требованию, чтобы избежать потери состояния при обновлении главной страницы
  HomePage? _homePage;
  final ServersPage _serversPage = const ServersPage();
  final LogsPage _logsPage = const LogsPage();
  final SettingsPage _settingsPage = const SettingsPage();

  List<Widget> get _pages => [
    _homePage ?? HomePage(selectedServer: AppGlobals.selectedServer),
    _serversPage,
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
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    super.dispose();
  }
  
  // Обработчик смены вкладки
  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      // Если переключаемся на домашнюю страницу, пересоздаем её для обновления
      if (_tabController.index == 0) {
        setState(() {
          _homePage = HomePage(selectedServer: AppGlobals.selectedServer);
        });
      }
    }
  }
  
  // Публичный метод для переключения на домашнюю страницу с выбранным сервером
  void goToHomeWithServer(VpnConfig server) {
    AppGlobals.selectedServer = server;
    setState(() {
      _homePage = HomePage(selectedServer: server);
      _tabController.animateTo(0); // Переключаемся на первую вкладку (Главная)
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Добавляем кастомный заголовок окна
          const CustomTitleBar(
            title: 'Noriko VPN',
            backgroundColor: Color(0xFF0D0D0D),
            iconColor: Colors.white,
          ),
          
          // Основное содержимое
          Expanded(
            child: Row(
              children: [
                // Боковая навигация
                NavigationRail(
                  selectedIndex: _tabController.index,
                  onDestinationSelected: (int index) {
                    // Переключаем вкладку при выборе пункта меню
                    _tabController.animateTo(index);
                  },
                  minWidth: 70,
                  extended: false,
                  backgroundColor: Theme.of(context).colorScheme.background,
                  unselectedIconTheme: IconThemeData(
                    color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                  ),
                  selectedIconTheme: IconThemeData(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  unselectedLabelTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onBackground.withOpacity(0.5),
                  ),
                  selectedLabelTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
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
                
                // Область содержимого с TabBarView
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(), // Отключаем свайп между вкладками
                    children: _pages,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Обработчики окна для WindowManager
  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            title: const Text('Подтверждение'),
            content: const Text('Вы уверены, что хотите закрыть приложение?'),
            actions: [
              TextButton(
                child: const Text('Свернуть'),
                onPressed: () {
                  Navigator.of(context).pop();
                  windowManager.minimize();
                },
              ),
              TextButton(
                child: const Text('Закрыть'),
                onPressed: () {
                  Navigator.of(context).pop();
                  windowManager.destroy();
                },
              ),
            ],
          );
        },
      );
    }
  }
}

// Глобальная функция для доступа к методу перехода на главную с сервером
void goToHomeWithServer(BuildContext context, VpnConfig server) {
  AppGlobals.selectedServer = server;
  
  // Используем TabController из контекста
  final tabController = DefaultTabController.of(context);
  if (tabController != null) {
    tabController.animateTo(0); // Переключаемся на первую вкладку (Главная)
  }
  
  // Обновляем состояние всего приложения через глобальный навигатор
  final state = context.findAncestorStateOfType<_AppLayoutState>();
  if (state != null) {
    state.setState(() {
      state._homePage = HomePage(selectedServer: server);
    });
  }
}