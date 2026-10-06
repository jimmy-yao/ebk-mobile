/// 统计页界面冒烟：三张图能渲染、切图 / 切区间会按**对应端点 + 对应参数**
/// 重新拉数据（饼图 statistics.json、趋势 trends.json、资产 asset_trends.json）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebk_mobile/core/network/api_client.dart';
import 'package:ebk_mobile/core/storage/token_store.dart';
import 'package:ebk_mobile/features/statistics/statistics_screen.dart';

import 'fakes.dart';

final _accountJson = <String, dynamic>{
  'id': '7',
  'name': '现金钱包',
  'parentId': '0',
  'category': 1,
  'type': 1,
  'icon': '1',
  'iconType': 0,
  'color': '3B7DD8',
  'currency': 'CNY',
  'balance': '5000',
  'comment': '',
  'displayOrder': 1,
  'hidden': false,
};

final _categoriesJson = <String, dynamic>{
  '1': [
    {
      'id': '100',
      'name': '工资',
      'parentId': '0',
      'type': 1,
      'icon': '1',
      'iconType': 0,
      'color': '2F9E44',
      'comment': '',
      'hidden': false,
      'subCategories': <dynamic>[],
    },
  ],
  '2': [
    {
      'id': '200',
      'name': '食品饮料',
      'parentId': '0',
      'type': 2,
      'icon': '1',
      'iconType': 0,
      'color': 'E8A33D',
      'comment': '',
      'hidden': false,
      'subCategories': [
        {
          'id': '201',
          'name': '食品',
          'parentId': '200',
          'type': 2,
          'icon': '2',
          'iconType': 0,
          'color': 'E8A33D',
          'comment': '',
          'hidden': false,
        },
      ],
    },
  ],
};

/// 返回当前时间往回 6 个月的年月列表（趋势图 fixture）
List<Map<String, dynamic>> _trendJson() {
  final now = DateTime.now();
  return [
    for (var i = 5; i >= 0; i--)
      {
        'year': DateTime(now.year, now.month - i, 1).year,
        'month': DateTime(now.year, now.month - i, 1).month,
        'items': [
          {'categoryId': '100', 'accountId': '7', 'amount': '5000'},
          {'categoryId': '201', 'accountId': '7', 'amount': '2000'},
        ],
      },
  ];
}

/// 近 3 天（今天收尾）的资产余额
List<Map<String, dynamic>> _assetJson() {
  final now = DateTime.now();
  return [
    for (var i = 2; i >= 0; i--)
      {
        'year': DateTime(now.year, now.month, now.day - i).year,
        'month': DateTime(now.year, now.month, now.day - i).month,
        'day': DateTime(now.year, now.month, now.day - i).day,
        'items': [
          {
            'accountId': '7',
            'accountOpeningBalance': '0',
            'accountClosingBalance': '${1000 * (3 - i)}',
          },
        ],
      },
  ];
}

FakeHttpAdapter _adapter({bool empty = false}) =>
    FakeHttpAdapter((path, body) {
      if (path.endsWith('/accounts/list.json')) return ok([_accountJson]);
      if (path.endsWith('/transaction/categories/list.json')) {
        return ok(_categoriesJson);
      }
      if (path.endsWith('/users/profile/get.json')) {
        return ok({
          'username': 'admin',
          'language': 'zh-CN',
          'defaultCurrency': 'CNY',
        });
      }
      if (path.endsWith('/exchange_rates/latest.json')) {
        return ok({
          'baseCurrency': 'CNY',
          'exchangeRates': [
            {'currency': 'CNY', 'rate': '1'},
          ],
        });
      }
      if (path.endsWith('/transactions/statistics.json')) {
        return ok({
          'startTime': 0,
          'endTime': 0,
          'items': empty
              ? <dynamic>[]
              : [
                  {
                    'categoryId': '201',
                    'accountId': '7',
                    'amount': '1234',
                  },
                  {
                    'categoryId': '100',
                    'accountId': '7',
                    'amount': '5678',
                  },
                ],
        });
      }
      if (path.endsWith('/transactions/statistics/trends.json')) {
        return ok(empty ? <dynamic>[] : _trendJson());
      }
      if (path.endsWith('/transactions/statistics/asset_trends.json')) {
        return ok(empty ? <dynamic>[] : _assetJson());
      }
      return ok(null);
    });

ProviderContainer _container(FakeHttpAdapter adapter) {
  final client = ApiClient(
    baseUrl: 'https://fake.test',
    tokenStore: TokenStore(),
  );
  client.dio.httpClientAdapter = adapter;

  return ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      tokenStoreProvider.overrideWithValue(TokenStore()),
    ],
  );
}

