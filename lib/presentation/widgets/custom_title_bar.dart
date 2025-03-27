import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatelessWidget {
  final String title;
  final Color backgroundColor;
  final Color iconColor;
  
  // Используем константу для цвета
  static const Color defaultBackgroundColor = Color(0xFF1C091C);
  static const Color primaryColor = Color(0xFFC60E7A);

  const CustomTitleBar({
    Key? key,
    required this.title,
    this.backgroundColor = defaultBackgroundColor,
    this.iconColor = Colors.white,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      color: backgroundColor,
      child: Row(
        children: [
          // Логотип и название с градиентным текстом
          const SizedBox(width: 16),
          Image.asset('assets/icons/favicon.png', width: 16, height: 16),
          const SizedBox(width: 8),
          ShaderMask(
            shaderCallback: (bounds) {
              return const LinearGradient(
                colors: [
                  primaryColor, 
                  Color(0xFFE01E8C)
                ],
              ).createShader(bounds);
            },
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
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
            hoverColor: Colors.red.withOpacity(0.15), // Более тонкий эффект для закрытия
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
                child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              SizedBox(
                width: 40,
                height: 32,
                child: Center(
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 16,
                  ),
                ),
              ),
              StatefulBuilder(
                builder: (context, setState) {
                  bool isHovered = false;
                  return MouseRegion(
                    onEnter: (_) => setState(() => isHovered = true),
                    onExit: (_) => setState(() => isHovered = false),
                    child: GestureDetector(
                      onTap: onPressed,
                      child: Container(
                        width: 40,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isHovered ? 
                            (hoverColor ?? primaryColor).withOpacity(0.05) : 
                            Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          boxShadow: isHovered ? [
                            BoxShadow(
                              color: (hoverColor ?? primaryColor).withOpacity(0.05),
                              blurRadius: 8,
                              spreadRadius: -2,
                            ),
                          ] : [],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}