/// 汇率页冒烟：列表（基准货币 / 数据来源 / 更新时间）、换算小工具按
/// `ExchangeRates.convert` 出结果、刷新会重新请求；空数据给空态。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebk_mobile/core/network/api_client.dart';
import 'package:ebk_mobile/core/storage/token_store.dart';
import 'package:ebk_mobile/features/exchange_rates/exchange_rates_screen.dart';

import 'fakes.dart';

FakeHttpAdapter _adapter({bool empty = false}) =>
    FakeHttpAdapter((path, body) {
      if (path.endsWith('/exchange_rates/latest.json')) {
        return ok({
          'dataSource': 'European Central Bank',
          'referenceUrl': 'https://www.ecb.europa.eu/',
          'updateTime': 1791208800,
          'baseCurrency': 'EUR',
          'exchangeRates': empty
              ? <dynamic>[]
              : [
                  {'currency': 'EUR', 'rate': '1'},
                  {'currency': 'CNY', 'rate': '7.5118'},
                  {'currency': 'USD', 'rate': '1.0813'},
                ],
        });
      }
      return ok(null);
    });

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeHttpAdapter adapter,
) async {
  final client = ApiClient(
    baseUrl: 'https://fake.test',
    tokenStore: TokenStore(),
  );
  client.dio.httpClientAdapter = adapter;

  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      tokenStoreProvider.overrideWithValue(TokenStore()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ExchangeRatesScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

int _calls(FakeHttpAdapter adapter) =>
    adapter.calls.where((c) => c.path.endsWith('/exchange_rates/latest.json')).length;

void main() {
  testWidgets('列表：基准货币、数据来源、更新时间与逐条汇率', (tester) async {
    final adapter = _adapter();
    await _pump(tester, adapter);

    expect(find.text('基准货币 EUR'), findsOneWidget);
    expect(find.textContaining('European Central Bank'), findsOneWidget);
    expect(find.textContaining('202'), findsWidgets, reason: '更新时间带年份');
    expect(find.text('1 EUR = 7.5118 CNY'), findsOneWidget);
    expect(find.text('1 EUR = 1.0813 USD'), findsOneWidget);
    expect(find.text('1 EUR = 1 EUR'), findsOneWidget, reason: '基准自身 rate=1');
  });

  testWidgets('换算：默认 1 EUR → CNY，改金额与币种实时出结果', (tester) async {
    final adapter = _adapter();
    await _pump(tester, adapter);

    // 初始：1.00 EUR = 7.51 CNY（100 分 × 7.5118 / 1 = 751 分）
    expect(find.text('1.00 EUR = 7.51 CNY'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '100');
    await tester.pumpAndSettle();
    expect(find.text('100.00 EUR = 751.18 CNY'), findsOneWidget);

    // 源币种换成 USD：100 USD = 100 × 7.5118 / 1.0813 = 694.69 CNY
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownMenuItem<String>, 'USD').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('100.00 USD = '), findsOneWidget);
    expect(find.textContaining('CNY'), findsWidgets);
  });

  testWidgets('刷新按钮重新拉一次汇率', (tester) async {
    final adapter = _adapter();
    await _pump(tester, adapter);
    expect(_calls(adapter), 1);

    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(_calls(adapter), 2);
  });

  testWidgets('服务端没有汇率 → 空态', (tester) async {
    await _pump(tester, _adapter(empty: true));

    expect(find.text('服务端没有可用的汇率数据'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
