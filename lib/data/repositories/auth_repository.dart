import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/token_store.dart';
import '../dto/auth_dto.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(tokenStoreProvider),
  ),
);

class AuthRepository {
  AuthRepository(this._api, this._tokenStore);

  final ApiClient _api;
  final TokenStore _tokenStore;

  /// 登录。返回结果里若 needTwoFactor=true，token 是待二次校验的临时 token。
  Future<LoginResult> login(String username, String password) async {
    final result = await _api.post(
      '/api/authorize.json',
      body: {'username': username, 'password': password},
    );
    return LoginResult.fromJson(result as Map<String, dynamic>);
  }

  /// 2FA 二次校验。[requireTwoFactorToken] 是上一步返回的临时 token，
  /// 接口按 `JWTTwoFactorAuthorization` 只认 header（源码 pkg/middlewares）。
  Future<String> verifyTwoFactor(String requireTwoFactorToken, String passcode) async {
    final result = await _api.post(
      '/api/2fa/authorize.json',
      body: {'passcode': passcode},
      headers: {'Authorization': 'Bearer $requireTwoFactorToken'},
    );
    return (result as Map<String, dynamic>)['token']?.toString() ?? '';
  }

  /// 保存会话 token（Android Keystore / iOS Keychain）
  Future<void> saveSession(String token) => _tokenStore.setToken(token);

  /// 注销：服务端删 token + 清本地
  Future<void> logout() async {
    try {
      await _api.get('/api/logout.json');
    } catch (_) {
      // 服务端注销失败也要清本地，避免卡在登录态
    }
    await _tokenStore.clear();
  }
}
