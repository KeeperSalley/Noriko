import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../data/models/vpn_config.dart';
import 'logger_service.dart';

class ServerStorageService {
  static const String _fileName = 'servers.json';
  
  // Сохранение списка серверов
  static Future<void> saveServers(List<VpnConfig> servers) async {
    try {
      final directory = await _getStorageDirectory();
      final file = File('${directory.path}/$_fileName');
      
      final jsonData = servers.map((server) => server.toJson()).toList();
      final jsonString = jsonEncode(jsonData);
      
      await file.writeAsString(jsonString);
      LoggerService.info('Серверы успешно сохранены в $_fileName (${servers.length} шт.)');
    } catch (e) {
      LoggerService.error('Ошибка при сохранении серверов', e);
      rethrow;
    }
  }
  
  // Загрузка списка серверов
  static Future<List<VpnConfig>> loadServers() async {
    try {
      final directory = await _getStorageDirectory();
      final file = File('${directory.path}/$_fileName');
      
      if (!await file.exists()) {
        LoggerService.info('Файл $_fileName не найден. Возвращаем пустой список.');
        return [];
      }
      
      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString) as List;
      
      final servers = jsonData
          .map((data) => VpnConfig.fromJson(Map<String, dynamic>.from(data)))
          .toList();
      
      LoggerService.info('Загружено ${servers.length} серверов из $_fileName');
      return servers;
    } catch (e) {
      LoggerService.error('Ошибка при загрузке серверов', e);
      // Возвращаем пустой список в случае ошибки, чтобы не крашить приложение
      return [];
    }
  }
  
  // Удаление сервера по индексу
  static Future<void> deleteServer(List<VpnConfig> servers, int index) async {
    if (index < 0 || index >= servers.length) {
      LoggerService.warning('Попытка удалить сервер с недопустимым индексом: $index');
      return;
    }
    
    final server = servers[index];
    servers.removeAt(index);
    await saveServers(servers);
    LoggerService.info('Удален сервер: ${server.displayName}');
  }
  
  // Получение директории для хранения данных
  static Future<Directory> _getStorageDirectory() async {
    Directory directory;
    
    try {
      // На Windows, macOS и Linux используем директорию приложения
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        directory = await getApplicationSupportDirectory();
      }
      // На Android используем внешнюю директорию
      else if (Platform.isAndroid) {
        directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      }
      // На других платформах используем директорию документов
      else {
        directory = await getApplicationDocumentsDirectory();
      }
      
      LoggerService.debug('Директория для хранения: ${directory.path}');
      return directory;
    } catch (e) {
      LoggerService.error('Ошибка при получении директории хранения', e);
      // Запасной вариант - временная директория
      directory = await getTemporaryDirectory();
      LoggerService.warning('Используем временную директорию: ${directory.path}');
      return directory;
    }
  }
}