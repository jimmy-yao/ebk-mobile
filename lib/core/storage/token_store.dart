import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 服务端默认地址（登录页可改，Phase 1 第 1 周做持久化）
const kDefaultServerUrl = 'https://ezbook.hapi.dpdns.org';

/// 在 main() 中 override 成已初始化的实例
final tokenStoreProvider = Provider<TokenStore>(
  (ref) => throw UnimplementedError('tokenStoreProvider 必须在 main() 中 override'),
);

/// 登录态持有者：token 存 Keystore/Keychain，同时用 ValueNotifier 驱动路由跳转。
///
/// 服务端把 token 从三条通路里认（源码 pkg/core/context_web.go）：
///   Authorization: bearer / ?token= / ebk_auth_token Cookie
/// App 侧：API 走 header；图片只能走 `?token=`（见 scripts/smoke.sh Q3）。
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'ebk_session_token';

  final FlutterSecureStorage _storage;
  final ValueNotifier<String?> _token = ValueNotifier<String?>(null);

  /// GoRouter 的 refreshListenable 用它
  ValueListenable<String?> get listenable => _token;

  String? get token => _token.value;

  bool get hasToken => _token.value != null && _token.value!.isNotEmpty;

  Future<void> init() async {
    try {
      _token.value = await _storage.read(key: _key);
    } catch (_) {
      // 个别设备 Keystore 不可用时不能卡死启动
      _token.value = null;
    }
  }

  Future<void> setToken(String value) async {
    _token.value = value;
    await _storage.write(key: _key, value: value);
  }

  Future<void> clear() async {
    _token.value = null;
    await _storage.delete(key: _key);
  }
}
