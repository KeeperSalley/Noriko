import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/services/config_import_service.dart';
import '../../data/models/vpn_config.dart';

class ImportConfigDialog extends StatefulWidget {
  final Function(List<VpnConfig> configs) onImportSuccess;

  const ImportConfigDialog({
    Key? key,
    required this.onImportSuccess,
  }) : super(key: key);

  @override
  _ImportConfigDialogState createState() => _ImportConfigDialogState();
}

class _ImportConfigDialogState extends State<ImportConfigDialog> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  String _infoMessage = '';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _importConfig() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _errorMessage = 'Введите URL или ссылку конфигурации';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _infoMessage = 'Получение данных...';
    });

    try {
      final configs = await ConfigImportService.importFromUrl(url);
      if (configs.isNotEmpty) {
        if (mounted) {
          Navigator.of(context).pop();
          widget.onImportSuccess(configs);
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Не удалось получить конфигурацию из ссылки';
          _infoMessage = '';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Ошибка: ${e.toString().replaceAll('Exception: ', '')}';
        _infoMessage = '';
      });
    }
  }

  Future<void> _pasteFromClipboard() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        _urlController.text = data.text!;
        _errorMessage = '';
      });
    }
  }

  bool _isDirectVpnConfig(String text) {
    final trimmed = text.trim();
    return trimmed.startsWith('vless://') || 
           trimmed.startsWith('vmess://') || 
           trimmed.startsWith('trojan://') || 
           trimmed.startsWith('ss://');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Импорт конфигурации'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Введите URL или ссылку на конфигурацию VPN:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'https://... или vless://...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste),
                tooltip: 'Вставить из буфера обмена',
                onPressed: _pasteFromClipboard,
              ),
            ),
            maxLines: 3,
            keyboardType: TextInputType.url,
            onChanged: (value) {
              // Если вставлена прямая VPN-ссылка, сразу импортируем
              if (_isDirectVpnConfig(value) && !_isLoading) {
                _importConfig();
              }
            },
          ),
          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _errorMessage,
                style: TextStyle(
                  color: Colors.red[400],
                  fontSize: 14,
                ),
              ),
            ),
          if (_infoMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                _infoMessage,
                style: TextStyle(
                  color: Colors.blue[400],
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _importConfig,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Text('Импортировать'),
        ),
      ],
    );
  }
}