import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 通用偏好存储。
///
/// 存的是**非敏感**项（主题模式、护眼模式），但复用 token 已经在用的
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
  static const String _eyeCareKey = 'eye_care';

  /// 新增偏好项：这里加一个键 + 一对 getter/setter 即可
  static const List<String> _keys = <String>[_themeModeKey, _eyeCareKey];

  final Map<String, String> _cache = <String, String>{};

  /// 启动时读一次，之后就能同步读
  Future<void> init() async {
    final storage = _storage;
    if (storage == null) return;
    for (final key in _keys) {
      final value = await storage.read(key: key);
      if (value != null) {
        _cache[key] = value;
      }
    }
  }

  /// 护眼模式（暖色调，默认关）
  bool get eyeCare => _cache[_eyeCareKey] == 'true';

  Future<void> setEyeCare(bool value) async {
    _cache[_eyeCareKey] = value ? 'true' : 'false';
    final storage = _storage;
    if (storage == null) return;
    await storage.write(key: _eyeCareKey, value: _cache[_eyeCareKey]!);
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
