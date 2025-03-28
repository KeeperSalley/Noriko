import 'package:flutter/material.dart';
import '../../../core/services/routing_service.dart';

/// Виджет для отображения активных правил маршрутизации
class ActiveRoutingRules extends StatelessWidget {
  final RoutingProfile profile;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  const ActiveRoutingRules({
    Key? key,
    required this.profile,
    this.expanded = false,
    required this.onToggleExpanded,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок с переключателем
        GestureDetector(
          onTap: onToggleExpanded,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Активные правила маршрутизации',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
        
        // Список правил в развернутом состоянии
        if (expanded)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Показать тип профиля
                _buildProfileTypeInfo(context),
                const Divider(height: 16),
                
                // Список правил
                ...profile.rules.map((rule) => _buildRuleItem(context, rule)).toList(),
                
                // Пустое состояние, если нет правил
                if (profile.rules.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'Нет активных правил маршрутизации',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
  
  Widget _buildProfileTypeInfo(BuildContext context) {
    String typeText = 'Стандартный режим маршрутизации';
    IconData icon = Icons.public;
    Color color = Colors.blue;
    
    if (profile.isSplitTunnelingEnabled) {
      if (profile.isProxyOnlyEnabled) {
        typeText = 'Выборочный режим прокси (только указанные приложения/сайты)';
        icon = Icons.filter_list;
        color = Colors.purple;
      } else {
        typeText = 'Режим разделения трафика (обход указанных приложений/сайтов)';
        icon = Icons.alt_route;
        color = Colors.orange;
      }
    }
    
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            typeText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildRuleItem(BuildContext context, RouteRule rule) {
    Color ruleColor;
    IconData ruleIcon;
    String actionText;
    
    // Установка цвета и иконки в зависимости от действия
    switch (rule.action) {
      case 'proxy':
        ruleColor = Colors.blue;
        ruleIcon = Icons.vpn_lock;
        actionText = 'Через VPN';
        break;
      case 'direct':
        ruleColor = Colors.green;
        ruleIcon = Icons.public;
        actionText = 'Напрямую';
        break;
      case 'block':
        ruleColor = Colors.red;
        ruleIcon = Icons.block;
        actionText = 'Блокировать';
        break;
      default:
        ruleColor = Colors.grey;
        ruleIcon = Icons.help_outline;
        actionText = rule.action;
    }
    
    // Перевод типа правила
    String ruleTypeText;
    switch (rule.type) {
      case 'domain':
        ruleTypeText = 'Домен';
        break;
      case 'ip':
        ruleTypeText = 'IP';
        break;
      default:
        ruleTypeText = rule.type;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Бейдж типа правила
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              ruleTypeText,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          
          // Значение правила
          Expanded(
            child: Text(
              rule.value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          
          // Индикатор действия
          Icon(ruleIcon, color: ruleColor, size: 16),
          const SizedBox(width: 4),
          Text(
            actionText,
            style: TextStyle(
              fontSize: 12,
              color: ruleColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}