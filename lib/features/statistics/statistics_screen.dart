import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/util/money.dart';
import '../../data/dto/account_dto.dart';
import '../../data/dto/misc_dto.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/exchange_rate_repository.dart';
import '../../data/repositories/statistics_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../accounts/accounts_screen.dart';
import '../categories/category_options.dart';
import 'statistics_logic.dart';

/// 三张统计图
enum StatTab { category, trend, asset }

/// 快捷时间区间
enum StatRange {
  thisMonth('本月'),
  last30Days('近30天'),
  last3Months('近3月'),
  last6Months('近6月'),
  last12Months('近12月'),
  thisYear('今年');

  const StatRange(this.label);

  final String label;
}

DateTime _rangeStart(StatRange range, DateTime now) => switch (range) {
      StatRange.thisMonth => DateTime(now.year, now.month, 1),
      StatRange.last30Days =>
        DateTime(now.year, now.month, now.day).subtract(
          const Duration(days: 30),
        ),
      StatRange.last3Months => DateTime(now.year, now.month - 3, 1),
      StatRange.last6Months => DateTime(now.year, now.month - 6, 1),
      StatRange.last12Months => DateTime(now.year, now.month - 12, 1),
      StatRange.thisYear => DateTime(now.year, 1, 1),
    };

extension StatRangeSpec on StatRange {
  /// 秒区间。`end` 传"现在"就够了 —— 服务端会把起止**扩展到所在自然日的整日**
  /// （`GetMin/MaxUnixTimeWithSameLocalDateTime`），当天的流水一定落在里面
  ({int startTime, int endTime}) seconds(DateTime now) {
    final start = _rangeStart(this, now);
    return (
      startTime: start.millisecondsSinceEpoch ~/ 1000,
      endTime: now.millisecondsSinceEpoch ~/ 1000,
    );
  }

  /// 年月区间（`2026-01` 格式，趋势图专用）
  ({String startYearMonth, String endYearMonth}) yearMonths(DateTime now) {
    final start = _rangeStart(this, now);
    String ym(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}';
    return (startYearMonth: ym(start), endYearMonth: ym(now));
  }
}

/// 当前选中的图
final statTabProvider = StateProvider<StatTab>((_) => StatTab.category);

/// 每张图各自记住上次选的区间
final statRangeProvider = StateProvider.family<StatRange, StatTab>(
  (_, tab) => switch (tab) {
    StatTab.category => StatRange.thisMonth,
    StatTab.trend => StatRange.last6Months,
    StatTab.asset => StatRange.last6Months,
  },
);

/// 分类占比看支出还是收入
final statIncomeProvider = StateProvider<bool>((_) => false);

/// 每张图可选的区间（趋势图最少看几个月，资产趋势看近期）
List<StatRange> statRangesOf(StatTab tab) => switch (tab) {
      StatTab.category => const [
          StatRange.thisMonth,
          StatRange.last3Months,
          StatRange.last6Months,
          StatRange.thisYear,
        ],
      StatTab.trend => const [
          StatRange.last3Months,
          StatRange.last6Months,
          StatRange.last12Months,
          StatRange.thisYear,
        ],
      StatTab.asset => const [
          StatRange.last30Days,
          StatRange.last6Months,
          StatRange.thisYear,
        ],
    };

/// 统计页公共上下文：账户 / 分类（都拍平成 id 索引）+ 默认币种 + 汇率
class StatsContext {
  const StatsContext({
    required this.categories,
    required this.accounts,
    required this.defaultCurrency,
    required this.rates,
  });

  final Map<String, Category> categories;
  final Map<String, Account> accounts;

  /// 汇总前统一换算到这个币种（`users/profile/get.json` 的 `defaultCurrency`）
  final String defaultCurrency;
  final ExchangeRates? rates;
}

