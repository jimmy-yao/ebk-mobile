import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../dto/user_dto.dart';

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(apiClientProvider)),
);

/// 当前用户资料（自动 dispose；改完资料后 invalidate 即可刷新）
final userProfileProvider = FutureProvider.autoDispose<UserProfile>(
  (ref) => ref.watch(userRepositoryProvider).profile(),
);

class UserRepository {
  UserRepository(this._api);

  final ApiClient _api;

  /// `GET /api/v1/users/profile/get.json`
  ///
  /// 源码 `api.UsersApi.UserProfileHandler` → `models.UserProfileResponse`
  /// （`user.ToUserProfileResponse(GetUserBasicInfo(user))`，字段全摊平）。
  /// 这里只取 MVP 需要的子集。
  Future<UserProfile> profile() async {
    final result = await _api.get('/api/v1/users/profile/get.json');
    if (result is! Map<String, dynamic>) {
      return const UserProfile(
        username: '',
        nickname: '',
        language: '',
        defaultCurrency: '',
        defaultAccountId: '',
      );
    }
    return UserProfile.fromJson(result);
  }
}
