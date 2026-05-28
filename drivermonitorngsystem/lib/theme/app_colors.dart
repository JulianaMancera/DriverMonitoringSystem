import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Backgrounds ──────────────────────────────────────────────────────────────
  static const Color bg          = Color(0xFF080E1A);
  static const Color surface     = Color(0xFF0D1627);
  static const Color surfaceAlt  = Color(0xFF1A2235);
  static const Color surfaceDark = Color(0xFF0F172A);
  static const Color surfaceSlate = Color(0xFF1E293B);
  static const Color navInactive = Color(0xFF3A4A5C);

  // ── Accents ───────────────────────────────────────────────────────────────────
  static const Color cyan        = Color(0xFF00D4FF);
  static const Color cyanAlt     = Color(0xFF22D3EE);
  static const Color green       = Color(0xFF00FF88);
  static const Color greenScore  = Color(0xFF10B981);
  static const Color amber       = Color(0xFFF59E0B);
  static const Color distracted  = Color(0xFFfbbf24);
  static const Color purple      = Color(0xFFA855F7);

  // ── Alerts ────────────────────────────────────────────────────────────────────
  static const Color red         = Color(0xFFFF4757);
  static const Color redAlert    = Color(0xFFEF4444);
  static const Color drowsy      = Colors.red;

  // ── Text ──────────────────────────────────────────────────────────────────────
  static const Color textPrimary    = Color(0xFFEEF2FF);
  static const Color textMuted      = Color(0xFF94A3B8);
  static const Color textDim        = Color(0xFF6B7A99);
  static const Color textFaded      = Color(0xFF64748B);
  static const Color textSlate      = Color(0xFF475569);
  static const Color textSlateLight = Color(0xFFCBD5E1);

  // ── Divider ───────────────────────────────────────────────────────────────────
  static const Color divider     = Color(0xFF1E2D45);
}