final statsContextProvider = FutureProvider.autoDispose<StatsContext>(
  (ref) async {
    final accounts = await ref.watch(accountsProvider.future);
    final categories = await ref.watch(categoriesProvider.future);
    final profile = await ref.watch(userProfileProvider.future);

    // 汇率接口挂了不该让整页白屏：降级成"只汇总同币种"，跨币种条目按 Web 同款跳过
    ExchangeRates? rates;
    try {
      rates = await ref.watch(exchangeRatesProvider.future);
    } catch (_) {
      rates = null;
    }

    return StatsContext(
      categories: categoryIndex(categories),
      accounts: accountIndex(accounts),
      defaultCurrency: profile.defaultCurrency,
      rates: rates,
    );
  },
);

/// 分类占比（区间 + 支出/收入切换作为 key）
final statCategorySlicesProvider = FutureProvider.autoDispose
    .family<List<StatSlice>, ({StatRange range, bool income})>(
  (ref, key) async {
    final ctx = await ref.watch(statsContextProvider.future);
    final overview = await ref.watch(
      statsOverviewProvider(key.range.seconds(DateTime.now())).future,
    );
    return slicesByPrimaryCategory(
      items: overview.items,
      categoryType: key.income
          ? StatCategoryType.income
          : StatCategoryType.expense,
      categories: ctx.categories,
      accounts: ctx.accounts,
      defaultCurrency: ctx.defaultCurrency,
      rates: ctx.rates,
    );
  },
);

/// 逐月收支
final statTrendPointsProvider = FutureProvider.autoDispose
    .family<List<TrendPoint>, StatRange>(
  (ref, range) async {
    final ctx = await ref.watch(statsContextProvider.future);
    final trends = await ref.watch(
      statsTrendsProvider(range.yearMonths(DateTime.now())).future,
    );
    return trendTotals(
      trends: trends,
      categories: ctx.categories,
      accounts: ctx.accounts,
      defaultCurrency: ctx.defaultCurrency,
      rates: ctx.rates,
    );
  },
);

/// 净资产逐日
final statAssetPointsProvider = FutureProvider.autoDispose
    .family<List<AssetPoint>, StatRange>(
  (ref, range) async {
    final ctx = await ref.watch(statsContextProvider.future);
    final days = await ref.watch(
      statsAssetTrendsProvider(range.seconds(DateTime.now())).future,
    );
    return assetSeries(
      days: days,
      accounts: ctx.accounts,
      defaultCurrency: ctx.defaultCurrency,
      rates: ctx.rates,
    );
  },
);

/// 统计页：分类占比饼图 / 收支趋势 / 资产趋势（fl_chart 三图，
/// 与 Web 统计页共用同一组 `statistics*.json` 端点）
class StatisticsScreen extends ConsumerWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(statTabProvider);
    final range = ref.watch(statRangeProvider(tab));

    return Scaffold(
      appBar: AppBar(title: const Text('统计')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<StatTab>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: StatTab.category, label: Text('分类占比')),
                ButtonSegment(value: StatTab.trend, label: Text('收支趋势')),
                ButtonSegment(value: StatTab.asset, label: Text('资产趋势')),
              ],
              selected: {tab},
              onSelectionChanged: (selection) =>
                  ref.read(statTabProvider.notifier).state = selection.first,
            ),
          ),
          SizedBox(
            height: 52,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final r in statRangesOf(tab))
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(r.label),
                        selected: r == range,
                        onSelected: (_) =>
                            ref.read(statRangeProvider(tab).notifier).state = r,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: switch (tab) {
              StatTab.category => _CategoryPane(range: range),
              StatTab.trend => _TrendPane(range: range),
              StatTab.asset => _AssetPane(range: range),
            },
          ),
        ],
      ),
    );
  }
}

/// 分类占比：支出 / 收入切换 + 饼图 + 图例
class _CategoryPane extends ConsumerWidget {
  const _CategoryPane({required this.range});

