import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../data/models/vpn_config.dart';

class ConfigImportService {
  // Импорт конфигурации из URL-ссылки
  static Future<List<VpnConfig>> importFromUrl(String url) async {
    try {
      // Проверяем, если это уже валидная VPN ссылка (vless://, vmess://, etc.)
      if (url.startsWith('vless://') || 
          url.startsWith('vmess://') || 
          url.startsWith('trojan://') || 
          url.startsWith('ss://')) {
        return [VpnConfig.fromUrl(url)];
      }
      
      // Выполняем GET-запрос к URL для получения конфигурации
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        return _parseResponseContent(response.body);
      } else {
        throw Exception('Ошибка получения данных: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Ошибка импорта: $e');
    }
  }

  // Парсинг содержимого ответа
  static List<VpnConfig> _parseResponseContent(String content) {
    final List<VpnConfig> configs = [];
    final String trimmedContent = content.trim();
    
    try {
      // Сначала проверяем, не прямой ли это VPN URL
      if (_isVpnUrl(trimmedContent)) {
        configs.add(VpnConfig.fromUrl(trimmedContent));
        return configs;
      }
      
      // Пробуем декодировать как Base64
      String decodedContent;
      try {
        decodedContent = utf8.decode(base64.decode(trimmedContent));
      } catch (e) {
        // Если не Base64, используем исходное содержимое
        decodedContent = trimmedContent;
      }
      
      // Разбиваем на строки и обрабатываем каждую
      final List<String> lines = LineSplitter.split(decodedContent).toList();
      
      for (final line in lines) {
        final String trimmedLine = line.trim();
        if (trimmedLine.isEmpty) continue;
        
        // Проверяем, является ли строка VPN URL
        if (_isVpnUrl(trimmedLine)) {
          try {
            configs.add(VpnConfig.fromUrl(trimmedLine));
          } catch (e) {
            print('Ошибка при обработке строки: $e');
          }
        } else {
          // Пробуем декодировать отдельную строку как Base64
          try {
            final String decodedLine = utf8.decode(base64.decode(trimmedLine));
            if (_isVpnUrl(decodedLine)) {
              configs.add(VpnConfig.fromUrl(decodedLine));
            }
          } catch (e) {
            // Пропускаем некорректные строки
          }
        }
      }
      
      if (configs.isEmpty) {
        throw FormatException('Ответ не содержит валидной VPN конфигурации');
      }
      
      return configs;
    } catch (e) {
      if (configs.isNotEmpty) {
        // Если уже нашли какие-то конфигурации, возвращаем их даже при ошибке
        return configs;
      }
      throw FormatException('Не удалось распознать формат ответа: $e');
    }
  }
  
  // Проверка, является ли строка VPN URL
  static bool _isVpnUrl(String text) {
    return text.startsWith('vless://') || 
           text.startsWith('vmess://') || 
           text.startsWith('trojan://') || 
           text.startsWith('ss://');
  }
}