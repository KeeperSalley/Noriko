import 'package:flutter/material.dart';
import '../../core/services/routing_service.dart';

class RoutingProfileDropdown extends StatefulWidget {
  final Function(RoutingProfile)? onProfileChanged;
  
  const RoutingProfileDropdown({
    Key? key,
    this.onProfileChanged,
  }) : super(key: key);

  @override
  _RoutingProfileDropdownState createState() => _RoutingProfileDropdownState();
}

class _RoutingProfileDropdownState extends State<RoutingProfileDropdown> {
  final RoutingService _routingService = RoutingService();
  RoutingProfile? _currentProfile;
  List<RoutingProfile> _availableProfiles = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }
  
  // Загрузка профилей маршрутизации
  Future<void> _loadProfiles() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Инициализируем сервис, если он еще не инициализирован
      if (_routingService.currentProfile == null) {
        await _routingService.initialize();
      }
      
      setState(() {
        _currentProfile = _routingService.currentProfile;
        _availableProfiles = _routingService.savedProfiles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      print('Ошибка загрузки профилей маршрутизации: $e');
    }
  }
  
  // Установка выбранного профиля
  Future<void> _setProfile(RoutingProfile? profile) async {
    if (profile == null) return;
    
    try {
      await _routingService.setCurrentProfile(profile);
      setState(() {
        _currentProfile = profile;
      });
      
      // Вызываем колбэк, если он указан
      if (widget.onProfileChanged != null) {
        widget.onProfileChanged!(profile);
      }
    } catch (e) {
      print('Ошибка установки профиля: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    
    if (_currentProfile == null || _availableProfiles.isEmpty) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: Text('Профили недоступны'),
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor,
          width: 1,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButton<RoutingProfile>(
        isExpanded: true,
        value: _currentProfile,
        underline: const SizedBox(),
        icon: const Icon(Icons.route),
        hint: const Text('Выберите профиль маршрутизации'),
        items: _availableProfiles.map((profile) {
          return DropdownMenuItem<RoutingProfile>(
            value: profile,
            child: Row(
              children: [
                _buildProfileTypeIcon(profile),
                const SizedBox(width: 8),
                Text(profile.name),
                if (profile.isSplitTunnelingEnabled)
                  const SizedBox(width: 8),
                if (profile.isSplitTunnelingEnabled)
                  _buildProfileBadge(profile),
              ],
            ),
          );
        }).toList(),
        onChanged: _setProfile,
      ),
    );
  }
  
  // Виджет для отображения иконки типа профиля
  Widget _buildProfileTypeIcon(RoutingProfile profile) {
    if (profile.isSplitTunnelingEnabled) {
      if (profile.isProxyOnlyEnabled) {
        return const Icon(Icons.filter_list, color: Colors.purple, size: 20);
      } else {
        return const Icon(Icons.alt_route, color: Colors.orange, size: 20);
      }
    }
    return const Icon(Icons.public, color: Colors.blue, size: 20);
  }
  
  // Виджет для отображения типа профиля
  Widget _buildProfileBadge(RoutingProfile profile) {
    Color color = Colors.blue;
    String text = 'Стандартный';
    
    if (profile.isSplitTunnelingEnabled) {
      if (profile.isProxyOnlyEnabled) {
        color = Colors.purple;
        text = 'Выборочный';
      } else {
        color = Colors.orange;
        text = 'Раздельный';
      }
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: color,
        ),
      ),
    );
  }
}