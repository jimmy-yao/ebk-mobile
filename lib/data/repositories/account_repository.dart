import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../dto/account_dto.dart';
import '../dto/misc_dto.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(apiClientProvider)),
);

class AccountRepository {
  AccountRepository(this._api);

  final ApiClient _api;

  /// `GET /api/v1/accounts/list.json` → AccountInfoResponse[]
  Future<List<Account>> list({bool withHidden = true}) async {
    final result = await _api.get(
      '/api/v1/accounts/list.json',
      query: {'with_hidden': withHidden},
    );
    return (result as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(Account.fromJson)
        .toList();
  }
}

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(apiClientProvider)),
);

class CategoryRepository {
  CategoryRepository(this._api);

  final ApiClient _api;

  /// `GET /api/v1/transaction/categories/list.json` → 分类树（含 children）
  Future<List<Category>> list() async {
    final result = await _api.get('/api/v1/transaction/categories/list.json');
    return (result as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(Category.fromJson)
        .toList();
  }

  /// `GET /api/v1/transaction/tags/list.json`
  Future<List<Tag>> listTags() async {
    final result = await _api.get('/api/v1/transaction/tags/list.json');
    return (result as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(Tag.fromJson)
        .toList();
  }
}
