import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Couleurs de WouStore (mêmes valeurs que la maquette).
class W {
  static const bg = Color(0xFF0A0C10);
  static const surface = Color(0xFF14181F);
  static const surface2 = Color(0xFF1A1F29);
  static const line = Color(0xFF1C222B);
  static const border = Color(0xFF262D38);
  static const text = Color(0xFFF2F4F7);
  static const soft = Color(0xFFC9D1DC);
  static const muted = Color(0xFF9AA4B2);
  static const accent = Color(0xFF3DDC97);
  static const onAccent = Color(0xFF062016);
  static const red = Color(0xFFFF6B6B);
  static const orange = Color(0xFFFFB454);

  static TextStyle title(double size) => GoogleFonts.spaceGrotesk(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: text,
        letterSpacing: -0.5,
      );

  static TextStyle body(double size,
          {Color color = text, FontWeight weight = FontWeight.w400}) =>
      GoogleFonts.inter(fontSize: size, color: color, fontWeight: weight);
}

ThemeData buildTheme() {
  final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: W.bg,
    colorScheme: const ColorScheme.dark(
      primary: W.accent,
      onPrimary: W.onAccent,
      surface: W.bg,
      onSurface: W.text,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme),
    splashFactory: InkSparkle.splashFactory,
  );
}

String formatSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '—';
  final mo = bytes / (1024 * 1024);
  return '${mo.toStringAsFixed(mo >= 10 ? 1 : 2).replaceAll('.', ',')} Mo';
}
