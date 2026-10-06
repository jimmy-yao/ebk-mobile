import '../../data/dto/account_dto.dart';
import '../../data/dto/misc_dto.dart';
import '../../data/dto/statistics_dto.dart';
import '../../data/repositories/exchange_rate_repository.dart';

/// 分类 `type`（源码 `models.CATEGORY_TYPE_*`）
class StatCategoryType {
  static const int income = 1;
  static const int expense = 2;
  static const int transfer = 3;
}

/// 分类树 → id 索引（含子分类；服务端只有两级，但这里不假设）
Map<String, Category> categoryIndex(List<Category> tree) {
  final index = <String, Category>{};

  void walk(List<Category> items) {
    for (final c in items) {
      index[c.id] = c;
      walk(c.children);
    }
  }

  walk(tree);
  return index;
}

/// 账户列表 → id 索引。
///
/// 响应是**顶层账户 + 嵌套 subAccounts**，统计里既可能出现顶层账户，
/// 也可能出现子账户（流水挂在子账户上），所以两边都要收进来 ——
/// 父账户不会因为"带子账户"而重复计数：父账户本身没有流水，
/// 资产趋势里也就不会出现它的行。
Map<String, Account> accountIndex(List<Account> accounts) {
  final index = <String, Account>{};

  void walk(List<Account> items) {
    for (final a in items) {
      index[a.id] = a;
      walk(a.subAccounts);
    }
  }

  walk(accounts);
  return index;
}

/// 换算到用户默认币种；拿不到汇率时返回 null（调用方按 Web 的做法跳过该条）
int? toDefaultCurrency(
  int minorAmount,
  String fromCurrency,
  String defaultCurrency,
  ExchangeRates? rates,
) {
  if (fromCurrency.toUpperCase() == defaultCurrency.toUpperCase()) {
    return minorAmount;
  }
  if (rates == null) return null;
  return rates.convert(minorAmount, fromCurrency, defaultCurrency);
}

/// 分类占比里的一"块"（一级分类）
class StatSlice {
  const StatSlice({
    required this.categoryId,
    required this.name,
    required this.color,
    required this.icon,
    required this.amountMinor,
    required this.percent,
  });

  final String categoryId;
  final String name;
  /// 6 位 hex（不带 #），配 `categoryColorOf()`
  final String color;
  final int icon;

  /// 已换算成默认币种的最小单位金额
  final int amountMinor;

  /// 0..100
  final double percent;
}

/// 支出 / 收入的分类占比（按**一级分类**归并）。
///
/// 口径对齐 Web `src/stores/statistics.ts`：
/// * `assembleAccountAndCategoryInfo` —— 分类 / 账户解析不出来、
///   或金额换不成默认币种的条目**整条跳过**；
/// * `getCategoryTotalAmountItems` 的 `ExpenseByPrimaryCategory` /
///   `IncomeByPrimaryCategory` —— 只留 `category.type` 相符的项
///   （**转账整体不参与**这两张图），子分类归并到一级分类；
/// * `percent = 该项 / Σ × 100`（金额都是正数，等价于 Web 的
///   `totalNonNegativeAmount`），按金额降序。
List<StatSlice> slicesByPrimaryCategory({
  required List<StatItem> items,
  required int categoryType,
  required Map<String, Category> categories,
  required Map<String, Account> accounts,
  required String defaultCurrency,
  ExchangeRates? rates,
}) {
  final totals = <String, int>{};

  for (final item in items) {
    final category = categories[item.categoryId];
    if (category == null || category.type != categoryType) continue;

    final primary =
        category.isPrimary ? category : categories[category.parentId];
    if (primary == null) continue;

    final account = accounts[item.accountId];
    if (account == null) continue;

    final amount = toDefaultCurrency(
      item.amount,
      account.currency,
      defaultCurrency,
      rates,
    );
    if (amount == null) continue;

    totals[primary.id] = (totals[primary.id] ?? 0) + amount;
  }

  final sum = totals.values.fold<int>(0, (a, b) => a + b);
  final slices = totals.entries.map((e) {
    final category = categories[e.key]!;
    return StatSlice(
      categoryId: category.id,
      name: category.name,
      color: category.color,
      icon: category.icon,
      amountMinor: e.value,
      percent: sum > 0 ? e.value * 100 / sum : 0,
    );
  }).toList()
    ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

  return slices;
}

