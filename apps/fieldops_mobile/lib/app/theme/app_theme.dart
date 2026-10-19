import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─── Design Tokens ───────────────────────────────────────────
// Based on UI/UX Pro Max: SaaS Mobile (High-Tech Boutique)
// Brand DNA: FieldOps signal orange + slate + premium spacing

const _slate = Color(0xFF0F172A); // Deepened for premium contrast
const _canvas = Color(0xFFFAFAFA); // Clean off-white (not yellow-tinted)
const _steel = Color(0xFF64748B); // Muted steel for secondary text
const _signal = Color(0xFFF38B2A); // FieldOps orange — primary brand
const _signalDark = Color(0xFFE07B1A); // Pressed state
const _success = Color(0xFF16A34A); // Brighter, more modern green
const _danger = Color(0xFFDC2626); // Standard red-600
const _surfaceWhite = Color(0xFFFFFFFF);
const _border = Color(0xFFE2E8F0); // Slate-200
const _borderFocused = Color(0xFFF38B2A); // Signal on focus
const _muted = Color(0xFFF1F5F9); // Slate-100 for subtle backgrounds

// ─── Spacing Scale (8dp rhythm) ──────────────────────────────
class FieldOpsSpacing {
  const FieldOpsSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

// ─── Radius Scale ────────────────────────────────────────────
class FieldOpsRadius {
  const FieldOpsRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16; // Cards, buttons
  static const double xl = 20; // Inputs
  static const double xxl = 24; // Large cards
  static const double full = 999; // Pills
}

// ─── Shadow Scale (elevation system) ─────────────────────────
class FieldOpsShadow {
  const FieldOpsShadow._();

  static List<BoxShadow> get sm => [
        BoxShadow(
          color: _slate.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get md => [
        BoxShadow(
          color: _slate.withValues(alpha: 0.06),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get lg => [
        BoxShadow(
          color: _slate.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}

// ─── Theme Builder ───────────────────────────────────────────

ThemeData buildFieldOpsTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _signal,
      brightness: Brightness.light,
      primary: _signal,
      onPrimary: _surfaceWhite,
      secondary: _steel,
      surface: _surfaceWhite,
      onSurface: _slate,
      error: _danger,
    ),
    scaffoldBackgroundColor: _canvas,
    useMaterial3: true,
  );

  // Premium typography: Space Grotesk for display, IBM Plex Sans for body
  final textTheme = GoogleFonts.spaceGroteskTextTheme(base.textTheme).copyWith(
    displayLarge: GoogleFonts.spaceGrotesk(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      color: _slate,
      height: 1.05,
      letterSpacing: -1.0,
    ),
    displaySmall: GoogleFonts.spaceGrotesk(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: _slate,
      height: 1.1,
      letterSpacing: -0.5,
    ),
    headlineMedium: GoogleFonts.spaceGrotesk(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: _slate,
      letterSpacing: -0.3,
    ),
    titleLarge: GoogleFonts.spaceGrotesk(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: _slate,
    ),
    titleMedium: GoogleFonts.ibmPlexSans(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: _slate,
    ),
    bodyLarge: GoogleFonts.ibmPlexSans(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      color: _slate,
      height: 1.5,
    ),
    bodyMedium: GoogleFonts.ibmPlexSans(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      color: _steel,
      height: 1.5,
    ),
    bodySmall: GoogleFonts.ibmPlexSans(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: _steel,
      height: 1.4,
    ),
    labelLarge: GoogleFonts.ibmPlexSans(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelMedium: GoogleFonts.ibmPlexSans(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: _steel,
    ),
  );

  return base.copyWith(
    textTheme: textTheme,

    // App bar — clean, elevated
    appBarTheme: AppBarTheme(
      backgroundColor: _surfaceWhite,
      foregroundColor: _slate,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      surfaceTintColor: Colors.transparent,
    ),

    // Input fields — premium with subtle border
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceWhite,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xl),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xl),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xl),
        borderSide: const BorderSide(color: _borderFocused, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xl),
        borderSide: const BorderSide(color: _danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xl),
        borderSide: const BorderSide(color: _danger, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: FieldOpsSpacing.lg,
        vertical: FieldOpsSpacing.base,
      ),
      labelStyle: textTheme.bodyMedium,
      hintStyle: textTheme.bodyMedium?.copyWith(
        color: _steel.withValues(alpha: 0.5),
      ),
      prefixIconColor: _steel,
    ),

    // Primary button — gradient-ready, tall, rounded
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _signal,
        foregroundColor: _surfaceWhite,
        disabledBackgroundColor: _signal.withValues(alpha: 0.4),
        disabledForegroundColor: _surfaceWhite.withValues(alpha: 0.6),
        minimumSize: const Size.fromHeight(56),
        textStyle: textTheme.labelLarge?.copyWith(color: _surfaceWhite),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ),
    ),

