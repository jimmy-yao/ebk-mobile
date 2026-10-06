/// 设置页外观（跟随系统 / 浅色 / 深色）与主题数据的测试。
///
/// 关键契约：切主题要**立即生效**（内存中的 provider）且**落盘**
/// （下次启动从 PreferencesStore 读回），两件事都断言。
library;

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
  test('主题偏好：默认跟随系统；写入后新实例能读回（等价重启）', () async {
    // 必须给可变 map：TestFlutterSecureStoragePlatform.write 直接改这张表
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    final fresh = PreferencesStore();
    await fresh.init();
    expect(fresh.themeMode, ThemeMode.system, reason: '没写过 → 默认跟随系统');

    await fresh.setThemeMode(ThemeMode.dark);
    final restarted = PreferencesStore();
    await restarted.init();
    expect(restarted.themeMode, ThemeMode.dark, reason: '落盘的值要能读回来');

    // 服务端/用户已有历史值的情况
    FlutterSecureStorage.setMockInitialValues(<String, String>{'theme_mode': 'light'});
    final existing = PreferencesStore();
    await existing.init();
    expect(existing.themeMode, ThemeMode.light);
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
  });
}