  final StatRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final income = ref.watch(statIncomeProvider);
    final key = (range: range, income: income);
    final ctxAsync = ref.watch(statsContextProvider);
    final slicesAsync = ref.watch(statCategorySlicesProvider(key));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('支出')),
                  ButtonSegment(value: true, label: Text('收入')),
                ],
                selected: {income},
                onSelectionChanged: (selection) =>
                    ref.read(statIncomeProvider.notifier).state =
                        selection.first,
              ),
              const Spacer(),
              Text('按一级分类汇总', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ctxAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(
              message: '$e',
              onRetry: () => ref.invalidate(statsContextProvider),
            ),
            data: (ctx) => slicesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorState(
                message: '$e',
                onRetry: () => ref.invalidate(statCategorySlicesProvider(key)),
              ),
              data: (slices) {
                if (slices.isEmpty) {
                  return Center(
                    child: Text(income ? '该区间还没有收入记录' : '该区间还没有支出记录'),
                  );
                }
                return _PieView(
                  slices: slices,
                  currency: ctx.defaultCurrency,
                  categoryType: income
                      ? StatCategoryType.income
                      : StatCategoryType.expense,
                  income: income,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _PieView extends StatelessWidget {
  const _PieView({
    required this.slices,
    required this.currency,
    required this.categoryType,
    required this.income,
  });

  final List<StatSlice> slices;
  final String currency;
  final int categoryType;
  final bool income;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = slices.fold<int>(0, (a, s) => a + s.amountMinor);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SizedBox(
          height: 230,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 44,
              sectionsSpace: 2,
              sections: [
                for (final s in slices)
                  PieChartSectionData(
                    value: s.amountMinor.toDouble(),
                    color: categoryColorOf(s.color),
                    radius: 54,
                    // 占比太小的扇区塞不下文字，交给下面的图例
                    title: s.percent >= 8
                        ? '${s.percent.toStringAsFixed(0)}%'
                        : '',
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '${income ? '收入合计' : '支出合计'}  '
            '${formatAmount(total, currency)}',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        const Divider(),
        for (final s in slices)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 11,
              backgroundColor: categoryColorOf(s.color).withValues(alpha: 0.18),
              child: Icon(
                categoryIconOf(s.icon, categoryType).icon,
                size: 14,
                color: categoryColorOf(s.color),
              ),
            ),
            title: Text(s.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(formatAmount(s.amountMinor, currency)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${s.percent.toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 收支趋势：收入 / 支出双折线
class _TrendPane extends ConsumerWidget {
  const _TrendPane({required this.range});

  final StatRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctxAsync = ref.watch(statsContextProvider);
    final pointsAsync = ref.watch(statTrendPointsProvider(range));

    return ctxAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: '$e',
        onRetry: () => ref.invalidate(statsContextProvider),
      ),
      data: (ctx) => pointsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(statTrendPointsProvider(range)),
        ),
        data: (points) {
          if (points.isEmpty) {
            return const Center(child: Text('该区间没有记录'));
          }
          return _TrendView(points: points, currency: ctx.defaultCurrency);
        },
      ),
    );
  }
}

const _incomeColor = Color(0xFF2F9E44);

class _TrendView extends StatelessWidget {
  const _TrendView({required this.points, required this.currency});

  final List<TrendPoint> points;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final expenseColor = theme.colorScheme.error;
    final maxY = points.fold<double>(
      0,
      (m, p) => math.max(m, math.max(p.incomeMinor, p.expenseMinor).toDouble()),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              _LegendDot(color: _incomeColor, label: '收入'),
              const SizedBox(width: 16),
              _LegendDot(color: expenseColor, label: '支出'),
              const Spacer(),
              Text(
                '${DateFormat('yyyy年M月').format(DateTime(points.first.year, points.first.month))}'
                ' 起',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (points.length - 1).toDouble(),
                minY: 0,
                maxY: maxY > 0 ? maxY * 1.15 : 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: theme.dividerColor.withValues(alpha: 0.6),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (value, _) => Text(
                        _axisLabel(value.toInt(), currency),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: 1,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= points.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${points[i].month}月',
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) =>
                        theme.colorScheme.surfaceContainerHighest,
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        LineTooltipItem(
                          '${spot.barIndex == 0 ? '收入' : '支出'} '
                          '${formatAmount(_valueOf(points, spot), currency)}',
                          TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < points.length; i++)
                        FlSpot(i.toDouble(), points[i].incomeMinor.toDouble()),
                    ],
                    color: _incomeColor,
                    barWidth: 2.5,
                    dotData: FlDotData(show: points.length <= 8),
                  ),
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < points.length; i++)
                        FlSpot(i.toDouble(), points[i].expenseMinor.toDouble()),
                    ],
                    color: expenseColor,
                    barWidth: 2.5,
                    dotData: FlDotData(show: points.length <= 8),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  int _valueOf(List<TrendPoint> points, LineBarSpot spot) {
    final i = spot.x.toInt();
    if (i < 0 || i >= points.length) return 0;
    return spot.barIndex == 0 ? points[i].incomeMinor : points[i].expenseMinor;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// 资产趋势：净资产逐日单折线
class _AssetPane extends ConsumerWidget {
  const _AssetPane({required this.range});

  final StatRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctxAsync = ref.watch(statsContextProvider);
    final pointsAsync = ref.watch(statAssetPointsProvider(range));

    return ctxAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: '$e',
        onRetry: () => ref.invalidate(statsContextProvider),
      ),
      data: (ctx) => pointsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(statAssetPointsProvider(range)),
        ),
        data: (points) {
          if (points.isEmpty) {
            return const Center(child: Text('该区间没有记录'));
          }
          return _AssetView(points: points, currency: ctx.defaultCurrency);
        },
      ),
    );
  }
}

