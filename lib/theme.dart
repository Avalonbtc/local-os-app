import 'package:flutter/material.dart';

/// Colours of the RigDeck console (dark, amber accent), shared with the web panel.
abstract final class C {
  static const bg = Color(0xFF111418);
  static const bar = Color(0xFF15191D);
  static const surface = Color(0xFF1B2025);
  static const surface2 = Color(0xFF20262C);
  static const field = Color(0xFF15191D);
  static const border = Color(0xFF2A3138);
  static const divider = Color(0xFF22282E);
  static const text = Color(0xFFE8EBEE);
  static const text2 = Color(0xFFC9D0D7);
  static const muted = Color(0xFF9AA4AE);
  static const faint = Color(0xFF5B646E);
  static const accent = Color(0xFFF5A524);
  static const onAccent = Color(0xFF1A1405);
  static const rate = Color(0xFFF5C26B);
  static const ok = Color(0xFF4CC38A);
  static const okText = Color(0xFF6FD6A3);
  static const okBg = Color(0xFF173326);
  static const bad = Color(0xFFF0555F);
  static const badText = Color(0xFFFF8A92);
  static const badBg = Color(0xFF3A1D21);
  static const pool = Color(0xFFFFAD5C);
  static const poolText = Color(0xFFFFB366);
  static const poolBg = Color(0xFF3A2A16);
  static const info = Color(0xFF7CC0FF);
  static const infoText = Color(0xFFA9D2FF);
  static const infoBg = Color(0xFF172633);
  static const greyBg = Color(0xFF2A2F35);
  static const chartTemp = Color(0xFFFF8A5C);
}

/// Digits that do not shift width while numbers update every few seconds.
const tabular = <FontFeature>[FontFeature.tabularFigures()];

const mono = TextStyle(fontFamily: 'monospace', fontFeatures: tabular);

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: C.accent,
    onPrimary: C.onAccent,
    secondary: C.accent,
    onSecondary: C.onAccent,
    surface: C.bg,
    onSurface: C.text,
    surfaceContainerHighest: C.surface2,
    surfaceContainerHigh: C.surface,
    surfaceContainer: C.surface,
    outline: C.border,
    outlineVariant: C.divider,
    error: C.bad,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: C.bg,
    // A plain ripple: no fragment shader to compile on the first tap.
    splashFactory: InkRipple.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    appBarTheme: const AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: C.text),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.bar,
      surfaceTintColor: Colors.transparent,
      indicatorColor: C.accent.withValues(alpha: 0.16),
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 11,
          color: s.contains(WidgetState.selected) ? C.accent : C.muted,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.accent : C.muted),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: C.accent,
      unselectedLabelColor: C.muted,
      indicatorColor: C.accent,
      dividerColor: C.divider,
      tabAlignment: TabAlignment.start,
      labelStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 14),
    ),
    dividerTheme: const DividerThemeData(color: C.divider, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.field,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      labelStyle: const TextStyle(color: C.muted),
      hintStyle: const TextStyle(color: C.faint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2F363E)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF2F363E)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: C.accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: C.onAccent,
        minimumSize: const Size(64, 46),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        backgroundColor: C.surface2,
        minimumSize: const Size(64, 44),
        side: const BorderSide(color: Color(0xFF2F363E)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.accent, minimumSize: const Size(44, 44)),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: C.accent,
      side: BorderSide(color: Color(0xFF2F363E)),
      labelStyle: TextStyle(fontSize: 13, color: C.text2),
      secondaryLabelStyle: TextStyle(fontSize: 13, color: C.onAccent, fontWeight: FontWeight.w600),
      showCheckmark: false,
      shape: StadiumBorder(),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF1A1F24),
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Color(0xFF3A424A),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.surface2,
      contentTextStyle: TextStyle(color: C.text),
      actionTextColor: C.accent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? C.onAccent : C.text2,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? C.accent : const Color(0xFF3A424A),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: C.accent),
  );
}
