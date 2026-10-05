import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/storage/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // token 落在 Android Keystore / iOS Keychain，先读出来再进首帧，
  // 这样路由的 redirect 能拿到真实登录态（避免闪一下登录页）
  final tokenStore = TokenStore();
  await tokenStore.init();

  runApp(
    ProviderScope(
      overrides: [tokenStoreProvider.overrideWithValue(tokenStore)],
      child: const EbkApp(),
    ),
  );
}