/// 收支趋势上的一个点（一个自然月）
class TrendPoint {
  const TrendPoint({
    required this.year,
    required this.month,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final int year;
  final int month;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;
}

/// 逐月「收入 / 支出」合计（**不含转账**）。
///
/// 与 Web 的 `TotalIncome` / `TotalExpense` 图表口径一致：
/// 只按分类 type 计入，转账分类（type=3）不参与。
/// 分类是几级都不影响总额（一条流水只挂一个分类，不会重复计）。
List<TrendPoint> trendTotals({
  required List<StatTrend> trends,
  required Map<String, Category> categories,
  required Map<String, Account> accounts,
  required String defaultCurrency,
  ExchangeRates? rates,
}) {
  final points = <TrendPoint>[];

  for (final trend in trends) {
    var income = 0;
    var expense = 0;

    for (final item in trend.items) {
      final category = categories[item.categoryId];
      if (category == null) continue;

      final account = accounts[item.accountId];
      if (account == null) continue;

      final amount = toDefaultCurrency(
        item.amount,
        account.currency,
        defaultCurrency,
        rates,
      );
      if (amount == null) continue;

      if (category.type == StatCategoryType.income) {
        income += amount;
      } else if (category.type == StatCategoryType.expense) {
        expense += amount;
      }
    }

    points.add(
      TrendPoint(
        year: trend.year,
        month: trend.month,
        incomeMinor: income,
        expenseMinor: expense,
      ),
    );
  }

  points.sort(
    (a, b) => (a.year * 100 + a.month).compareTo(b.year * 100 + b.month),
  );
  return points;
}

/// 净资产趋势上的一个点
class AssetPoint {
  const AssetPoint({required this.date, required this.netMinor});

  final DateTime date;
  final int netMinor;
}

/// 净资产逐日曲线。
///
/// 空档补齐规则与 Web 一致（`assetTrendsDataWithAccountInfo`）：
/// 服务端**只返回有交易的日子**，相邻两天之间的空档用
/// 「上一个已知交易日的各账户收盘余额」结转补点。
///
/// ⚠️ 汇总口径（已实测核实，与 Web 移动端统计页**有意不同**）：
/// 账户余额本身带符号 —— 实测信用卡消费 500 分后 `balance = -500` ——
/// 所以净资产 = Σ资产余额 **+** Σ负债余额（负债自带负号），
/// 这与桌面版 `NetAssetsTrendWidget`（两边都 add）一致；
/// 而 `stores/statistics.ts` 对负债做的是**减法**，欠款会被算成正资产。
/// App 取正确的口径，差异记在方案文档里。
List<AssetPoint> assetSeries({
  required List<AssetTrendDay> days,
  required Map<String, Account> accounts,
  required String defaultCurrency,
  ExchangeRates? rates,
}) {
  if (days.isEmpty) return const [];

  final sorted = [...days]
    ..sort((a, b) => (a.year * 10000 + a.month * 100 + a.day)
        .compareTo(b.year * 10000 + b.month * 100 + b.day));

  // accountId → 最近一次已知的收盘余额
  final carry = <String, int>{};
  final points = <AssetPoint>[];
  DateTime? previous;

  int netTotal() {
    var total = 0;
    carry.forEach((accountId, balance) {
      final account = accounts[accountId];
      if (account == null) return; // 已删除的账户不再计入
      final converted = toDefaultCurrency(
        balance,
        account.currency,
        defaultCurrency,
        rates,
      );
      if (converted == null) return;
      total += converted;
    });
    return total;
  }

  for (final day in sorted) {
    final date = day.date;

    // 中间空档：沿用上一交易日的结转余额补点
    if (previous != null) {
      for (var d = previous.add(const Duration(days: 1));
          d.isBefore(date);
          d = d.add(const Duration(days: 1))) {
        points.add(AssetPoint(date: d, netMinor: netTotal()));
      }
    }

    for (final balance in day.balances) {
      if (!accounts.containsKey(balance.accountId)) continue;
      carry[balance.accountId] = balance.closingMinor;
    }

    points.add(AssetPoint(date: date, netMinor: netTotal()));
    previous = date;
  }

  return points;
}
