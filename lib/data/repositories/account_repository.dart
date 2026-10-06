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
  ///
  /// 过滤参数是 **`visible_only`**（`models.AccountListRequest`），不是
  /// `with_hidden`；传未知参数服务端直接忽略（等价于返回全部）。
  Future<List<Account>> list({bool withHidden = true}) async {
    final result = await _api.get(
      '/api/v1/accounts/list.json',
      query: {'visible_only': withHidden ? 'false' : 'true'},
    );
    return (result as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(Account.fromJson)
        .toList();
  }

  /// `GET /api/v1/accounts/get.json?id=`
  Future<Account?> get(String id) async {
    final result =
        await _api.get('/api/v1/accounts/get.json', query: {'id': id});
    if (result is! Map<String, dynamic>) return null;
    return Account.fromJson(result);
  }

  /// 新建账户。`POST /api/v1/accounts/add.json`
  ///
  /// 实测/源码约束（`models.AccountCreateRequest` + `api/accounts.go`）：
  /// * `icon` 是**字符串化 int64**（`"1"`），`color` 6 位**不带 #**
  /// * **初始余额非 0 时必须带 `balanceTime`**，否则 `204015
  ///   account balance time is not set`
  /// * `type` 只支持 1（单账户）—— 带子账户的父账户不能设余额
  Future<void> add({
    required String name,
    required int category,
    required int icon,
    required int iconType,
    required String color,
    required String currency,
    int balance = 0,
    String comment = '',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await _api.post(
      '/api/v1/accounts/add.json',
      body: {
        'name': name,
        'category': category,
        'type': 1, // ACCOUNT_TYPE_SINGLE_ACCOUNT
        'icon': '$icon',
        'iconType': iconType,
        'color': color,
        'currency': currency,
        if (balance != 0) ...{
          'balance': '$balance',
          'balanceTime': now,
        },
        'comment': comment,
      },
    );
  }

  /// 修改账户。`POST /api/v1/accounts/modify.json`
  ///
  /// **绝对不能带 `balance` / `balanceTime`** —— 服务端只要看到这两个键就报
  /// `204021 not supported to modify account balance`（余额由明细流水推算，
  /// 只能改"初始余额"以外的展示字段）。
  Future<void> modify({
    required String id,
    required String name,
    required int category,
    required int icon,
    required int iconType,
    required String color,
    required String currency,
    String comment = '',
    bool hidden = false,
  }) async {
    await _api.post(
      '/api/v1/accounts/modify.json',
      body: {
        'id': id,
        'name': name,
        'category': category,
        'icon': '$icon',
        'iconType': iconType,
        'color': color,
        'currency': currency,
        'comment': comment,
        'hidden': hidden,
      },
    );
  }

  /// 隐藏/取消隐藏。`POST /api/v1/accounts/hide.json` → `{id, hidden}`
  Future<void> hide(String id, bool hidden) async {
    await _api.post(
      '/api/v1/accounts/hide.json',
      body: {'id': id, 'hidden': hidden},
    );
  }

  /// 删除账户。`POST /api/v1/accounts/delete.json` → 有流水时
  /// `400 account is in use and cannot be deleted`
  Future<void> remove(String id) async {
    await _api.post('/api/v1/accounts/delete.json', body: {'id': id});
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
