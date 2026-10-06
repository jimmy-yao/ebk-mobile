/// 明细列表的搜索 / 筛选界面冒烟：关键词走 `keyword+match_mode=1`，
/// 类型・账户・分类走 `type` / `account_ids` / `category_ids`（一级自动展开）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebk_mobile/core/network/api_client.dart';
import 'package:ebk_mobile/core/storage/token_store.dart';
import 'package:ebk_mobile/features/transactions/transactions_screen.dart';

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
  'balance': '0',
  'comment': '',
  'displayOrder': 1,
  'hidden': false,
};

final _categoriesJson = <String, dynamic>{
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

FakeHttpAdapter _adapter() => FakeHttpAdapter((path, body) {
      if (path.endsWith('/accounts/list.json')) return ok([_accountJson]);
      if (path.endsWith('/transaction/categories/list.json')) {
        return ok(_categoriesJson);
      }
      if (path.endsWith('/transaction/tags/list.json')) return ok([]);
      if (path.endsWith('/transactions/list/by_month.json')) {
        return ok({'items': <dynamic>[], 'totalCount': 0});
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

/// 最近一次按月列表请求的 query
Map<String, String> _queryOf(FakeHttpAdapter adapter) => adapter
    .lastCallFor('/transactions/list/by_month.json')
    .uri
    .queryParameters;

void main() {
  testWidgets('关键词搜索：keyword + match_mode=1，条件以 Chip 展示可删', (tester) async {
    final adapter = _adapter();
    // 给测试面更高的屏幕：筛选弹层 maxHeight = 75% 屏高，
    // 默认 800x600 会把分类那一段裁到列表可视区外
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
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('这个月还没有记录'), findsOneWidget);

    // 打开搜索框
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '午饭');
    // suffixIcon 上的搜索按钮 = 提交
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    final query = _queryOf(adapter);
    expect(query['keyword'], '午饭');
    expect(query['match_mode'], '1');
    expect(query.containsKey('type'), isFalse);
    expect(find.text('搜索：午饭'), findsOneWidget);
    expect(find.text('没有匹配的记录'), findsOneWidget);

    // 删掉这个条件 → keyword 不再出现
    final chip = find.widgetWithText(Chip, '搜索：午饭');
    expect(chip, findsOneWidget);
    // Chip 的删除图标是 Icons.cancel（不是 close）
    await tester.tap(find.descendant(of: chip, matching: find.byType(Icon)));
    await tester.pumpAndSettle();
    expect(_queryOf(adapter).containsKey('keyword'), isFalse);
    expect(find.text('这个月还没有记录'), findsOneWidget);
  });

  testWidgets('筛选弹层：选类型支出 → type=3；账户 → account_ids', (tester) async {
    final adapter = _adapter();
    // 给测试面更高的屏幕：筛选弹层 maxHeight = 75% 屏高，
    // 默认 800x600 会把分类那一段裁到列表可视区外
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
        child: const MaterialApp(home: TransactionsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('类型'), findsOneWidget);

    // ChoiceChip 的 label 会被渲染两次，取第一个（都在同一个 chip 里）
    await tester.tap(find.widgetWithText(ChoiceChip, '支出').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '现金钱包').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '应用'));
    await tester.pumpAndSettle();

    final query = _queryOf(adapter);
    expect(query['type'], '3', reason: '支出 = 3');
    expect(query['account_ids'], '7');
    expect(query.containsKey('category_ids'), isFalse);
    expect(find.text('类型：支出'), findsOneWidget);
    expect(find.text('账户：现金钱包'), findsOneWidget);

    // 弹层里选一级分类 → category_ids 传的是**一级** id（服务端展开子分类）
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '食品饮料').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '应用'));
    await tester.pumpAndSettle();
    expect(_queryOf(adapter)['category_ids'], '200');

    // 一键清空
    await tester.tap(find.widgetWithText(ActionChip, '清空'));
    await tester.pumpAndSettle();
    final cleared = _queryOf(adapter);
    expect(cleared.containsKey('type'), isFalse);
    expect(cleared.containsKey('account_ids'), isFalse);
    expect(cleared.containsKey('category_ids'), isFalse);
    expect(find.text('类型：支出'), findsNothing);
  });
}
