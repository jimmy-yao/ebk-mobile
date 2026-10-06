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

/// 护眼模式：在浅色/深色之上**叠加**暖色底与暖字（降低蓝光成分）。
///
/// 与 [themeModeProvider] 正交 —— 「跟随系统 + 护眼」「深色 + 护眼」都成立。
/// 同样先改内存再落盘。
final eyeCareProvider = StateProvider<bool>(
  (ref) => ref.watch(preferencesStoreProvider).eyeCare,
);

/// 护眼色板：只覆盖「面 / 字 / 描边」三层，**业务色一律不动** ——
/// 品牌主色（本就是暖色 #C67E48）、收支红绿、统计图配色都保持原样，
/// 否则"护眼"会把金额语义也一起改掉。
ColorScheme _eyeCare(ColorScheme base, Brightness brightness) {
  if (brightness == Brightness.light) {
    // 暖纸底：R>G>B，把蓝光通道压下去
    return base.copyWith(
      surface: const Color(0xFFFCF7EC), // 主底（scaffold）
      surfaceContainerLow: const Color(0xFFF5EDDC), // 卡片
      surfaceContainer: const Color(0xFFEFE5D0),
      surfaceContainerHigh: const Color(0xFFE9DEC7),
      surfaceContainerHighest: const Color(0xFFE3D7BE),
      onSurface: const Color(0xFF3B3226), // 正文
      onSurfaceVariant: const Color(0xFF6C6252), // 次要文字/副标题
      outline: const Color(0xFF9C907C), // 分隔线
      outlineVariant: const Color(0xFFCCC2AE),
    );
  }
  // 暖黑底：比常规深色更"褐"，字偏米色而不是冷白
  return base.copyWith(
    surface: const Color(0xFF201B14),
    surfaceContainerLow: const Color(0xFF272118),
    surfaceContainer: const Color(0xFF2D271E),
    surfaceContainerHigh: const Color(0xFF332C23),
    surfaceContainerHighest: const Color(0xFF3A3329),
    onSurface: const Color(0xFFEBE1CE),
    onSurfaceVariant: const Color(0xFFB9AE9A),
    outline: const Color(0xFF8D8371),
    outlineVariant: const Color(0xFF4C4538),
  );
}

/// [eyeCare] 为 true 时套用暖色护眼色板。
ThemeData buildAppTheme(Brightness brightness, {bool eyeCare = false}) {
  var scheme =
      ColorScheme.fromSeed(seedColor: kBrandColor, brightness: brightness);
  if (eyeCare) scheme = _eyeCare(scheme, brightness);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 护眼时底色必须跟 surface 一起换，否则会出现"暖卡片 + 冷背景"
    scaffoldBackgroundColor: eyeCare ? scheme.surface : null,
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
