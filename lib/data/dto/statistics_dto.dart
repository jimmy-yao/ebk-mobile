/// 统计三端点的 DTO —— 源码 `pkg/models/transaction.go`，
/// 线上实测见 `scripts/smoke.sh` 第 12 节。
///
/// | 端点 | 请求参数 | 响应 |
/// |---|---|---|
/// | `GET /api/v1/transactions/statistics.json` | `start_time` / `end_time`（Unix 秒） | `{startTime, endTime, items[]}` |
/// | `GET .../statistics/trends.json` | `start_year_month` / `end_year_month`（`2026-01` 这种） | `[{year, month, items[]}]`，按年月升序 |
/// | `GET .../statistics/asset_trends.json` | `start_time` / `end_time` | `[{year, month, day, items[]}]`，**只有发生过交易的日子** |
///
/// 前两个端点的 `items[]` 每项（`models.TransactionStatisticResponseItem`）：
///
/// ```json
/// {"categoryId":"3846579121073160262","accountId":"3846683640981356544","amount":"1234"}
/// ```
///
/// * id 一律**字符串化 int64**（`json:",string"`）
/// * `amount` 是**正数**最小单位字符串：服务端按 (分类, 账户, 对端, 类型) 分组后
///   直接累加原值、不做任何符号运算
///   （`TransactionService.GetAccountsAndCategoriesTotalInflowAndOutflow`），
///   所以支出还是收入只能靠 `categoryId` 上挂的分类 `type` 判定
/// * 转账会多 `relatedAccountId` + `relatedAccountType`
///   （**1 = 对端是转出方、2 = 对端是转入方**，源码 `ToTransactionRelatedAccountType`），
///   同一笔转账会出两项：转出账户一项、转入账户一项
/// * 「调整余额」（type=1）不进统计
///
/// `asset_trends` 的 `items[]` 字段是
/// `{accountId, accountOpeningBalance, accountClosingBalance}`，
/// 余额是**带符号**的累计值（实测信用卡消费 500 分后 = `"-500"`），
/// 且是**截至该日**的全量余额 —— 不受查询区间影响。
class StatItem {
  const StatItem({
    required this.categoryId,
    required this.accountId,
    required this.relatedAccountId,
    required this.relatedAccountType,
    required this.amount,
  });

  /// 分类 id。资产趋势里被前端当成"补白项"复用时是空串
  final String categoryId;
  final String accountId;

  /// 非转账时响应里 `omitempty` 直接省略该字段 → 空串
  final String relatedAccountId;

  /// 0=非转账；1=对端是转出方；2=对端是转入方
  final int relatedAccountType;

  /// 正数最小单位
  final int amount;

  bool get isTransfer => relatedAccountType != 0;

  factory StatItem.fromJson(Map<String, dynamic> json) => StatItem(
        categoryId: json['categoryId']?.toString() ?? '',
        accountId: json['accountId']?.toString() ?? '',
        relatedAccountId: json['relatedAccountId']?.toString() ?? '',
        relatedAccountType: _asInt(json['relatedAccountType']),
        amount: int.tryParse(json['amount']?.toString() ?? '') ?? 0,
      );
}

/// `statistics.json`：区间内按 (分类, 账户) 汇总的总流水
class StatOverview {
  const StatOverview({
    required this.startTime,
    required this.endTime,
    required this.items,
  });

  final int startTime;
  final int endTime;
  final List<StatItem> items;

  factory StatOverview.fromJson(Map<String, dynamic> json) => StatOverview(
        startTime: _asInt(json['startTime']),
        endTime: _asInt(json['endTime']),
        items: _itemsOf(json['items']),
      );
}

/// `trends.json` 里的一组（一个自然月）
class StatTrend {
  const StatTrend({required this.year, required this.month, required this.items});

  final int year;
  final int month;
  final List<StatItem> items;

  factory StatTrend.fromJson(Map<String, dynamic> json) => StatTrend(
        year: _asInt(json['year']),
        month: _asInt(json['month']),
        items: _itemsOf(json['items']),
      );
}

/// 某账户某一天的开盘 / 收盘余额（最小单位，带符号）
class AssetBalance {
  const AssetBalance({
    required this.accountId,
    required this.openingMinor,
    required this.closingMinor,
  });

  final String accountId;
  final int openingMinor;
  final int closingMinor;

  factory AssetBalance.fromJson(Map<String, dynamic> json) => AssetBalance(
        accountId: json['accountId']?.toString() ?? '',
        openingMinor: int.tryParse(
              json['accountOpeningBalance']?.toString() ?? '',
            ) ??
            0,
        closingMinor:
            int.tryParse(json['accountClosingBalance']?.toString() ?? '') ?? 0,
      );
}

/// `asset_trends.json` 里的一天
class AssetTrendDay {
  const AssetTrendDay({
    required this.year,
    required this.month,
    required this.day,
    required this.balances,
  });

  final int year;
  final int month;
  final int day;
  final List<AssetBalance> balances;

  DateTime get date => DateTime(year, month, day);

  factory AssetTrendDay.fromJson(Map<String, dynamic> json) => AssetTrendDay(
        year: _asInt(json['year']),
        month: _asInt(json['month']),
        day: _asInt(json['day']),
        balances: (json['items'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(AssetBalance.fromJson)
            .toList(),
      );
}

List<StatItem> _itemsOf(dynamic raw) => (raw as List<dynamic>? ?? const [])
    .whereType<Map<String, dynamic>>()
    .map(StatItem.fromJson)
    .toList();

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
