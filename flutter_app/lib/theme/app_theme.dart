import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Brand colors
  static const Color primary = Color(0xFF1A73E8);
  static const Color primaryDark = Color(0xFF0D47A1);
  static const Color accent = Color(0xFF00C853);
  static const Color warning = Color(0xFFFFB300);
  static const Color error = Color(0xFFE53935);
  static const Color surface = Color(0xFFF8F9FE);
  static const Color cardBg = Colors.white;

  // Status colors
  static const Color statusPresent = Color(0xFF00C853);
  static const Color statusLate = Color(0xFFFFB300);
  static const Color statusAbsent = Color(0xFFE53935);
  static const Color statusIncomplete = Color(0xFF7B61FF);
  static const Color statusCompleted = Color(0xFF1A73E8);
  static const Color statusManual = Color(0xFF9E9E9E);
  static const Color statusApprovedAbsence = Color(0xFF5C6BC0);

  static Color statusColor(String status) {
    switch (status) {
      case 'present': return statusPresent;
      case 'late': return statusLate;
      case 'absent': return statusAbsent;
      case 'incomplete': return statusIncomplete;
      case 'completed': return statusCompleted;
      case 'manual': return statusManual;
      case 'approved_absence': return statusApprovedAbsence;
      default: return statusAbsent;
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'present': return 'Присутствует';
      case 'late': return 'Опоздание';
      case 'absent': return 'Отсутствует';
      case 'incomplete': return 'Неполный день';
      case 'completed': return 'День завершён';
      case 'manual': return 'Скорректировано';
      case 'approved_absence': return 'Разрешённое отсутствие';
      default: return 'Неизвестно';
    }
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: surface,
      textTheme: GoogleFonts.nunitoTextTheme().copyWith(
        displayLarge: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 32, color: const Color(0xFF1A1A2E)),
        headlineMedium: GoogleFonts.nunito(fontWeight: FontWeight.w700, fontSize: 24, color: const Color(0xFF1A1A2E)),
        titleLarge: GoogleFonts.nunito(fontWeight: FontWeight.w600, fontSize: 18, color: const Color(0xFF1A1A2E)),
        bodyLarge: GoogleFonts.nunito(fontSize: 16, color: const Color(0xFF333355)),
        bodyMedium: GoogleFonts.nunito(fontSize: 14, color: const Color(0xFF666688)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.nunito(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: const Color(0xFF1A1A2E),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w700, fontSize: 16),
          elevation: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFEEEEF5), width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0F2F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        labelStyle: GoogleFonts.nunito(color: const Color(0xFF888899)),
      ),
    );
  }
}
