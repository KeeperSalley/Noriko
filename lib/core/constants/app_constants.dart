class AppConstants {
  // Название приложения
  static const String appName = 'Noriko VPN';
  static const String appVersion = '1.0.0';
  
  // Настройки сервера по умолчанию
  static const int defaultServerPort = 443;
  static const int defaultSocksPort = 1080;
  static const int defaultHttpPort = 8118;
  
  // Поддерживаемые протоколы
  static const List<String> supportedProtocols = [
    'V2Ray',
    'Trojan',
    'Shadowsocks',
  ];
  
  // Пути к файлам
  static const String configDir = 'config';
  static const String logsDir = 'logs';
  static const String mainConfigFile = 'settings.json';
  static const String serversConfigFile = 'servers.json';
  
  // Ключи для настроек
  static const String keyAutoStart = 'autoStart';
  static const String keyAutoConnect = 'autoConnect';
  static const String keyMinimizeToTray = 'minimizeToTray';
  static const String keyEnableLogging = 'enableLogging';
  static const String keyEnableNotifications = 'enableNotifications';
  static const String keySelectedTheme = 'selectedTheme';
  static const String keySelectedLanguage = 'selectedLanguage';
  static const String keyRoutingMode = 'routingMode';
  static const String keyUseCustomDNS = 'useCustomDNS';
  static const String keyPrimaryDNS = 'primaryDNS';
  static const String keySecondaryDNS = 'secondaryDNS';
  static const String keyLastServer = 'lastServer';
  
  // Языки приложения
  static const Map<String, String> appLanguages = {
    'ru': 'Русский',
    'en': 'Английский',
    'zh': 'Китайский',
    'es': 'Испанский',
  };
  
  // Темы приложения
  static const List<String> appThemes = [
    'Системная',
    'Светлая',
    'Тёмная',
  ];
}