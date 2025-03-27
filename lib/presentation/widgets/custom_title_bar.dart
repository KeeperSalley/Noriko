import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatelessWidget {
  final String title;
  final Color backgroundColor;
  final Color iconColor;

  const CustomTitleBar({
    Key? key,
    required this.title,
    this.backgroundColor = Colors.transparent,
    this.iconColor = Colors.white,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: backgroundColor,
      child: Row(
        children: [
          // Логотип и название
          const SizedBox(width: 16),
          Icon(Icons.shield, color: iconColor, size: 16),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: iconColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          
          // Draggable area (для перемещения окна)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (details) {
                windowManager.startDragging();
              },
              child: Container(),
            ),
          ),
          
          // Кнопки управления окном
          _buildWindowButton(
            icon: Icons.minimize,
            onPressed: () async {
              await windowManager.minimize();
            },
            tooltip: 'Свернуть',
          ),
          _buildWindowButton(
            icon: Icons.crop_square,
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            tooltip: 'Развернуть',
          ),
          _buildWindowButton(
            icon: Icons.close,
            onPressed: () async {
              await windowManager.close();
            },
            tooltip: 'Закрыть',
            hoverColor: Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildWindowButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color? hoverColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          hoverColor: hoverColor ?? Colors.black12,
          child: SizedBox(
            width: 40,
            height: 32,
            child: Icon(
              icon,
              color: iconColor,
              size: 16,
            ),
          ),
        ),
      ),
    );
  }
}