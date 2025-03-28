// Для настройки стандартного профиля маршрутизации, который будет проксировать весь трафик (TCP и UDP),
// необходимо изменить метод RoutingProfile.standard() в файле routing_service.dart:

factory RoutingProfile.standard() {
  return RoutingProfile(
    name: 'Standard',
    rules: [
      // Направить весь трафик через прокси по умолчанию
      RouteRule(type: 'default', value: 'default', action: 'proxy'),

      // Локальные/частные сети - напрямую
      RouteRule(type: 'ip', value: 'geoip:private', action: 'direct'),
      
      // Реклама и вредоносные сайты - блокировать
      RouteRule(type: 'domain', value: 'geosite:category-ads', action: 'block'),
      
      // Указываем явно, что TCP трафик идет через прокси
      RouteRule(type: 'protocol', value: 'tcp', action: 'proxy'),
      
      // Указываем явно, что UDP трафик идет через прокси
      RouteRule(type: 'protocol', value: 'udp', action: 'proxy'),
    ],
    isSplitTunnelingEnabled: false,
    isProxyOnlyEnabled: false,
  );
}

// Кроме того, для обеспечения проксирования всего трафика, нужно в файле vpn_connection_manager.dart
// изменить метод _generateV2RayConfig, добавив поддержку UDP для SOCKS прокси в inbounds:

Future<String> _generateV2RayConfig(VpnConfig config) async {
  // Create base V2Ray config
  final Map<String, dynamic> v2rayConfig = {
    "log": {
      "loglevel": "warning"
    },
    "inbounds": [
      {
        "port": 10808,
        "listen": "127.0.0.1",
        "protocol": "socks",
        "settings": {
          "udp": true, // Включаем поддержку UDP для SOCKS прокси
          "auth": "noauth"
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        }
      },
      {
        "port": 10809,
        "listen": "127.0.0.1",
        "protocol": "http",
        "settings": {},
        "sniffing": {
          "enabled": true,
          "destOverride": ["http", "tls"]
        }
      }
    ],
    "outbounds": [
      {
        "protocol": config.protocol.toLowerCase(),
        "settings": {
          "vnext": [
            {
              "address": config.address,
              "port": config.port,
              "users": [
                {
                  "id": config.id,
                  "encryption": config.params["encryption"] ?? "none",
                  "flow": config.params["flow"] ?? "",
                  "security": config.params["security"] ?? "none"
                }
              ]
            }
          ]
        },
        "streamSettings": {
          "network": config.params["type"] ?? "tcp",
          "security": config.params["security"] ?? "none",
          "tlsSettings": config.params["security"] == "tls" ? {
            "serverName": config.params["sni"] ?? config.address,
            "allowInsecure": config.params["allowInsecure"] == "true"
          } : null,
          "wsSettings": config.params["type"] == "ws" ? {
            "path": config.params["path"] ?? "/",
            "headers": {
              "Host": config.params["host"] ?? config.address
            }
          } : null
        },
        "mux": {
          "enabled": true,
          "concurrency": 8
        },
        "tag": "proxy"
      },
      {
        "protocol": "freedom",
        "settings": {
          "domainStrategy": "UseIP", // Используем IP для доменов
          "userLevel": 0
        },
        "tag": "direct"
      },
      {
        "protocol": "blackhole",
        "settings": {},
        "tag": "block"
      }
    ],
    // Get routing config from routing service
    "routing": _routingService.generateV2RayRouting(),
    
    // DNS configuration to avoid leaks
    "dns": {
      "servers": [
        "8.8.8.8", // Google DNS через прокси
        "1.1.1.1", // Cloudflare DNS через прокси
        {
          "address": "114.114.114.114", // Китайский DNS напрямую
          "port": 53,
          "domains": ["geosite:cn"]
        },
        "localhost"
      ],
      "tag": "dns-out"
    },
  };
  
  return jsonEncode(v2rayConfig);
}

// Для поддержки UDP трафика также нужно модифицировать метод generateV2RayRouting в routing_service.dart:

Map<String, dynamic> generateV2RayRouting() {
  final rules = <Map<String, dynamic>>[];
  
  // Group rules by action
  final Map<String, List<RouteRule>> rulesByAction = {};
  
  for (final rule in _currentProfile.rules) {
    if (!rulesByAction.containsKey(rule.action)) {
      rulesByAction[rule.action] = [];
    }
    rulesByAction[rule.action]!.add(rule);
  }
  
  // Добавляем правило для DNS-запросов
  rules.add({
    'type': 'field',
    'port': 53,
    'outboundTag': 'dns-out',
  });
  
  // Process rules by action
  rulesByAction.forEach((action, actionRules) {
    // Group rules by type
    final Map<String, List<String>> valuesByType = {};
    
    for (final rule in actionRules) {
      if (!valuesByType.containsKey(rule.type)) {
        valuesByType[rule.type] = [];
      }
      valuesByType[rule.type]!.add(rule.value);
    }
    
    // Create rule for each type
    valuesByType.forEach((type, values) {
      final rule = <String, dynamic>{
        'type': 'field',
        'outboundTag': action,
      };
      
      // Set appropriate field based on type
      switch (type) {
        case 'domain':
          rule['domain'] = values;
          break;
        case 'ip':
          rule['ip'] = values;
          break;
        case 'port':
          rule['port'] = values.join(',');
          break;
        case 'protocol':
          rule['protocol'] = values;
          break;
        case 'default':
          // Правило по умолчанию добавляется в конце
          continue;
      }
      
      rules.add(rule);
    });
  });
  
  // Если есть правило "default" для прокси, добавляем его последним
  if (rulesByAction.containsKey('proxy') && 
      rulesByAction['proxy']!.any((rule) => rule.type == 'default')) {
    rules.add({
      'type': 'field',
      'outboundTag': 'proxy',
    });
  }
  
  // Create routing configuration
  return {
    'domainStrategy': 'IPIfNonMatch',
    'domainMatcher': 'mph',
    'rules': rules,
  };
}