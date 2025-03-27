class VpnConfig {
  final String protocol;
  final String id;
  final String address;
  final int port;
  final Map<String, String> params;
  final String tag;
  
  VpnConfig({
    required this.protocol,
    required this.id,
    required this.address,
    required this.port,
    required this.params,
    required this.tag,
  });
  
  // Фабричный метод для создания из URL-схемы
  factory VpnConfig.fromUrl(String url) {
    try {
      // Разбиваем URL на составные части
      final Uri parsedUrl = Uri.parse(url);
      
      // Определение протокола (vless, vmess и т.д.)
      final protocol = parsedUrl.scheme;
      
      // Используем userInfo как ID
      final id = parsedUrl.userInfo;
      
      // Хост и порт
      final address = parsedUrl.host;
      final port = parsedUrl.port;
      
      // Параметры из query string
      final params = Map<String, String>.from(parsedUrl.queryParameters);
      
      // Тег из фрагмента URL (части после #)
      final tag = Uri.decodeComponent(parsedUrl.fragment);
      
      return VpnConfig(
        protocol: protocol,
        id: id,
        address: address,
        port: port,
        params: params,
        tag: tag,
      );
    } catch (e) {
      throw FormatException('Неверный формат ссылки: $e');
    }
  }
  
  // Преобразование в строковое представление
  String toUrl() {
    final Uri uri = Uri(
      scheme: protocol,
      userInfo: id,
      host: address,
      port: port,
      queryParameters: params,
      fragment: tag,
    );
    return uri.toString();
  }
  
  // Преобразование в JSON для сохранения
  Map<String, dynamic> toJson() {
    return {
      'protocol': protocol,
      'id': id,
      'address': address,
      'port': port,
      'params': params,
      'tag': tag,
    };
  }
  
  // Создание из JSON
  factory VpnConfig.fromJson(Map<String, dynamic> json) {
    return VpnConfig(
      protocol: json['protocol'],
      id: json['id'],
      address: json['address'],
      port: json['port'],
      params: Map<String, String>.from(json['params']),
      tag: json['tag'],
    );
  }
  
  // Удобное представление для отображения
  String get displayName => tag.isNotEmpty ? tag : '$address:$port';
  
  // Проверка поддерживается ли протокол
  bool get isSupported => ['vless', 'vmess', 'trojan', 'shadowsocks'].contains(protocol.toLowerCase());
}