/// `GET /api/v1/users/profile/get.json` 的 `models.UserProfileResponse`。
///
/// 响应是**扁平**的（没有再包一层 `user`），线上实测关键字段：
/// `{"username":"admin","language":"zh-CN","defaultCurrency":"CNY",
///   "defaultAccountId":"...","avatar":""}`。
///
/// 统计页要用 `defaultCurrency` 决定"换算成什么币种再汇总"
/// （对齐 web `userStore.currentUserDefaultCurrency`）。
class UserProfile {
  const UserProfile({
    required this.username,
    required this.nickname,
    required this.language,
    required this.defaultCurrency,
    required this.defaultAccountId,
  });

  final String username;
  final String nickname;
  final String language;

  /// 3 位币种大写码，如 `CNY`
  final String defaultCurrency;
  final String defaultAccountId;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        username: json['username']?.toString() ?? '',
        nickname: json['nickname']?.toString() ?? '',
        language: json['language']?.toString() ?? '',
        defaultCurrency: json['defaultCurrency']?.toString() ?? '',
        defaultAccountId: json['defaultAccountId']?.toString() ?? '',
      );
}
