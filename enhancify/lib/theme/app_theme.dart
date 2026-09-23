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

/// Surfaces and text that flip between the white theme and the dark theme.
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  static const light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F2F3),
    surfaceHigh: Color(0xFFEFE4E7),
    border: Color(0xFFE3D4D8),
    textPrimary: Color(0xFF1A1012),
    textSecondary: Color(0xFF5C454B),
    textMuted: Color(0xFF8A7378),
  );

  static const dark = AppPalette(
    brightness: Brightness.dark,
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceHigh: AppColors.surfaceHigh,
    border: AppColors.border,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textMuted: AppColors.textMuted,
  );

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
  }) =>
      AppPalette(
        brightness: brightness ?? this.brightness,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceHigh: surfaceHigh ?? this.surfaceHigh,
        border: border ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textMuted: textMuted ?? this.textMuted,
      );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) => this;
}

extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(AppPalette.light);
  static ThemeData get dark => _build(AppPalette.dark);

  static ThemeData _build(AppPalette palette) {
    final isDark = palette.brightness == Brightness.dark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: palette.brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.crimson,
        brightness: palette.brightness,
        primary: AppColors.red,
        secondary: AppColors.maroon,
        surface: palette.background,
        surfaceTint: Colors.transparent,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: palette.background,
      extensions: [palette],
      textTheme: base.textTheme.apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.background,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      iconTheme: IconThemeData(color: palette.textPrimary),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.surfaceHigh : AppColors.maroon,
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      dividerColor: palette.border,
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.surface,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(backgroundColor: palette.surface),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.red : null,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.red,
        thumbColor: isDark ? Colors.white : AppColors.maroon,
        inactiveTrackColor: palette.border,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? Colors.white
                : palette.textPrimary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.red : palette.surface,
          ),
        ),
      ),
    );
  }
}
