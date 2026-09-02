import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  final bool isDark;
  final AppColors c;
  AppTheme(this.isDark) : c = isDark ? AppColors.dark : AppColors.light;

  TextStyle get display => GoogleFonts.fraunces(color: c.ink, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500);
  TextStyle get label => GoogleFonts.inter(color: c.ink);
  TextStyle get mono => GoogleFonts.spaceMono(color: c.ink);

  ThemeData get themeData {
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    return base.copyWith(
      scaffoldBackgroundColor: c.bgDeep,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: c.accent, secondary: c.accent, surface: c.bgRise, error: c.alarm,
      ),
      textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: c.ink, displayColor: c.ink),
      dividerColor: c.line,
      iconTheme: IconThemeData(color: c.inkFaint),
      hoverColor: c.fillHover,
      splashColor: c.fillActive,
      highlightColor: c.fillHover,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          overlayColor: isDark ? Colors.black.withValues(alpha: .18) : Colors.black.withValues(alpha: .10),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(overlayColor: c.fillHover),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(overlayColor: c.fillHover),
      ),
    );
  }
}
