import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../dto/misc_dto.dart';

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(ref.watch(apiClientProvider)),
);

/// 分类树（自动 dispose，保存后可 invalidate 刷新）
final categoriesProvider = FutureProvider.autoDispose<List<Category>>(
  (ref) => ref.watch(categoryRepositoryProvider).list(),
);

/// 标签列表
final tagsProvider = FutureProvider.autoDispose<List<Tag>>(
  (ref) => ref.watch(categoryRepositoryProvider).listTags(),
);

/// 分类（TransactionCategory）与标签（TransactionTag）的读写。
///
/// 契约要点（源码 `pkg/models/transaction_category.go`、`transaction_tag.go` +
/// `scripts/smoke.sh` 实测）：
/// * 分类**只有两级**：子分类下面不能再挂分类（`206004
///   cannot add to secondary transaction category`）
/// * `modify` 请求**没有 `type` 字段** —— 类型建好就不能改；
///   且不允许一级↔二级互转（`206007`/`206008`），所以编辑时
///   `parentId` 必须原样回传
/// * `icon`/`parentId`/`id` 都是**字符串化 int64**（`json:",string"`），
///   发数字会 400
/// * **删除一级分类会连子分类一起软删**，只要有任何一条流水/模板用到
///   （含子级）就报 `206006 transaction category is in use and cannot be deleted`
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

  /// 新建分类。`POST /api/v1/transaction/categories/add.json`
  ///
  /// * `type` 1=收入 2=支出 3=转账（建了就不能改）
  /// * `parentId` 一级填 `"0"`，二级填一级分类的 id；**不能三级**
  /// * `icon` 必须 ≥1（`binding:"min=1"`），`iconType:0` 是预置图标
  Future<void> addCategory({
    required String name,
    required int type,
    required String parentId,
    required int icon,
    int iconType = 0,
    required String color,
    String comment = '',
  }) async {
    await _api.post(
      '/api/v1/transaction/categories/add.json',
      body: {
        'name': name,
        'type': type,
        'parentId': parentId,
        'icon': '$icon',
        'iconType': iconType,
        'color': color,
        'comment': comment,
      },
    );
  }

  /// 修改分类。`POST /api/v1/transaction/categories/modify.json`
  ///
  /// 请求体**没有 `type`**（类型不可变）；`parentId` 必须与原值一致，
  /// 否则 `206007`/`206008 not allow to change ... primary ... secondary`。
  Future<void> modifyCategory({
    required String id,
    required String name,
    required String parentId,
    required int icon,
    int iconType = 0,
    required String color,
    String comment = '',
    bool hidden = false,
  }) async {
    await _api.post(
      '/api/v1/transaction/categories/modify.json',
      body: {
        'id': id,
        'name': name,
        'parentId': parentId,
        'icon': '$icon',
        'iconType': iconType,
        'color': color,
        'comment': comment,
        'hidden': hidden,
      },
    );
  }

  /// 隐藏/取消隐藏分类。`POST /api/v1/transaction/categories/hide.json`
  Future<void> hideCategory(String id, bool hidden) async {
    await _api.post(
      '/api/v1/transaction/categories/hide.json',
      body: {'id': id, 'hidden': hidden},
    );
  }

  /// 删除分类（**连子分类一起删**）。`POST .../categories/delete.json`
  Future<void> removeCategory(String id) async {
    await _api.post(
      '/api/v1/transaction/categories/delete.json',
      body: {'id': id},
    );
  }

  /// 新建标签。`POST /api/v1/transaction/tags/add.json`
  ///
  /// `groupId` 不填/填 `"0"` 就是"未分组"（标签组 Phase 2 再做）。
  Future<void> addTag({
    required String name,
    String groupId = '0',
  }) async {
    await _api.post(
      '/api/v1/transaction/tags/add.json',
      body: {'groupId': groupId, 'name': name},
    );
  }

  /// 改标签名。`POST /api/v1/transaction/tags/modify.json`
  Future<void> modifyTag({
    required String id,
    required String name,
    String groupId = '0',
  }) async {
    await _api.post(
      '/api/v1/transaction/tags/modify.json',
      body: {'id': id, 'groupId': groupId, 'name': name},
    );
  }

  /// 隐藏/取消隐藏标签。`POST /api/v1/transaction/tags/hide.json`
  Future<void> hideTag(String id, bool hidden) async {
    await _api.post(
      '/api/v1/transaction/tags/hide.json',
      body: {'id': id, 'hidden': hidden},
    );
  }

  /// 删标签。**有流水引用时报 `207004 transaction tag is in use...`**
  Future<void> removeTag(String id) async {
    await _api.post('/api/v1/transaction/tags/delete.json', body: {'id': id});
  }
}
