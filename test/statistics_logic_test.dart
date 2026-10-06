/// 统计聚合逻辑单测：口径必须与 Web `src/stores/statistics.ts` 对齐
/// （按一级分类归并、只留同类型分类、金额换算成默认币种、资产趋势空档结转）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ebk_mobile/data/dto/account_dto.dart';
import 'package:ebk_mobile/data/dto/misc_dto.dart';
import 'package:ebk_mobile/data/dto/statistics_dto.dart';
import 'package:ebk_mobile/data/repositories/exchange_rate_repository.dart';
import 'package:ebk_mobile/features/statistics/statistics_logic.dart';

Category _cat(
  String id, {
  required String name,
  required int type,
  String parentId = '0',
  List<Category> children = const [],
}) =>
    Category(
      id: id,
      name: name,
      type: type,
      color: 'E8A33D',
      icon: 1,
      hidden: false,
      parentId: parentId,
      children: children,
    );

Account _acc(String id, {String currency = 'CNY', bool liability = false}) =>
    Account(
      id: id,
      name: '账户$id',
      parentId: '0',
      category: liability ? 3 : 1,
      type: 1,
      icon: 1,
      iconType: 0,
      color: '3B7DD8',
      currency: currency,
      balance: '0',
      comment: '',
      displayOrder: 1,
      isAsset: !liability,
      isLiability: liability,
      hidden: false,
      subAccounts: const [],
    );

StatItem _item(
  String category,
  String account,
  int amount, {
  int relatedType = 0,
}) =>
    StatItem(
      categoryId: category,
      accountId: account,
      relatedAccountId: relatedType == 0 ? '' : 'other',
      relatedAccountType: relatedType,
      amount: amount,
    );

/// 支出一级 200（子 201）、支出一级 400（子 401）+ 收入一级 100 + 转账一级 300
List<Category> _tree() => [
      _cat(
        '200',
        name: '食品饮料',
        type: 2,
        children: [_cat('201', name: '食品', type: 2, parentId: '200')],
      ),
      _cat(
        '400',
        name: '交通',
        type: 2,
        children: [_cat('401', name: '公交', type: 2, parentId: '400')],
      ),
      _cat('100', name: '工资', type: 1),
      _cat('300', name: '一般转账', type: 3),
    ];

