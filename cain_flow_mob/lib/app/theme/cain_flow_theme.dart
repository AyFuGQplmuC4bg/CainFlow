import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'cain_tokens.dart';

/// Builds the "oscilloscope instrument" theme: near-black layered surfaces,
/// a single phosphor accent, hairline borders, sharp 4px corners, and a
/// JetBrains Mono base with Chakra Petch display headings.
ThemeData buildCainFlowTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: CainTokens.phosphor,
    brightness: Brightness.dark,
    surface: CainTokens.panel,
    primary: CainTokens.phosphor,
    onPrimary: const Color(0xFF04110E),
    secondary: CainTokens.signalImage,
    error: CainTokens.danger,
    surfaceContainerHighest: CainTokens.panelHigh,
    outlineVariant: CainTokens.panelEdge,
    onSurface: CainTokens.ink,
    onSurfaceVariant: CainTokens.inkDim,
  );

  final baseText = GoogleFonts.jetBrainsMonoTextTheme(
    ThemeData(brightness: Brightness.dark).textTheme,
  ).apply(bodyColor: CainTokens.ink, displayColor: CainTokens.ink);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: CainTokens.surface,
    textTheme: baseText.copyWith(
      titleLarge: CainTokens.display(20, weight: FontWeight.w700, spacing: 0.6),
      titleMedium: CainTokens.display(15, weight: FontWeight.w600),
      titleSmall: CainTokens.display(13, weight: FontWeight.w600),
      labelLarge: CainTokens.display(13, weight: FontWeight.w600, spacing: 0.8),
      bodyMedium: CainTokens.mono(13, color: CainTokens.ink),
      bodySmall: CainTokens.mono(11.5, color: CainTokens.inkDim),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: CainTokens.panel,
      foregroundColor: CainTokens.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: CainTokens.display(17, weight: FontWeight.w700, spacing: 1.2),
    ),
    dividerTheme: const DividerThemeData(
      color: CainTokens.panelEdge,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CainTokens.phosphor,
        foregroundColor: const Color(0xFF04110E),
        textStyle: CainTokens.display(13, weight: FontWeight.w700, spacing: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: CainTokens.phosphor,
        textStyle: CainTokens.display(13, weight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: CainTokens.ink,
        side: const BorderSide(color: CainTokens.panelEdge),
        textStyle: CainTokens.display(13, weight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: CainTokens.inkDim,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: CainTokens.void0,
      isDense: true,
      labelStyle: CainTokens.mono(12, color: CainTokens.inkDim),
      hintStyle: CainTokens.mono(12, color: CainTokens.inkFaint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: CainTokens.panelEdge),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: CainTokens.panelEdge),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: CainTokens.phosphor, width: 1.5),
      ),
    ),
    cardTheme: CardThemeData(
      color: CainTokens.panelHigh,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: CainTokens.panelEdge),
      ),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: CainTokens.phosphor,
      inactiveTrackColor: CainTokens.panelEdge,
      thumbColor: CainTokens.phosphor,
      overlayColor: CainTokens.phosphorGlow,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: CainTokens.panelHigh,
      contentTextStyle: CainTokens.mono(12.5, color: CainTokens.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: CainTokens.inkDim,
      textColor: CainTokens.ink,
    ),
  );
}
