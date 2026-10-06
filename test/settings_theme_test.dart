/// 设置页外观（跟随系统 / 浅色 / 深色）、护眼模式与主题数据的测试。
///
/// 关键契约：切主题/护眼要**立即生效**（内存中的 provider）且**落盘**
/// （下次启动从 PreferencesStore 读回），两件事都断言。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebk_mobile/app/theme.dart';
import 'package:ebk_mobile/core/network/api_client.dart';
import 'package:ebk_mobile/core/storage/preferences_store.dart';
import 'package:ebk_mobile/core/storage/token_store.dart';
import 'package:ebk_mobile/features/settings/settings_screen.dart';

import 'fakes.dart';

FakeHttpAdapter _adapter() => FakeHttpAdapter((path, body) {
      if (path.endsWith('/systems/version.json')) {
        return ok({'version': '2.0.1', 'latestVersion': '2.0.1'});
      }
      return ok(null);
    });

ProviderContainer _container(FakeHttpAdapter adapter, PreferencesStore prefs) {
  final client = ApiClient(
    baseUrl: 'https://fake.test',
    tokenStore: TokenStore(),
  );
  client.dio.httpClientAdapter = adapter;

  return ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      tokenStoreProvider.overrideWithValue(TokenStore()),
      preferencesStoreProvider.overrideWithValue(prefs),
    ],
  );
}

void main() {
  /// WCAG 相对亮度与对比度（护眼色板必须满足正文 4.5:1）
  double luminance(Color c) {
    double ch(double s) => s <= 0.03928
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();

    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  test('主题偏好：默认跟随系统；写入后新实例能读回（等价重启）', () async {
    // 必须给可变 map：TestFlutterSecureStoragePlatform.write 直接改这张表
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final fresh = PreferencesStore();
    await fresh.init();
    expect(fresh.themeMode, ThemeMode.system, reason: '没写过 → 默认跟随系统');
    expect(fresh.eyeCare, isFalse, reason: '护眼默认关');

    await fresh.setThemeMode(ThemeMode.dark);
    final restarted = PreferencesStore();
    await restarted.init();
    expect(restarted.themeMode, ThemeMode.dark, reason: '落盘的值要能读回来');
    expect(restarted.eyeCare, isFalse);

    await fresh.setEyeCare(true);
    final restarted2 = PreferencesStore();
    await restarted2.init();
    expect(restarted2.eyeCare, isTrue, reason: '护眼开关也要能读回来');

    // 服务端/用户已有历史值的情况
    FlutterSecureStorage.setMockInitialValues(
        <String, String>{'theme_mode': 'light', 'eye_care': 'true'});
    final existing = PreferencesStore();
    await existing.init();
    expect(existing.themeMode, ThemeMode.light);
    expect(existing.eyeCare, isTrue);
  });

  test('主题数据：两套 ColorScheme 的亮度各自正确', () {
    final light = buildAppTheme(Brightness.light);
    final dark = buildAppTheme(Brightness.dark);

    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.surface.computeLuminance(), greaterThan(0.5));
    expect(dark.colorScheme.surface.computeLuminance(), lessThan(0.5));
    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
  });

  test('护眼主题：暖底（R>G>B）+ 对比度 ≥ 4.5:1，且只改面/字不改业务色', () {
    for (final brightness in Brightness.values) {
      final normal = buildAppTheme(brightness);
      final eye = buildAppTheme(brightness, eyeCare: true);
      final bg = eye.scaffoldBackgroundColor;

      expect(bg.r > bg.g && bg.g > bg.b, isTrue,
          reason: '$brightness 护眼底色必须偏暖（压蓝光通道）');
      expect(bg, isNot(normal.scaffoldBackgroundColor),
          reason: '$brightness 底色要真的换掉');
      expect(eye.colorScheme.surface, isNot(normal.colorScheme.surface));

      expect(contrast(eye.colorScheme.onSurface, bg), greaterThanOrEqualTo(4.5),
          reason: '$brightness 正文可读性');
      expect(
        contrast(eye.colorScheme.onSurfaceVariant, bg),
        greaterThanOrEqualTo(4.5),
        reason: '$brightness 副标题/次要文字可读性',
      );

      // 护眼只覆盖「面 / 字 / 描边」：主色、错误色等业务色必须原样，
      // 否则收支红绿与统计图配色会跟着变（金额语义不能被护眼改掉）
      expect(eye.colorScheme.primary, normal.colorScheme.primary);
      expect(eye.colorScheme.error, normal.colorScheme.error);
      expect(eye.colorScheme.tertiary, normal.colorScheme.tertiary);
    }
  });

  testWidgets('外观切换：立即生效并写入偏好；数据区有汇率入口', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prefs = PreferencesStore.memory();
    final container = _container(_adapter(), prefs);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(find.widgetWithText(ListTile, '汇率'), findsOneWidget,
        reason: '设置 → 数据 → 汇率入口');

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.dark,
        reason: '切完立刻生效，不用重启');
    expect(prefs.themeMode, ThemeMode.dark, reason: '同时写进偏好存储');
    expect(container.read(preferencesStoreProvider).themeMode, ThemeMode.dark);

    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();

    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(prefs.themeMode, ThemeMode.system);

    // 护眼开关：默认关，切一下立即生效并落盘，再切回去
    expect(container.read(eyeCareProvider), isFalse,
        reason: '护眼默认关闭');
    expect(find.text('护眼模式'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(container.read(eyeCareProvider), isTrue);
    expect(prefs.eyeCare, isTrue, reason: '护眼也要写进偏好存储');

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(container.read(eyeCareProvider), isFalse);
    expect(prefs.eyeCare, isFalse);
  });
}
