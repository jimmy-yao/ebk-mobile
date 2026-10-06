import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../dto/statistics_dto.dart';

final statisticsRepositoryProvider = Provider<StatisticsRepository>(
  (ref) => StatisticsRepository(ref.watch(apiClientProvider)),
);

/// 秒区间（Unix 秒），当 family key 用（record 有值相等语义）
typedef StatSecondsRange = ({int startTime, int endTime});

/// 年月区间（`2026-01` 这种），当 family key 用
typedef StatYearMonthRange = ({String startYearMonth, String endYearMonth});

/// 分类占比（饼图）—— 与 Web 统计页同一个 `statistics.json`
final statsOverviewProvider = FutureProvider.autoDispose
    .family<StatOverview, StatSecondsRange>(
  (ref, range) => ref.watch(statisticsRepositoryProvider).overview(
        startTime: range.startTime,
        endTime: range.endTime,
      ),
);

/// 收支趋势：每个自然月一组 items（服务端按年月升序返回）
final statsTrendsProvider = FutureProvider.autoDispose
    .family<List<StatTrend>, StatYearMonthRange>(
  (ref, range) => ref.watch(statisticsRepositoryProvider).trends(
        startYearMonth: range.startYearMonth,
        endYearMonth: range.endYearMonth,
      ),
);

/// 资产趋势：逐日账户余额（**只返回有交易的日子**，空档要自己结转补齐）
final statsAssetTrendsProvider = FutureProvider.autoDispose
    .family<List<AssetTrendDay>, StatSecondsRange>(
  (ref, range) => ref.watch(statisticsRepositoryProvider).assetTrends(
        startTime: range.startTime,
        endTime: range.endTime,
      ),
);

/// 统计三端点（源码 `pkg/api/transactions.go` 的
/// `TransactionStatisticsHandler` / `TransactionStatisticsTrendsHandler` /
/// `TransactionStatisticsAssetTrendsHandler`，线上实测见 `scripts/smoke.sh` 12 节）。
///
/// 契约要点：
/// * 三个都必须带 `X-Timezone-Name` 头（服务端 `GetClientTimezone()`，
///   缺了直接报错），拦截器已统一携带
/// * 秒区间参数会被服务端**扩展到所在自然日的整日**
///   （`GetMin/MaxUnixTimeWithSameLocalDateTime`），所以传"现在"即可覆盖当天
/// * 年月参数格式是 `2026-01`（`utils.ParseNumericYearMonth` 按 `-` 切）
class StatisticsRepository {
  StatisticsRepository(this._api);

  final ApiClient _api;

  /// `GET /api/v1/transactions/statistics.json?start_time=&end_time=`
  Future<StatOverview> overview({
    required int startTime,
    required int endTime,
  }) async {
    final result = await _api.get(
      '/api/v1/transactions/statistics.json',
      query: {'start_time': '$startTime', 'end_time': '$endTime'},
    );
    if (result is! Map<String, dynamic>) {
      return StatOverview(startTime: startTime, endTime: endTime, items: const []);
    }
    return StatOverview.fromJson(result);
  }

  /// `GET /api/v1/transactions/statistics/trends.json?start_year_month=&end_year_month=`
  Future<List<StatTrend>> trends({
    required String startYearMonth,
    required String endYearMonth,
  }) async {
    final result = await _api.get(
      '/api/v1/transactions/statistics/trends.json',
      query: {
        'start_year_month': startYearMonth,
        'end_year_month': endYearMonth,
      },
    );
    if (result is! List<dynamic>) return const [];
    return result
        .whereType<Map<String, dynamic>>()
        .map(StatTrend.fromJson)
        .toList();
  }

  /// `GET /api/v1/transactions/statistics/asset_trends.json?start_time=&end_time=`
  Future<List<AssetTrendDay>> assetTrends({
    required int startTime,
    required int endTime,
  }) async {
    final result = await _api.get(
      '/api/v1/transactions/statistics/asset_trends.json',
      query: {'start_time': '$startTime', 'end_time': '$endTime'},
    );
    if (result is! List<dynamic>) return const [];
    return result
        .whereType<Map<String, dynamic>>()
        .map(AssetTrendDay.fromJson)
        .toList();
  }
}
