import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../dto/transaction_dto.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(apiClientProvider)),
);

/// 记账表单提交的数据（新建/修改共用）
class TxDraft {
  const TxDraft({
    required this.type,
    required this.categoryId,
    required this.time,
    required this.utcOffset,
    required this.sourceAccountId,
    required this.sourceAmount,
    this.destinationAccountId,
    this.destinationAmount = 0,
    this.hideAmount = false,
    this.tagIds = const [],
    this.comment = '',
  });

  final int type;
  final String categoryId;
  final int time;
  final int utcOffset;
  final String sourceAccountId;
  final int sourceAmount;
  final String? destinationAccountId;
  final int destinationAmount;
  final bool hideAmount;
  final List<String> tagIds;
  final String comment;
}

class TransactionRepository {
  TransactionRepository(this._api);

  final ApiClient _api;

  /// `GET /api/v1/transactions/get.json?id=&with_pictures=&trim_*=`
  /// （这些 bool 参数会让响应里的 account/category/tags 变成 null，所以都不传）
  Future<Transaction?> get(String id) async {
    final result = await _api.get(
      '/api/v1/transactions/get.json',
      query: {'id': id},
    );
    if (result is! Map<String, dynamic>) return null;
    return Transaction.fromJson(result);
  }

  /// 新建明细。`POST /api/v1/transactions/add.json`
  ///
  /// 契约要点（源码 models.TransactionCreateRequest + 实测）：
  /// * `time` 是 Unix 秒，`utcOffset` 是**东向为正**的分钟（UTC+8 → 480）
  /// * `sourceAccountId`/`categoryId` 是**字符串化 int64**
  /// * `sourceAmount` 是最小单位；**支出/收入都传正数**（服务端自己做符号运算：
  ///   收入 `+Amount`、支出 `-Amount` 扣减余额）
  /// * 非转账时 `destinationAmount` **必须为 0**，否则
  ///   `ErrTransactionDestinationAmountCannotBeSet`
  Future<void> add(TxDraft draft) async {
    await _api.post(
      '/api/v1/transactions/add.json',
      body: _buildBody(draft),
    );
  }

  /// 修改明细。`POST /api/v1/transactions/modify.json`（body 比 add 多一个 `id`）
  Future<void> modify({
    required String id,
    required TxDraft draft,
  }) async {
    await _api.post(
      '/api/v1/transactions/modify.json',
      body: {'id': id, ..._buildBody(draft)},
    );
  }

  /// 删除单条。`POST /api/v1/transactions/delete.json`（`{id}`）
  /// 注意：该接口强制要求 `X-Timezone-Offset` 头，拦截器已统一带上
  Future<void> remove(String id) async {
    await _api.post('/api/v1/transactions/delete.json', body: {'id': id});
  }

  Map<String, dynamic> _buildBody(TxDraft d) {
    return {
      'type': d.type,
      'categoryId': d.categoryId,
      'time': d.time,
      'utcOffset': d.utcOffset,
      'sourceAccountId': d.sourceAccountId,
      'destinationAccountId': d.destinationAccountId ?? '0',
      'sourceAmount': d.sourceAmount,
      'destinationAmount': d.destinationAmount,
      'hideAmount': d.hideAmount,
      'tagIds': d.tagIds,
      'pictureIds': const <String>[],
      'comment': d.comment,
    };
  }

  /// 按月分页明细（MVP 的主列表）。
  ///
  /// `GET /api/v1/transactions/list/by_month.json`
  /// 必填 `year`、`month`（源码 `TransactionListInMonthByPageRequest`），
  /// 可选过滤：
  /// * `type` 1..4（不传 = 全部）
  /// * `category_ids` / `account_ids`：**逗号分隔的 id 串**；传一级分类 id 时
  ///   服务端会**自动展开成它的子分类**再比对（`GetCategoryOrSubCategoryIds`）
  /// * `keyword` + `match_mode`：`0`=默认（区分大小写）、`1`=忽略大小写
  ///   → 这里恒发 `1`，中文不受影响，英文关键词不用管大小写
  /// * `must_have_pictures`：只看带图的
  Future<TransactionPage> listByMonth({
    required int year,
    required int month,
    int? type,
    String? keyword,
    String? categoryIds,
    String? accountIds,
    bool mustHavePictures = false,
  }) async {
    final query = <String, dynamic>{
      'year': year,
      'month': month,
      'with_pictures': true,
      'trim_account': true,
      'trim_category': true,
    };
    if (type != null && type > 0) query['type'] = type;
    if (keyword != null && keyword.isNotEmpty) {
      query['keyword'] = keyword;
      query['match_mode'] = 1;
    }
    if (categoryIds != null && categoryIds.isNotEmpty) {
      query['category_ids'] = categoryIds;
    }
    if (accountIds != null && accountIds.isNotEmpty) {
      query['account_ids'] = accountIds;
    }
    if (mustHavePictures) query['must_have_pictures'] = true;

    final result = await _api.get(
      '/api/v1/transactions/list/by_month.json',
      query: query,
    );
    return TransactionPage.fromJson(result as Map<String, dynamic>);
  }

  /// `GET /api/v1/transactions/count.json` —— 用于徽标数字。
  /// 时间参数是 `max_time` / `min_time`（**不是** start_time/end_time），
  /// 语义是 time sequence id（models.TransactionCountRequest）
  Future<int> count({int? maxTime, int? minTime}) async {
    final query = <String, dynamic>{};
    if (maxTime != null) query['max_time'] = maxTime;
    if (minTime != null) query['min_time'] = minTime;

    final result = await _api.get(
      '/api/v1/transactions/count.json',
      query: query.isEmpty ? null : query,
    );
    if (result is int) return result;
    if (result is Map<String, dynamic>) {
      return result['count'] is int
          ? result['count'] as int
          : (int.tryParse('${result['count'] ?? 0}') ?? 0);
    }
    return 0;
  }
}
