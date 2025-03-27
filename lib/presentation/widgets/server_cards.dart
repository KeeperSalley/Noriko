import 'package:flutter/material.dart';
import '../../../data/models/vpn_config.dart';
import 'hover_effect.dart';

// Виджет карточки сервера, который можно использовать повторно
class ServerCard extends StatefulWidget {
  final VpnConfig server;
  final bool isSelected;
  final VoidCallback onTap;

  const ServerCard({
    Key? key,
    required this.server,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  @override
  State<ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends State<ServerCard> {
  bool _isHovered = false;

  // Функция для получения иконки протокола
  IconData _getProtocolIcon(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'vless':
        return Icons.bolt;
      case 'vmess':
        return Icons.shield;
      case 'trojan':
        return Icons.security;
      case 'shadowsocks':
      case 'ss':
        return Icons.vpn_key;
      default:
        return Icons.language;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlurredHover(
      hoverColor: widget.isSelected 
        ? Theme.of(context).colorScheme.primary
        : const Color(0xFF2D132D),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 140,
          margin: const EdgeInsets.only(right: 12),
          child: Card(
            elevation: widget.isSelected ? 4 : 2,
            color: widget.isSelected 
              ? Theme.of(context).colorScheme.primary.withOpacity(0.1) 
              : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: widget.isSelected 
                ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2) 
                : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getProtocolIcon(widget.server.protocol),
                    color: widget.isSelected 
                      ? Theme.of(context).colorScheme.primary 
                      : Colors.grey,
                    size: 24,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.server.displayName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: widget.isSelected 
                        ? Theme.of(context).colorScheme.primary 
                        : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.server.protocol.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Расширеный виджет для списка серверов с улучшенной производительностью
class ServerListView extends StatelessWidget {
  final List<VpnConfig> servers;
  final VpnConfig? currentServer;
  final Function(VpnConfig) onServerSelected;

  const ServerListView({
    Key? key,
    required this.servers,
    this.currentServer,
    required this.onServerSelected,
  }) : super(key: key);

  bool _isSelected(VpnConfig server) {
    if (currentServer == null) return false;
    
    return currentServer!.address == server.address && 
           currentServer!.port == server.port &&
           currentServer!.id == server.id;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: servers.length,
        // Усиленная оптимизация для предотвращения мерцания
        itemBuilder: (context, index) {
          final server = servers[index];
          final isSelected = _isSelected(server);
          
          // Используем ключ, основанный на данных сервера, а не на индексе
          return ServerCard(
            key: ValueKey('${server.id}-${server.address}-${server.port}'),
            server: server,
            isSelected: isSelected,
            onTap: () => onServerSelected(server),
          );
        },
      ),
    );
  }
}