void main() {
  group('categoryIndex / accountIndex', () {
    test('分类树拍平后能按 id 找到子分类', () {
      final index = categoryIndex(_tree());

      expect(index.length, 6);
      expect(index['201']!.name, '食品');
      expect(index['201']!.parentId, '200');
    });

    test('账户索引包含子账户（流水挂在子账户上）', () {
      final parent = _acc('1').copyWithSub(
        [_acc('2', currency: 'USD')],
      );

      final index = accountIndex([parent, _acc('3')]);

      expect(index.keys, containsAll(['1', '2', '3']));
      expect(index['2']!.currency, 'USD');
    });
  });

  group('toDefaultCurrency', () {
    test('同币种直接返回原值', () {
      expect(
        toDefaultCurrency(1234, 'CNY', 'CNY', null),
        1234,
        reason: '没汇率也必须能算 —— 同币种不依赖汇率',
      );
    });

    test('拿不到汇率时跨币种返回 null（调用方整条跳过）', () {
      expect(toDefaultCurrency(1234, 'USD', 'CNY', null), isNull);
    });

    test('按汇率换算并四舍五入到最小单位', () {
      // 汇率表口径：rates[X] = 1 单位基准币种能换多少 X
      // （base = CNY 时 USD:0.5 即 1 元 = 0.5 美元）
      final rates = ExchangeRates(
        baseCurrency: 'CNY',
        rates: const {'CNY': 1, 'USD': 0.5},
      );

      expect(toDefaultCurrency(100, 'USD', 'CNY', rates), 200);
      expect(toDefaultCurrency(101, 'CNY', 'USD', rates), 51);
    });
  });

  group('slicesByPrimaryCategory（分类占比）', () {
    final accounts = accountIndex([_acc('a'), _acc('b', currency: 'USD')]);

    test('子分类归并到一级；类型不符 / 分类缺失 / 账户缺失的条目跳过', () {
      final slices = slicesByPrimaryCategory(
        items: [
          _item('201', 'a', 1234), // 子分类 → 归并到 200
          _item('200', 'a', 500), // 一级本身
          _item('100', 'a', 5678), // 收入分类，支出口径下跳过
          _item('300', 'a', 1000), // 转账分类，两张占比图都不参与
          _item('201', 'ghost', 700), // 账户不存在
          _item('999', 'a', 999), // 分类不存在
        ],
        categoryType: StatCategoryType.expense,
        categories: categoryIndex(_tree()),
        accounts: accounts,
        defaultCurrency: 'CNY',
      );

      expect(slices, hasLength(1));
      expect(slices.single.categoryId, '200');
      expect(slices.single.amountMinor, 1734);
      expect(slices.single.percent, 100);
    });

    test('跨币种换算成默认币种；换不了的整条跳过', () {
      final accounts = accountIndex([
        _acc('a'),
        _acc('b', currency: 'USD'),
        _acc('z', currency: 'JPY'), // 汇率表里没有日元
      ]);
      final rates = ExchangeRates(
        baseCurrency: 'CNY',
        rates: const {'CNY': 1, 'USD': 0.5},
      );

      final slices = slicesByPrimaryCategory(
        items: [
          _item('201', 'a', 100), // 同币种原样
          _item('201', 'b', 100), // USD → CNY = 100 / 0.5 = 200
          _item('201', 'z', 777), // 没汇率 → 整条跳过
        ],
        categoryType: StatCategoryType.expense,
        categories: categoryIndex(_tree()),
        accounts: accounts,
        defaultCurrency: 'CNY',
        rates: rates,
      );

      expect(slices.single.amountMinor, 300);
    });

    test('百分比 = 该项 / 总额 × 100，且按金额降序', () {
      final expense = slicesByPrimaryCategory(
        items: [
          _item('401', 'a', 750), // 子分类 → 一级 400
          _item('201', 'a', 250), // 子分类 → 一级 200
          _item('100', 'a', 9999), // 收入分类，不参与支出口径
        ],
        categoryType: StatCategoryType.expense,
        categories: categoryIndex(_tree()),
        accounts: accounts,
        defaultCurrency: 'CNY',
      );

      expect(expense.map((s) => s.categoryId), ['400', '200'], reason: '降序');
      expect(expense.first.percent, 75);
      expect(expense.last.percent, 25);

      final income = slicesByPrimaryCategory(
        items: [
          _item('100', 'a', 250),
          _item('201', 'a', 750), // 支出分类，不参与收入口径
        ],
        categoryType: StatCategoryType.income,
        categories: categoryIndex(_tree()),
        accounts: accounts,
        defaultCurrency: 'CNY',
      );

      expect(income.single.name, '工资');
      expect(income.single.percent, 100);
    });

    test('转账（relatedAccountType）在收支两张图里都不出现', () {
      final slices = slicesByPrimaryCategory(
        items: [
          _item('300', 'a', 1000, relatedType: 2),
          _item('201', 'a', 10),
        ],
        categoryType: StatCategoryType.expense,
        categories: categoryIndex(_tree()),
        accounts: accounts,
        defaultCurrency: 'CNY',
      );

      expect(slices.map((s) => s.categoryId), ['200']);
      expect(slices.single.amountMinor, 10);
    });
  });

  group('trendTotals（收支趋势）', () {
    final categories = categoryIndex(_tree());
    final accounts = accountIndex([_acc('a')]);

    test('按月合计、只算收支两类、结果按年月升序', () {
      final points = trendTotals(
        trends: [
          // 故意乱序
          StatTrend(year: 2026, month: 10, items: [
            _item('201', 'a', 1000),
            _item('300', 'a', 300),
          ]),
          StatTrend(year: 2026, month: 9, items: [
            _item('100', 'a', 5000),
            _item('201', 'a', 2000),
          ]),
        ],
        categories: categories,
        accounts: accounts,
        defaultCurrency: 'CNY',
      );

      expect(points, hasLength(2));
      expect([points.first.year, points.first.month], [2026, 9]);
      expect(points.first.incomeMinor, 5000);
      expect(points.first.expenseMinor, 2000);
      expect(points.first.netMinor, 3000);
      // 10 月：转账不计入
      expect(points.last.incomeMinor, 0);
      expect(points.last.expenseMinor, 1000);
    });

    test('分类/账户解析不出来的条目跳过', () {
      final points = trendTotals(
        trends: [
          StatTrend(year: 2026, month: 10, items: [
            _item('999', 'a', 100),
            _item('201', 'ghost', 100),
            _item('201', 'a', 100),
          ]),
        ],
        categories: categories,
        accounts: accounts,
        defaultCurrency: 'CNY',
      );

      expect(points.single.expenseMinor, 100);
    });
  });

  group('assetSeries（资产趋势）', () {
    final accounts = accountIndex([
      _acc('a'),
      _acc('cc', liability: true),
      // 注意：流水里出现的 'gone' 账户**不在**索引里（等价于已被删除）
    ]);

    List<AssetTrendDay> days() => [
          AssetTrendDay(year: 2026, month: 10, day: 1, balances: const [
            AssetBalance(accountId: 'a', openingMinor: 0, closingMinor: 1000),
          ]),
          AssetTrendDay(year: 2026, month: 10, day: 3, balances: const [
            AssetBalance(accountId: 'a', openingMinor: 1000, closingMinor: 3000),
            AssetBalance(accountId: 'cc', openingMinor: 0, closingMinor: -500),
            AssetBalance(accountId: 'gone', openingMinor: 0, closingMinor: 9999),
          ]),
        ];

    test('空档用上一交易日的结转余额补点', () {
      final points = assetSeries(
        days: days(),
        accounts: accounts,
        defaultCurrency: 'CNY',
      );

      expect(points.map((p) => p.date.day), [1, 2, 3]);
      expect(points[0].netMinor, 1000);
      expect(points[1].netMinor, 1000, reason: '2 日没交易 → 结转 1 日的余额');
      expect(points[2].netMinor, 3000 - 500, reason: '负债余额自带负号');
    });

    test('已删除的账户不再计入净资产', () {
      final points = assetSeries(
        days: days(),
        accounts: accounts,
        defaultCurrency: 'CNY',
      );

      expect(points.last.netMinor, 2500, reason: 'gone 账户 9999 不该进来');
    });

    test('没有交易日 → 空序列', () {
      expect(
        assetSeries(
          days: const [],
          accounts: accounts,
          defaultCurrency: 'CNY',
        ),
        isEmpty,
      );
    });

    test('非交易日顺位排序（服务端返回乱序也不怕）', () {
      final unordered = days().reversed.toList();
      final points = assetSeries(
        days: unordered,
        accounts: accounts,
        defaultCurrency: 'CNY',
      );

      expect(points.map((p) => p.date.day), [1, 2, 3]);
    });
  });
}

extension on Account {
  Account copyWithSub(List<Account> sub) => Account(
        id: id,
        name: name,
        parentId: parentId,
        category: category,
        type: type,
        icon: icon,
        iconType: iconType,
        color: color,
        currency: currency,
        balance: balance,
        comment: comment,
        displayOrder: displayOrder,
        isAsset: isAsset,
        isLiability: isLiability,
        hidden: hidden,
        subAccounts: sub,
      );
}
