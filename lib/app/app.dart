import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class EbkApp extends ConsumerWidget {
  const EbkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // 护眼模式在浅色/深色之上叠加暖色色板（与 themeMode 正交，可任意组合）
    final eyeCare = ref.watch(eyeCareProvider);
    return MaterialApp.router(
      title: 'ezBookkeeping',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light, eyeCare: eyeCare),
      darkTheme: buildAppTheme(Brightness.dark, eyeCare: eyeCare),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
    );
  }
}
