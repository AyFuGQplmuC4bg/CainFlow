import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the "oscilloscope instrument" aesthetic — a near-black
/// schematic surface, a single phosphor accent, hairline structure, and
/// monospace instrument readouts.
abstract final class CainTokens {
  // --- Surfaces (near-black, layered like an instrument panel) -------------
  static const void0 = Color(0xFF07090B); // deepest backdrop
  static const surface = Color(0xFF0B0E11); // canvas / scaffold
  static const panel = Color(0xFF11151A); // rails, sheets
  static const panelHigh = Color(0xFF161B21); // cards, raised
  static const panelEdge = Color(0xFF222A32); // hairline borders
  static const gridMinor = Color(0xFF141A20); // fine grid lines
  static const gridMajor = Color(0xFF1E262E); // major grid lines

  // --- Phosphor accent (single dominant color) -----------------------------
  static const phosphor = Color(0xFF00E5C7); // primary CRT-green
  static const phosphorDim = Color(0xFF1C7A6E); // low-energy variant
  static const phosphorGlow = Color(0x3300E5C7); // glow wash

  // --- Signal / status ------------------------------------------------------
  static const signalText = Color(0xFF6FD0E8); // text-type ports/lines (cyan)
  static const signalImage = Color(0xFFB69CFF); // image-type ports/lines
  static const signalControl = Color(0xFFE8B45B); // control-flow (amber)
  static const danger = Color(0xFFFF5C6C);
  static const ok = Color(0xFF3BE0A0);
  static const idle = Color(0xFF4A5560);

  // --- Ink ------------------------------------------------------------------
  static const ink = Color(0xFFE7EEF2); // primary text
  static const inkDim = Color(0xFF8A97A2); // secondary text
  static const inkFaint = Color(0xFF55626C); // tertiary / labels

  // --- Type ----------------------------------------------------------------
  /// Engineering display face (titles, labels, chip silkscreen).
  static TextStyle display(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color color = ink,
    double spacing = 0.4,
  }) {
    return GoogleFonts.chakraPetch(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: 1.15,
    );
  }

  /// Monospace instrument readout (values, ports, coords, durations).
  static TextStyle mono(
    double size, {
    FontWeight weight = FontWeight.w500,
    Color color = ink,
    double spacing = 0.2,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: spacing,
      height: 1.25,
    );
  }
}