    // Outlined button — clean secondary
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _slate,
        minimumSize: const Size.fromHeight(48),
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
        ),
        side: const BorderSide(color: _border),
      ),
    ),

    // Text button
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _signal,
        textStyle: textTheme.labelLarge,
      ),
    ),

    // Cards — subtle shadow, generous radius
    cardTheme: CardThemeData(
      color: _surfaceWhite,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        side: const BorderSide(color: _border, width: 0.5),
      ),
      surfaceTintColor: Colors.transparent,
    ),

    // Divider
    dividerTheme: const DividerThemeData(
      color: _border,
      thickness: 0.5,
      space: 0,
    ),

    // Bottom sheet
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _surfaceWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(FieldOpsRadius.xxl),
        ),
      ),
    ),

    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: _surfaceWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
      ),
    ),

    // Snackbar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _slate,
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: _surfaceWhite),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.md),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    // Extensions
    extensions: const <ThemeExtension<dynamic>>[
      FieldOpsPalette(
        canvas: _canvas,
        slate: _slate,
        steel: _steel,
        signal: _signal,
        signalDark: _signalDark,
        success: _success,
        danger: _danger,
        muted: _muted,
        border: _border,
        surfaceWhite: _surfaceWhite,
      ),
    ],
  );
}

// ─── Dark Theme ──────────────────────────────────────────────

const _darkBg = Color(0xFF0F1419);
const _darkSurface = Color(0xFF1A2028);
const _darkBorder = Color(0xFF2A3240);
const _darkTextPrimary = Color(0xFFEDEDEF);
const _darkTextSecondary = Color(0xFF8A8F98);

ThemeData buildFieldOpsDarkTheme() {
  final base = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _signal,
      brightness: Brightness.dark,
      primary: _signal,
      onPrimary: _darkBg,
      secondary: _darkTextSecondary,
      surface: _darkSurface,
      onSurface: _darkTextPrimary,
      error: _danger,
    ),
    scaffoldBackgroundColor: _darkBg,
    useMaterial3: true,
  );

  final textTheme = GoogleFonts.spaceGroteskTextTheme(base.textTheme).copyWith(
    displaySmall: GoogleFonts.spaceGrotesk(
      fontSize: 32, fontWeight: FontWeight.w700,
      color: _darkTextPrimary, height: 1.1, letterSpacing: -0.5,
    ),
    headlineMedium: GoogleFonts.spaceGrotesk(
      fontSize: 24, fontWeight: FontWeight.w700,
      color: _darkTextPrimary, letterSpacing: -0.3,
    ),
    titleLarge: GoogleFonts.spaceGrotesk(
      fontSize: 18, fontWeight: FontWeight.w600, color: _darkTextPrimary,
    ),
    bodyLarge: GoogleFonts.ibmPlexSans(
      fontSize: 16, fontWeight: FontWeight.w400,
      color: _darkTextPrimary, height: 1.5,
    ),
    bodyMedium: GoogleFonts.ibmPlexSans(
      fontSize: 14, fontWeight: FontWeight.w400,
      color: _darkTextSecondary, height: 1.5,
    ),
    labelLarge: GoogleFonts.ibmPlexSans(
      fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: 0.1,
    ),
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: _darkSurface,
      foregroundColor: _darkTextPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xl),
        borderSide: const BorderSide(color: _darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xl),
        borderSide: const BorderSide(color: _darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xl),
        borderSide: const BorderSide(color: _signal, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: FieldOpsSpacing.lg, vertical: FieldOpsSpacing.base,
      ),
      prefixIconColor: _darkTextSecondary,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _signal,
        foregroundColor: _darkBg,
        minimumSize: const Size.fromHeight(56),
        textStyle: textTheme.labelLarge,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FieldOpsRadius.lg),
        ),
        elevation: 0,
      ),
    ),
    cardTheme: CardThemeData(
      color: _darkSurface,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FieldOpsRadius.xxl),
        side: const BorderSide(color: _darkBorder, width: 0.5),
      ),
      surfaceTintColor: Colors.transparent,
    ),
    extensions: const <ThemeExtension<dynamic>>[
      FieldOpsPalette(
        canvas: _darkBg,
        slate: _darkTextPrimary,
        steel: _darkTextSecondary,
        signal: _signal,
        signalDark: _signalDark,
        success: _success,
        danger: _danger,
        muted: _darkSurface,
        border: _darkBorder,
        surfaceWhite: _darkSurface,
      ),
    ],
  );
}

