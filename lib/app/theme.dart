import 'package:flutter/material.dart';

/// 品牌色取自 Web Manifest 的 theme_color（#C67E48），与网页端保持一致
const kBrandColor = Color(0xFFC67E48);

ThemeData buildAppTheme(Brightness brightness) {
  final scheme =
      ColorScheme.fromSeed(seedColor: kBrandColor, brightness: brightness);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      isDense: true,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}