class _AssetView extends StatelessWidget {
  const _AssetView({required this.points, required this.currency});

  final List<AssetPoint> points;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineColor = theme.colorScheme.primary;
    final maxY = points.fold<double>(
      0,
      (m, p) => math.max(m, p.netMinor.toDouble()),
    );
    final minY = points.fold<double>(
      0,
      (m, p) => math.min(m, p.netMinor.toDouble()),
    );
    // x 轴刻度：点太多时按步长抽稀，月初必标
    final step = math.max(1, (points.length / 6).ceil());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              _LegendDot(color: lineColor, label: '净资产'),
              const Spacer(),
              Text(
                '截至 ${DateFormat('M月d日').format(points.last.date)}',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: (points.length - 1).toDouble(),
                minY: minY < 0 ? minY * 1.1 : 0,
                maxY: maxY > 0 ? maxY * 1.15 : 100,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: theme.dividerColor.withValues(alpha: 0.6),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (value, _) => Text(
                        _axisLabel(value.toInt(), currency),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i < 0 || i >= points.length) {
                          return const SizedBox.shrink();
                        }
                        final date = points[i].date;
                        final show = date.day == 1 ||
                            i % step == 0 ||
                            i == points.length - 1;
                        if (!show) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            DateFormat('M/d').format(date),
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) =>
                        theme.colorScheme.surfaceContainerHighest,
                    getTooltipItems: (spots) => [
                      for (final spot in spots)
                        LineTooltipItem(
                          '${DateFormat('M月d日').format(points[spot.spotIndex].date)}'
                          '  ${formatAmount(points[spot.spotIndex].netMinor, currency)}',
                          TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: [
                      for (var i = 0; i < points.length; i++)
                        FlSpot(i.toDouble(), points[i].netMinor.toDouble()),
                    ],
                    color: lineColor,
                    barWidth: 2.5,
                    dotData: FlDotData(show: points.length <= 10),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          lineColor.withValues(alpha: 0.28),
                          lineColor.withValues(alpha: 0.02),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 坐标轴刻度：金额太大就压缩（123456 → 12.3万）
String _axisLabel(int minor, String currency) {
  final factor = math.pow(10, currencyFraction(currency)).toDouble();
  final major = minor / factor;
  final sign = major < 0 ? '-' : '';
  final abs = major.abs();

  if (abs >= 100000000) return '$sign${(abs / 100000000).toStringAsFixed(1)}亿';
  if (abs >= 10000) return '$sign${(abs / 10000).toStringAsFixed(1)}万';
  if (abs < 10) return '$sign${abs.toStringAsFixed(1)}';
  return '$sign${abs.toStringAsFixed(0)}';
}
