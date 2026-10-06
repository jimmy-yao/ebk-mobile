/// `TransactionRepository.get()` 对服务端缺陷的兜底回归。
///
/// 背景（实测 ezBookkeeping 2.0.1）：「调整余额」(type=1) 的 categoryId 恒为 0，
/// `TransactionGetHandler` 不带 `trim_category=true` 就拿它查分类
/// （pkg/services/transaction_categories.go:121 `categoryId <= 0` 早退），
/// 于是 `get.json?id=<调整余额>` 必回 `400 206000 transaction category id is invalid`
/// —— 真机上就是"详情页弹 App exception(400 206000)"这个 bug。
///
/// 三个用例各钉一件事：该兜的兜、正常路径不多打一发、别的错误不吞。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ebk_mobile/core/error/app_exception.dart';
import 'package:ebk_mobile/core/network/api_client.dart';
import 'package:ebk_mobile/core/storage/token_store.dart';
import 'package:ebk_mobile/data/repositories/transaction_repository.dart';

import 'fakes.dart';

const _adjustTx = <String, dynamic>{
  'id': '10',
  'type': 1,
  'categoryId': '0',
  'time': 1760000000,
  'utcOffset': 480,
  'sourceAccountId': '1',
  'sourceAccount': {'id': '1', 'name': '现金钱包', 'currency': 'CNY'},
  'destinationAccountId': '0',
  'sourceAmount': 5000,
  'destinationAmount': 0,
  'hideAmount': false,
  'tagIds': <String>[],
  'tags': <dynamic>[],
  'comment': '',
  'editable': true,
};

const _expenseTx = <String, dynamic>{
  'id': '9',
  'type': 3,
  'categoryId': '201',
  'category': {
    'id': '201',
    'name': '食品',
    'color': 'E8A33D',
    'icon': '2',
    'iconType': 0,
  },
  'time': 1760000000,
  'utcOffset': 480,
  'sourceAccountId': '1',
  'sourceAccount': {'id': '1', 'name': '现金钱包', 'currency': 'CNY'},
  'destinationAccountId': '0',
  'sourceAmount': 1234,
  'destinationAmount': 0,
  'hideAmount': false,
  'tagIds': <String>[],
  'tags': <dynamic>[],
  'comment': '午饭',
  'editable': true,
};

ApiClient _client(FakeHttpAdapter adapter) {
  final client = ApiClient(
    baseUrl: 'https://fake.test',
    tokenStore: TokenStore(),
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

void main() {
  test('调整余额：首次 400/206000 → 自动带 trim_category 重取', () async {
    var getCalls = 0;
    final adapter = FakeHttpAdapter((path, body) {
      if (path.endsWith('/transactions/get.json')) {
        getCalls++;
        if (getCalls == 1) {
          // 服务端原样错误形态（HTTP 400 由假 adapter 按 success=false 推导）
          return <String, dynamic>{
            'success': false,
            'errorCode': 206000,
            'errorMessage': 'transaction category id is invalid',
          };
        }
        return ok(_adjustTx);
      }
      return ok(null);
    });
    final repo = TransactionRepository(_client(adapter));

    final tx = await repo.get('10');

    expect(tx, isNotNull);
    expect(tx!.type, 1);
    expect(tx.category, isNull, reason: '调整余额本来就没有分类，null 才是对的');
    expect(tx.sourceAccount, isNotNull, reason: '账户不受 trim 影响，只读视图要用');
    expect(tx.sourceAmount, 5000);
    expect(getCalls, 2, reason: '400 之后必须补一发带 trim 的请求');
    expect(
      adapter.calls[0].uri.queryParameters.containsKey('trim_category'),
      isFalse,
      reason: '先按正常契约取（category 对普通明细是必需的）',
    );
    expect(
      adapter.calls[1].uri.queryParameters['trim_category'],
      'true',
      reason: '兜底那一发必须带 trim_category=true 才能绕开服务端缺陷',
    );
  });

  test('普通支出：一次拿到、带出 category，不触发兜底', () async {
    final adapter = FakeHttpAdapter((path, body) {
      if (path.endsWith('/transactions/get.json')) return ok(_expenseTx);
      return ok(null);
    });
    final repo = TransactionRepository(_client(adapter));

    final tx = await repo.get('9');

    expect(tx, isNotNull);
    expect(tx!.type, 3);
    expect(tx.category?.name, '食品', reason: '普通明细仍要拿到分类');
    expect(adapter.calls, hasLength(1), reason: '不该多打一发');
    expect(
      adapter.calls[0].uri.queryParameters.containsKey('trim_category'),
      isFalse,
    );
  });

  test('非 206000 的错误原样抛出（不做"什么都吞"的兜底）', () async {
    final adapter = FakeHttpAdapter((path, body) {
      if (path.endsWith('/transactions/get.json')) {
        return <String, dynamic>{
          'success': false,
          'errorCode': 206001,
          'errorMessage': 'transaction category not found',
        };
      }
      return ok(null);
    });
    final repo = TransactionRepository(_client(adapter));

    await expectLater(
      repo.get('404'),
      throwsA(isA<AppException>()
          .having((e) => e.code, 'code', '206001')
          .having((e) => e.statusCode, 'statusCode', 400)),
    );
    expect(adapter.calls, hasLength(1), reason: '非目标错误码不得重试');
  });
}
