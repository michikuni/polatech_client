import 'package:flutter/material.dart';

/// A restrained, modern palette — deep slate-navy on a soft neutral canvas.
/// "Sang trọng, không màu mè": colour is used sparingly, mostly as quiet accents.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF1F2A44); // deep slate navy
  static const Color canvas = Color(0xFFF3F4F6); // soft neutral background
  static const Color surface = Colors.white;
  static const Color line = Color(0xFFE5E7EB); // hairline borders
  static const Color textPrimary = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  /// Quiet status accents (used at low saturation only).
  static const Color checkIn = Color(0xFF2F6F5E); // muted teal-green
  static const Color checkOut = Color(0xFFB07A3C); // muted bronze
}

/// Shared design tokens so cards/rows look consistent across screens.
const double kRadius = 18;
const EdgeInsets kScreenPadding = EdgeInsets.all(20);

BoxDecoration cardDecoration() => BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(kRadius),
      border: Border.all(color: AppColors.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F111827),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    );

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    surface: AppColors.surface,
    primary: AppColors.primary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: AppColors.primary.withValues(alpha: 0.10),
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.textMuted,
        ),
      ),
    ),
  );
}
