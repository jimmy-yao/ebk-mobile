/// 登录相关 DTO。
///
/// `POST /api/authorize.json` 成功响应（源码 models.AuthResponse）：
/// ```json
/// { "success": true, "result": {
///     "token": "...", "need2FA": false, "user": {...},
///     "applicationCloudSettings": [...], "notificationContent": {...}
/// } }
/// ```
/// 若 `need2FA=true`，此时的 token 是 REQUIRE_2FA 类型，
/// 需带着它调 `POST /api/2fa/authorize.json`（body 只有 `passcode`，token 走 header）。
class LoginResult {
  const LoginResult._({required this.token, required this.needTwoFactor});

  final String token;
  final bool needTwoFactor;

  factory LoginResult.fromJson(Map<String, dynamic> json) => LoginResult._(
        token: json['token']?.toString() ?? '',
        needTwoFactor: json['need2FA'] == true,
      );
}

/// `result.user` 的子集（源码 models.UserResponse）
class CurrentUser {
  const CurrentUser({
    required this.uid,
    required this.username,
    required this.nickname,
    required this.language,
    required this.defaultCurrency,
    required this.twoFactorEnabled,
  });

  final String uid;
  final String username;
  final String nickname;
  final String language;
  final String defaultCurrency;
  final bool twoFactorEnabled;

  factory CurrentUser.fromJson(Map<String, dynamic> json) => CurrentUser(
        uid: json['uid']?.toString() ?? '',
        username: json['username']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? '',
        language: json['language']?.toString() ?? 'zh-Hans',
        defaultCurrency: json['defaultCurrency']?.toString() ?? 'CNY',
        twoFactorEnabled: json['twoFactorEnabled'] == true,
      );
}
