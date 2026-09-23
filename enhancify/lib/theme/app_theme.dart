import 'package:flutter/material.dart';

/// Red / maroon palette.
class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0E0809);
  static const Color surface = Color(0xFF1A1012);
  static const Color surfaceHigh = Color(0xFF261619);
  static const Color border = Color(0xFF3A2328);

  static const Color maroon = Color(0xFF6E0F2A);
  static const Color maroonDeep = Color(0xFF3D0715);
  static const Color crimson = Color(0xFFC8102E);
  static const Color red = Color(0xFFE8274B);
  static const Color redLight = Color(0xFFFF5A78);
  static const Color gold = Color(0xFFFFC53D);

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFB9A7AB);
  static const Color textMuted = Color(0xFF7D6A6E);
  static const Color success = Color(0xFF3DDC84);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [red, maroon],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient giftGradient = LinearGradient(
    colors: [Color(0xFFB0123A), Color(0xFF5A0A2A), Color(0xFF2A0616)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.crimson,
        brightness: Brightness.dark,
        primary: AppColors.red,
        secondary: AppColors.maroon,
        surface: AppColors.background,
        surfaceTint: Colors.transparent,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceHigh,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      dividerColor: AppColors.border,
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        showDragHandle: true,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.red : null,
        ),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.red,
        thumbColor: Colors.white,
        inactiveTrackColor: AppColors.border,
      ),
    );
  }
}
