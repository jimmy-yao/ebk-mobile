import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 通用偏好存储。
///
/// 存的是**非敏感**项（目前只有主题模式），但复用 token 已经在用的
/// `flutter_secure_storage`（Android Keystore / iOS Keychain），
/// 免得多引一个 shared_preferences。
///
/// 约定：`main()` 里在首帧前调一次 [init] 把值读进内存，
/// 之后就能**同步**读 [themeMode] —— 否则会先闪一下默认主题。
/// 写入走 [write]（先改内存再落盘）。
class PreferencesStore {
  PreferencesStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  /// 测试用：只读写内存，不碰平台通道（比传 storage 更明确）
  PreferencesStore.memory() : _storage = null;

  /// null = 只读写内存（[PreferencesStore.memory]）
  final FlutterSecureStorage? _storage;

  static const String _themeModeKey = 'theme_mode';

  final Map<String, String> _cache = <String, String>{};

  /// 启动时读一次。新键在这里加一行即可
  Future<void> init() async {
    final storage = _storage;
    if (storage == null) return;
    final value = await storage.read(key: _themeModeKey);
    if (value != null) {
      _cache[_themeModeKey] = value;
    }
  }

  /// 主题模式（默认跟随系统）
  ThemeMode get themeMode => switch (_cache[_themeModeKey]) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode mode) async {
    final value = switch (mode) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    };
    _cache[_themeModeKey] = value;
    final storage = _storage;
    if (storage == null) return;
    await storage.write(key: _themeModeKey, value: value);
  }
}

final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => PreferencesStore(),
);