// ─── Theme Extension ─────────────────────────────────────────

// ignore_for_file: avoid_extension_on_build_context
extension FieldOpsPaletteContext on BuildContext {
  /// Returns the [FieldOpsPalette] from the active theme.
  /// Falls back to [FieldOpsPalette.light()] instead of throwing,
  /// so widgets never crash due to a missing theme extension.
  FieldOpsPalette get palette =>
      Theme.of(this).extension<FieldOpsPalette>() ?? FieldOpsPalette.light();
}

class FieldOpsPalette extends ThemeExtension<FieldOpsPalette> {
  const FieldOpsPalette({
    required this.canvas,
    required this.slate,
    required this.steel,
    required this.signal,
    required this.signalDark,
    required this.success,
    required this.danger,
    required this.muted,
    required this.border,
    required this.surfaceWhite,
  });

  /// Fallback palette used when [FieldOpsPalette] is not registered in the
  /// active theme (e.g. in tests, isolated widgets, or misconfigured themes).
  /// Values mirror the light theme tokens so the UI remains usable.
  static FieldOpsPalette light() => const FieldOpsPalette(
        canvas: Color(0xFFFAFAFA),
        slate: Color(0xFF0F172A),
        steel: Color(0xFF64748B),
        signal: Color(0xFFF38B2A),
        signalDark: Color(0xFFE07B1A),
        success: Color(0xFF16A34A),
        danger: Color(0xFFDC2626),
        muted: Color(0xFFF1F5F9),
        border: Color(0xFFE2E8F0),
        surfaceWhite: Color(0xFFFFFFFF),
      );

  final Color canvas;
  final Color slate;
  final Color steel;
  final Color signal;
  final Color signalDark;
  final Color success;
  final Color danger;
  final Color muted;
  final Color border;
  final Color surfaceWhite;

  @override
  ThemeExtension<FieldOpsPalette> copyWith({
    Color? canvas,
    Color? slate,
    Color? steel,
    Color? signal,
    Color? signalDark,
    Color? success,
    Color? danger,
    Color? muted,
    Color? border,
    Color? surfaceWhite,
  }) {
    return FieldOpsPalette(
      canvas: canvas ?? this.canvas,
      slate: slate ?? this.slate,
      steel: steel ?? this.steel,
      signal: signal ?? this.signal,
      signalDark: signalDark ?? this.signalDark,
      success: success ?? this.success,
      danger: danger ?? this.danger,
      muted: muted ?? this.muted,
      border: border ?? this.border,
      surfaceWhite: surfaceWhite ?? this.surfaceWhite,
    );
  }

  @override
  ThemeExtension<FieldOpsPalette> lerp(
    covariant ThemeExtension<FieldOpsPalette>? other,
    double t,
  ) {
    if (other is! FieldOpsPalette) return this;
    return FieldOpsPalette(
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      slate: Color.lerp(slate, other.slate, t) ?? slate,
      steel: Color.lerp(steel, other.steel, t) ?? steel,
      signal: Color.lerp(signal, other.signal, t) ?? signal,
      signalDark: Color.lerp(signalDark, other.signalDark, t) ?? signalDark,
      success: Color.lerp(success, other.success, t) ?? success,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      muted: Color.lerp(muted, other.muted, t) ?? muted,
      border: Color.lerp(border, other.border, t) ?? border,
      surfaceWhite:
          Color.lerp(surfaceWhite, other.surfaceWhite, t) ?? surfaceWhite,
    );
  }
}
