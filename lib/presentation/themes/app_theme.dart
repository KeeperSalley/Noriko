import 'package:flutter/material.dart';

class AppTheme {
  // Цветовая схема приложения
  static const Color _primaryColor = Color(0xFFC60E7A);     // Основной розово-малиновый цвет
  static const Color _accentColor = Color(0xFFE01E8C);      // Более светлый оттенок основного цвета
  static const Color _errorColor = Color(0xFFE57373);       // Красный (оставляем)
  static const Color _backgroundColor = Color(0xFF1C091C);  // Темно-фиолетовый фон
  static const Color _surfaceColor = Color(0xFF2A102A);     // Чуть светлее фонового для карточек
  static const Color _textColor = Color(0xFFECEFF1);        // Светло-серый текст
  
  // Дополнительные цвета для UI элементов с более тонкими эффектами hover
  static const Color _cardHoverColor = Color(0xFF2D132D);   // Более тонкий эффект для карточек
  static const Color _dividerColor = Color(0xFF3D1E3D);     // Цвет разделителей
  static const Color _buttonHoverColor = Color(0xFFCF2085); // Более мягкий эффект для кнопки при наведении

  // Темная тема с новыми цветами и тонкими эффектами hover
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
      color: _dividerColor,
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
    // Темы для дополнительных компонентов
    switchTheme: SwitchThemeData(
      thumbColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return _primaryColor;
        }
        return Colors.grey;
      }),
      trackColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return _primaryColor.withOpacity(0.3); // Более тонкий эффект
        }
        return Colors.grey.withOpacity(0.3); // Более тонкий эффект
      }),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: MaterialStateProperty.resolveWith<Color>((Set<MaterialState> states) {
        if (states.contains(MaterialState.selected)) {
          return _primaryColor;
        }
        return Colors.transparent;
      }),
      checkColor: MaterialStateProperty.all(Colors.white),
    ),
    // Добавляем более тонкие hover-эффекты
    hoverColor: _buttonHoverColor.withOpacity(0.05), // Еще более тонкий эффект для размытия
    splashColor: Colors.transparent, // Убираем стандартный эффект при нажатии
    highlightColor: Colors.transparent, // Убираем стандартный эффект выделения
    hintColor: _textColor.withOpacity(0.5), // Для подсказок
  );
}