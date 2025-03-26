import 'package:flutter/material.dart';

class AppTheme {
  // Цветовая схема приложения
  static const Color _primaryColor = Color(0xFF2196F3);        // Голубой
  static const Color _accentColor = Color(0xFF03A9F4);         // Синий
  static const Color _errorColor = Color(0xFFE57373);          // Красный
  static const Color _backgroundColor = Color(0xFF121212);     // Темно-серый
  static const Color _surfaceColor = Color(0xFF1E1E1E);        // Серый
  static const Color _textColor = Color(0xFFECEFF1);           // Светло-серый

  // Темная тема
  static final ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: const ColorScheme.dark(
      primary: _primaryColor,
      secondary: _accentColor,
      error: _errorColor,
      background: _backgroundColor,
      surface: _surfaceColor,
      onBackground: _textColor,
      onSurface: _textColor,
    ),
    scaffoldBackgroundColor: _backgroundColor,
    cardTheme: const CardTheme(
      color: _surfaceColor,
      elevation: 4,
      margin: EdgeInsets.all(8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _backgroundColor,
      elevation: 0,
      centerTitle: false,
    ),
    buttonTheme: ButtonThemeData(
      buttonColor: _primaryColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _primaryColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF323232),
      thickness: 1,
      space: 1,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: _backgroundColor,
      selectedIconTheme: const IconThemeData(
        color: _primaryColor,
        size: 24,
      ),
      unselectedIconTheme: IconThemeData(
        color: _textColor.withOpacity(0.5),
        size: 24,
      ),
      selectedLabelTextStyle: const TextStyle(
        color: _primaryColor,
        fontSize: 12,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: _textColor.withOpacity(0.5),
        fontSize: 12,
      ),
    ),
    // Настройки для диалогов и всплывающих окон
    dialogTheme: DialogTheme(
      backgroundColor: _surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );
}