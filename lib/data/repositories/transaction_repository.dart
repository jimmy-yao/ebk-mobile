import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../dto/transaction_dto.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(apiClientProvider)),
);

class TransactionRepository {
  TransactionRepository(this._api);

  final ApiClient _api;

  /// 按月分页明细（MVP 的主列表）。
  ///
  /// `GET /api/v1/transactions/list/by_month.json`
  /// 必填 `year`、`month`（源码 TransactionListInMonthByPageRequest），
  /// 可选过滤：type / category_ids / account_ids / keyword / must_have_pictures ...
  Future<TransactionPage> listByMonth({
    required int year,
    required int month,
    int? type,
    String? keyword,
  }) async {
    final query = <String, dynamic>{
      'year': year,
      'month': month,
      'with_pictures': true,
      'trim_account': true,
      'trim_category': true,
    };
    if (type != null) query['type'] = type;
    if (keyword != null && keyword.isNotEmpty) query['keyword'] = keyword;

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
