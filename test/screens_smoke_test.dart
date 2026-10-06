/// 界面级冒烟：页面能渲染、不抛异常；并完整走一遍"填表 → 提交 → 返回"，
/// 顺带断言真正发出的 payload（账户编辑不得携带 balance）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ebk_mobile/core/network/api_client.dart';
import 'package:ebk_mobile/core/storage/token_store.dart';
import 'package:ebk_mobile/features/accounts/account_edit_screen.dart';
import 'package:ebk_mobile/features/accounts/accounts_screen.dart';
import 'package:ebk_mobile/features/transactions/transaction_edit_screen.dart';

import 'fakes.dart';

const _accountJson = <String, dynamic>{
  'id': '1',
  'name': '现金钱包',
  'parentId': '0',
  'category': 1,
  'type': 1,
  'icon': '1',
  'iconType': 0,
  'color': '3B7DD8',
  'currency': 'CNY',
  'balance': '1234',
  'comment': '零钱',
  'displayOrder': 1,
  'hidden': false,
};

const _categoriesJson = <String, dynamic>{
  '2': [
    {
      'id': '200',
      'name': '食品饮料',
      'type': 2,
      'parentId': '0',
      'hidden': false,
      'subCategories': [
        {
          'id': '201',
          'name': '食品',
          'type': 2,
          'parentId': '200',
          'hidden': false,
        },
      ],
    },
  ],
  '3': [
    {
      'id': '300',
      'name': '一般转账',
      'type': 3,
      'parentId': '0',
      'hidden': false,
      'subCategories': [
        {
          'id': '301',
          'name': '银行转账',
          'type': 3,
          'parentId': '300',
          'hidden': false,
        },
      ],
    },
  ],
};

const _expenseTxJson = <String, dynamic>{
  'id': '9',
  'type': 3,
  'categoryId': '201',
  'time': 1760000000,
  'utcOffset': 480,
  'sourceAccountId': '1',
  'destinationAccountId': '0',
  'sourceAmount': 1234,
  'destinationAmount': 0,
  'hideAmount': false,
  'comment': '午饭',
  'tags': [],
};

const _adjustTxJson = <String, dynamic>{
  'id': '10',
  'type': 1, // 调整余额：categoryId 必须为 0，App 只给看+删
  'categoryId': '0',
  'time': 1760000000,
  'utcOffset': 480,
  'sourceAccountId': '1',
  'destinationAccountId': '0',
  'sourceAmount': 5000,
  'destinationAmount': 0,
  'hideAmount': false,
  'comment': '',
  'tags': [],
};

FakeHttpAdapter _adapter() => FakeHttpAdapter((path, body) {
      if (path.endsWith('/accounts/list.json')) return ok([_accountJson]);
      if (path.endsWith('/accounts/get.json')) return ok(_accountJson);
      if (path.endsWith('/transaction/categories/list.json')) {
        return ok(_categoriesJson);
      }
      if (path.endsWith('/transaction/tags/list.json')) return ok([]);
      if (path.endsWith('/exchange_rates/latest.json')) {
        return ok({
          'dataSource': 'test',
          'baseCurrency': 'EUR',
          'exchangeRates': [
            {'currency': 'EUR', 'rate': '1'},
            {'currency': 'CNY', 'rate': '7.5'},
          ],
        });
      }
      if (path.endsWith('/transactions/get.json')) return ok(_expenseTxJson);
      if (path.endsWith('/accounts/add.json')) return ok({'id': '2'});
      if (path.endsWith('/accounts/modify.json')) return ok(true);
      if (path.endsWith('/transactions/add.json')) return ok({'id': '99'});
      return ok(null);
    });

ApiClient _client(FakeHttpAdapter adapter) {
  final client = ApiClient(
    baseUrl: 'https://fake.test',
    tokenStore: TokenStore(),
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

ProviderContainer _container(FakeHttpAdapter adapter) => ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(_client(adapter)),
        tokenStoreProvider.overrideWithValue(TokenStore()),
      ],
    );

void main() {
  testWidgets('账户页：余额按最小单位格式化、FAB 就位', (tester) async {
    final container = _container(_adapter());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AccountsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('现金钱包'), findsOneWidget);
    expect(find.text('12.34'), findsOneWidget,
        reason: 'balance="1234" 是最小单位，展示要除 100');
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('零钱'), findsOneWidget);
  });

  testWidgets('记账表单：三段类型 + 只给子分类 + 底部记账按钮', (tester) async {
    final container = _container(_adapter());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TransactionEditScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('记一笔'), findsOneWidget);
    for (final label in ['支出', '收入', '转账']) {
      expect(find.text(label), findsOneWidget, reason: '$label 段');
    }
    expect(find.text('支出分类'), findsOneWidget);
    expect(find.text('食品'), findsOneWidget, reason: '子分类可选');
    expect(find.text('银行转账'), findsNothing,
        reason: '转账子分类不应出现在支出分类里');

    // 滚到底，确保整页（标签/备注/按钮）渲染无异常
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('记账'), findsOneWidget);
  });

  testWidgets('编辑支出：金额原样回填 12.34', (tester) async {
    final container = _container(_adapter());
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: TransactionEditScreen(transactionId: '9'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('编辑记录'), findsOneWidget);
    expect(find.text('12.34'), findsOneWidget);
    expect(find.text('午饭'), findsOneWidget);
    expect(find.text('食品'), findsOneWidget);
  });

  testWidgets('调整余额明细：只读视图，没有记账按钮', (tester) async {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(
          _client(FakeHttpAdapter((path, body) {
            if (path.endsWith('/accounts/list.json')) return ok([_accountJson]);
            if (path.endsWith('/transaction/categories/list.json')) {
              return ok(_categoriesJson);
            }
            if (path.endsWith('/transaction/tags/list.json')) return ok([]);
            if (path.endsWith('/transactions/get.json')) return ok(_adjustTxJson);
            return ok(null);
          })),
        ),
        tokenStoreProvider.overrideWithValue(TokenStore()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: TransactionEditScreen(transactionId: '10'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('余额调整记录'), findsOneWidget);
    expect(find.text('删除这条记录'), findsOneWidget);
    expect(find.text('记账'), findsNothing);
  });

  testWidgets('新建账户：填表提交 → payload 不含 balance → 返回上一页',
      (tester) async {
    final adapter = _adapter();
    final container = _container(adapter);
    addTearDown(container.dispose);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const SizedBox()),
        GoRoute(
          path: '/accounts/new',
          builder: (context, state) => const AccountEditScreen(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.push('/accounts/new');
    await tester.pumpAndSettle();
    expect(find.text('新建账户'), findsOneWidget);

    // 名称（第一个输入框）
    await tester.enterText(find.byType(TextField).first, '我的钱包');
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('创建账户'));
    await tester.pumpAndSettle();

    final call = adapter.lastCallFor('/accounts/add.json');
    expect(call.body!['name'], '我的钱包');
    expect(call.body!['category'], 1);
    expect(call.body!['type'], 1);
    expect(call.body!.containsKey('balance'), isFalse,
        reason: '没填余额就不该发 balance（发了就得带 balanceTime）');
    expect(router.canPop(), isFalse, reason: '提交成功后应返回上一页');
  });
}
