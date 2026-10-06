import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/preferences_store.dart';

/// 品牌色取自 Web Manifest 的 theme_color（#C67E48），与网页端保持一致
const kBrandColor = Color(0xFFC67E48);

/// 当前主题模式（跟随系统 / 浅色 / 深色）。
///
/// 初值来自 [PreferencesStore]（main() 里已同步读好），改它要同时落盘，
/// 所以设置页统一走 `PreferencesStore.setThemeMode()` 再改这个 provider。
final themeModeProvider = StateProvider<ThemeMode>(
  (ref) => ref.watch(preferencesStoreProvider).themeMode,
);

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