Future<void> _pump(WidgetTester tester, FakeHttpAdapter adapter) async {
  // 饼图 230px + 图例行，窄屏会把右侧百分比挤出去
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final container = _container(adapter);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: StatisticsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

int _callsTo(FakeHttpAdapter adapter, String path) =>
    adapter.calls.where((c) => c.path.endsWith(path)).length;

void main() {
  testWidgets('分类占比：默认支出视图，按一级分类汇总', (tester) async {
    final adapter = _adapter();
    await _pump(tester, adapter);

    // 支出 1234 分 → 合计 12.34，归并到一级分类「食品饮料」
    expect(find.textContaining('支出合计'), findsOneWidget);
    expect(find.text('12.34'), findsOneWidget, reason: '图例里的合计金额');
    expect(find.text('食品饮料'), findsOneWidget);
    expect(find.text('工资'), findsNothing, reason: '收入分类不进支出口径');

    final query = adapter
        .lastCallFor('/transactions/statistics.json')
        .uri
        .queryParameters;
    expect(RegExp(r'^\d+$').hasMatch(query['start_time'] ?? ''), isTrue);
    expect(RegExp(r'^\d+$').hasMatch(query['end_time'] ?? ''), isTrue);

    // 切「收入」→ 同一端点重新拉，展示收入口径
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('收入合计'), findsOneWidget);
    expect(find.text('56.78'), findsOneWidget, reason: '图例里的合计金额');
    expect(find.text('工资'), findsOneWidget);
    expect(find.text('食品饮料'), findsNothing);
    // 支出/收入共用同一次 statistics.json 结果（区间没变就不重复拉），
    // 所以这里只断言视图切换正确，重复请求的断言放在「切区间」那条用例里
  });

  testWidgets('切区间：本月 → 今年，饼图按新区间重新拉', (tester) async {
    final adapter = _adapter();
    await _pump(tester, adapter);

    await tester.tap(find.text('今年'));
    await tester.pumpAndSettle();

    expect(_callsTo(adapter, '/transactions/statistics.json'), 2);

    final first = adapter.calls
        .where((c) => c.path.endsWith('/transactions/statistics.json'))
        .toList()
        .first
        .uri
        .queryParameters;
    final last = adapter.lastCallFor('/transactions/statistics.json')
        .uri
        .queryParameters;
    expect(
      int.parse(last['start_time']!) < int.parse(first['start_time']!),
      isTrue,
      reason: '今年的起点比本月更早',
    );
  });

  testWidgets('收支趋势：走 trends.json，年月区间格式 2026-01', (tester) async {
    final adapter = _adapter();
    await _pump(tester, adapter);

    await tester.tap(find.text('收支趋势'));
    await tester.pumpAndSettle();

    final query = adapter
        .lastCallFor('/transactions/statistics/trends.json')
        .uri
        .queryParameters;
    expect(
      RegExp(r'^\d{4}-\d{2}$').hasMatch(query['start_year_month'] ?? ''),
      isTrue,
    );
    expect(
      RegExp(r'^\d{4}-\d{2}$').hasMatch(query['end_year_month'] ?? ''),
      isTrue,
    );

    // 图例 + x 轴刻度（当前月）+ 区间起点说明
    expect(find.text('收入'), findsWidgets);
    expect(find.text('支出'), findsWidgets);
    expect(find.text('${DateTime.now().month}月'), findsWidgets);
    expect(find.textContaining('起'), findsOneWidget);
  });

  testWidgets('资产趋势：走 asset_trends.json，画净资产折线', (tester) async {
    final adapter = _adapter();
    await _pump(tester, adapter);

    await tester.tap(find.text('资产趋势'));
    await tester.pumpAndSettle();

    expect(adapter.lastCallFor('/transactions/statistics/asset_trends.json'),
        isNotNull);
    expect(find.text('净资产'), findsOneWidget);
    expect(find.textContaining('截至'), findsOneWidget);
    // 结转补齐后 3 天 → 3 个日期刻度
    final dateLabels = find.textContaining('/');
    expect(dateLabels, findsWidgets);
  });

  testWidgets('区间没数据给空态，不白屏也不转圈', (tester) async {
    final adapter = _adapter(empty: true);
    await _pump(tester, adapter);

    expect(find.text('该区间还没有支出记录'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('收支趋势'));
    await tester.pumpAndSettle();
    expect(find.text('该区间没有记录'), findsOneWidget);
  });
}
