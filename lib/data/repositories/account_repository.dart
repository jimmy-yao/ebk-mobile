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

/// 分类树（自动 dispose，保存后可 invalidate 刷新）
final categoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).list(),
);

/// 可见标签
final tagsProvider = FutureProvider.autoDispose<List<Tag>>(
  (ref) => ref.watch(categoryRepositoryProvider).listTags(),
);

class CategoryRepository {
  CategoryRepository(this._api);

  final ApiClient _api;

  /// `GET /api/v1/transaction/categories/list.json`
  ///
  /// **返回的是按分类 type 分组的 map**（`{"1":[收入],"2":[支出],"3":[转账]}`，
  /// 源码 `TransactionCategoriesResponse`），不是数组 —— 直接 `as List` 会崩。
  /// 这里把各组拍平；每条自带 `type` 字段，调用方再按需过滤。
  Future<List<Category>> list() async {
    final result = await _api.get('/api/v1/transaction/categories/list.json');

    final out = <Category>[];
    if (result is Map<String, dynamic>) {
      for (final value in result.values) {
        if (value is! List) continue;
        out.addAll(
          value.whereType<Map<String, dynamic>>().map(Category.fromJson),
        );
      }
    } else if (result is List) {
      // 兼容某些版本/参数下的平铺返回
      out.addAll(
        result.whereType<Map<String, dynamic>>().map(Category.fromJson),
      );
    }
    return out;
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
