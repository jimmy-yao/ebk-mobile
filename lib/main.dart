import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/storage/preferences_store.dart';
import 'core/storage/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // token 落在 Android Keystore / iOS Keychain，先读出来再进首帧，
  // 这样路由的 redirect 能拿到真实登录态（避免闪一下登录页）
  final tokenStore = TokenStore();
  await tokenStore.init();

  // 主题偏好同理：首帧前同步读好，否则会先闪一下默认主题
  final preferences = PreferencesStore();
  await preferences.init();

  runApp(
    ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokenStore),
        preferencesStoreProvider.overrideWithValue(preferences),
      ],
      child: const EbkApp(),
    ),
  );
}
