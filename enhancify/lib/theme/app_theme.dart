import 'package:flutter/material.dart';

/// Pink palette built around #EA026A.
///
/// Field names are kept from the first version so every screen picks up the
/// new colors automatically:
///   red      -> primary pink (#EA026A)
///   maroon   -> deep berry (pressed states, dark accents)
///   gold     -> warm apricot accent (stars, highlights)
class AppColors {
  AppColors._();

  // Dark-mode surfaces (light mode uses AppPalette.light below).
  static const Color background = Color(0xFF14070E);
  static const Color surface = Color(0xFF221019);
  static const Color surfaceHigh = Color(0xFF301823);
  static const Color border = Color(0xFF47273A);

  static const Color primary = Color(0xFFEA026A);
  static const Color maroon = Color(0xFFA3004B); // deep berry
  static const Color maroonDeep = Color(0xFF5C0A33);
  static const Color crimson = Color(0xFFC80059);
  static const Color red = primary;
  static const Color redLight = Color(0xFFFF5C9E);
  static const Color blush = Color(0xFFFFE3EF);
  static const Color lavender = Color(0xFFB892FF); // complementary accent
  static const Color mint = Color(0xFF2EC4A6); // complementary accent
  static const Color gold = Color(0xFFFFB547); // apricot

  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFFD8B9C7);
  static const Color textMuted = Color(0xFF9C7C8B);
  static const Color success = Color(0xFF22B573);

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFFF4F97), primary, Color(0xFFB8005A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient giftGradient = LinearGradient(
    colors: [Color(0xFFFF5C9E), Color(0xFFEA026A), Color(0xFF8E0A55)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  /// Soft background wash used on light screens.
  static const LinearGradient blushGradient = LinearGradient(
    colors: [Color(0xFFFFF4F9), Color(0xFFFFE3EF)],
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
    background: Color(0xFFFFFAFC),
    surface: Color(0xFFFFF0F6),
    surfaceHigh: Color(0xFFFFE1EE),
    border: Color(0xFFF5CADC),
    textPrimary: Color(0xFF2A0A1A),
    textSecondary: Color(0xFF6B4658),
    textMuted: Color(0xFF9E7A8B),
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
        seedColor: AppColors.primary,
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
