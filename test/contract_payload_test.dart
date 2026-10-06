/// 仓库层 **payload 契约测试**：断言真正发出去的 JSON 字段，
/// 全部对应 `scripts/smoke.sh --crud` 实测踩过的坑（见方案文档 §1）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ebk_mobile/core/network/api_client.dart';
import 'package:ebk_mobile/core/storage/token_store.dart';
import 'package:ebk_mobile/data/repositories/account_repository.dart';
import 'package:ebk_mobile/data/repositories/category_repository.dart';
import 'package:ebk_mobile/data/repositories/exchange_rate_repository.dart';
import 'package:ebk_mobile/data/repositories/statistics_repository.dart';
import 'package:ebk_mobile/data/repositories/transaction_repository.dart';
import 'package:ebk_mobile/data/repositories/user_repository.dart';

import 'fakes.dart';

ApiClient _clientWith(FakeHttpAdapter adapter) {
  final client = ApiClient(
    baseUrl: 'https://fake.test',
    tokenStore: TokenStore(),
  );
  client.dio.httpClientAdapter = adapter;
  return client;
}

void main() {
  group('TransactionRepository payload', () {
    test('listByMonth：过滤参数与 match_mode 拼法', () async {
      final adapter = FakeHttpAdapter(
        (path, body) => ok({'items': <dynamic>[], 'totalCount': 0}),
      );
      final repo = TransactionRepository(_clientWith(adapter));

      await repo.listByMonth(
        year: 2026,
        month: 10,
        type: 3,
        keyword: 'Lunch',
        categoryIds: '200',
        accountIds: '7,8',
      );

      final q = adapter
          .lastCallFor('/transactions/list/by_month.json')
          .uri
          .queryParameters;
      expect(q['year'], '2026');
      expect(q['month'], '10');
      expect(q['type'], '3');
      expect(q['keyword'], 'Lunch');
      expect(q['match_mode'], '1', reason: '忽略大小写（0 会区分大小写）');
      expect(q['category_ids'], '200', reason: '传一级 id，服务端展开成子分类');
      expect(q['account_ids'], '7,8', reason: '逗号分隔');
      expect(q['trim_account'], 'true');
    });

    test('listByMonth：不加过滤时不发 type/keyword 键', () async {
      final adapter = FakeHttpAdapter(
        (path, body) => ok({'items': <dynamic>[], 'totalCount': 0}),
      );
      final repo = TransactionRepository(_clientWith(adapter));

      await repo.listByMonth(year: 2026, month: 10);

      final q = adapter
          .lastCallFor('/transactions/list/by_month.json')
          .uri
          .queryParameters;
      expect(q.containsKey('type'), isFalse);
      expect(q.containsKey('keyword'), isFalse);
      expect(q.containsKey('category_ids'), isFalse);
      expect(q.containsKey('account_ids'), isFalse);
    });

    test('add 支出：id 全是字符串、金额为正、非转账 destinationAmount=0', () async {
      final adapter = FakeHttpAdapter((path, body) => ok({'id': '9'}));
      final repo = TransactionRepository(_clientWith(adapter));

      await repo.add(const TxDraft(
        type: 3, // 支出
        categoryId: '201', // 子分类 id（一级分类会被 206005 拒）
        time: 1760000000,
        utcOffset: 480, // 东向为正
        sourceAccountId: '7',
        sourceAmount: 1234, // 正的最小单位
        comment: '午饭',
      ));

      final call = adapter.lastCallFor('/transactions/add.json');
      expect(call.method, 'POST');
      expect(call.body, isNotNull);
      final body = call.body!;
      expect(body['type'], 3);
      expect(body['categoryId'], '201', reason: 'categoryId 必须是字符串化 int64');
      expect(body['sourceAccountId'], '7');
      expect(body['destinationAccountId'], '0');
      expect(body['sourceAmount'], 1234, reason: '支出传正数，服务端自己扣');
      expect(body['destinationAmount'], 0, reason: '非转账传 0，否则 206004');
      expect(body['time'], 1760000000);
      expect(body['utcOffset'], 480);
      expect(body['tagIds'], isEmpty);
      expect(body['pictureIds'], isEmpty);
      expect(body['comment'], '午饭');
      expect(body['hideAmount'], isFalse);
    });

    test('modify 比 add 只多一个 id', () async {
      final adapter = FakeHttpAdapter((path, body) => ok({'id': '9'}));
      final repo = TransactionRepository(_clientWith(adapter));

      await repo.modify(
        id: '9',
        draft: const TxDraft(
          type: 4,
          categoryId: '301',
          time: 1760000000,
          utcOffset: -330,
          sourceAccountId: '7',
          sourceAmount: 500,
          destinationAccountId: '8',
          destinationAmount: 500,
        ),
      );

      final body = adapter.lastCallFor('/transactions/modify.json').body!;
      expect(body['id'], '9');
      expect(body['type'], 4);
      expect(body['destinationAccountId'], '8');
      expect(body['destinationAmount'], 500, reason: '同币种转账两者相等');
      expect(body['utcOffset'], -330, reason: '西向为负，范围 -720..840');
    });

    test('delete 只发 {id}', () async {
      final adapter = FakeHttpAdapter((path, body) => ok(true));
      final repo = TransactionRepository(_clientWith(adapter));

      await repo.remove('9');

      final call = adapter.lastCallFor('/transactions/delete.json');
      expect(call.body, {'id': '9'});
    });
  });

  group('AccountRepository payload', () {
    test('新建带初始余额 → 必须同时给 balanceTime（否则 204015）', () async {
      final adapter = FakeHttpAdapter((path, body) => ok({'id': '1'}));
      final repo = AccountRepository(_clientWith(adapter));

      await repo.add(
        name: '钱包',
        category: 1,
        icon: 1,
        iconType: 0,
        color: '3B7DD8',
        currency: 'CNY',
        balance: 500,
        comment: '零钱',
      );

      final body = adapter.lastCallFor('/accounts/add.json').body!;
      expect(body['name'], '钱包');
      expect(body['category'], 1);
      expect(body['type'], 1, reason: 'MVP 只建单账户');
      expect(body['icon'], '1', reason: 'icon 是字符串化 int64');
      expect(body['iconType'], 0);
      expect(body['color'], '3B7DD8', reason: '6 位不带 #');
      expect(body['currency'], 'CNY');
      expect(body['balance'], '500');
      expect(body['balanceTime'], isA<int>());
      expect(body['balanceTime'] as int, greaterThan(0));
    });

    test('新建不填余额 → 一个 balance 键都不发（发了就得带 balanceTime）', () async {
      final adapter = FakeHttpAdapter((path, body) => ok({'id': '1'}));
      final repo = AccountRepository(_clientWith(adapter));

      await repo.add(
        name: '钱包',
        category: 1,
        icon: 1,
        iconType: 0,
        color: '3B7DD8',
        currency: 'CNY',
      );

      final body = adapter.lastCallFor('/accounts/add.json').body!;
      expect(body.containsKey('balance'), isFalse);
      expect(body.containsKey('balanceTime'), isFalse);
    });

    test('编辑绝不带 balance/balanceTime（带了报 204021）', () async {
      final adapter = FakeHttpAdapter((path, body) => ok(true));
      final repo = AccountRepository(_clientWith(adapter));

      await repo.modify(
        id: '1',
        name: '钱包改名',
        category: 4,
        icon: 100,
        iconType: 0,
        color: '1F9D55',
        currency: 'CNY',
        comment: '备注',
        hidden: true,
      );

      final body = adapter.lastCallFor('/accounts/modify.json').body!;
      expect(body['id'], '1');
      expect(body['name'], '钱包改名');
      expect(body['category'], 4);
      expect(body['currency'], 'CNY');
      expect(body['hidden'], isTrue);
      expect(body.containsKey('balance'), isFalse,
          reason: '服务端见 balance 键就报 not supported to modify account balance');
      expect(body.containsKey('balanceTime'), isFalse);
    });

    test('hide 发 {id, hidden}；列表过滤参数是 visible_only', () async {
      final adapter = FakeHttpAdapter((path, body) => ok([]));
      final repo = AccountRepository(_clientWith(adapter));

      await repo.hide('1', true);
      final hideBody = adapter.lastCallFor('/accounts/hide.json').body!;
      expect(hideBody, {'id': '1', 'hidden': true});

      await repo.list(withHidden: false);
      final listCall = adapter.lastCallFor('/accounts/list.json');
      expect(listCall.uri.queryParameters['visible_only'], 'true');
      expect(listCall.uri.queryParameters.containsKey('with_hidden'), isFalse,
          reason: 'with_hidden 是无效参数，服务端会忽略');
    });
  });

  group('CategoryRepository payload（分类）', () {
    test('新建：icon/parentId 字符串化、带 type，且**不带 hidden**', () async {
      final adapter = FakeHttpAdapter((path, body) => ok({'id': '200'}));
      final repo = CategoryRepository(_clientWith(adapter));

      await repo.addCategory(
        name: '房租水电',
        type: 2,
        parentId: '0',
        icon: 200,
        color: '3B7DD8',
        comment: '每月固定',
      );

      final body = adapter.lastCallFor('/categories/add.json').body!;
      expect(body['name'], '房租水电');
      expect(body['type'], 2, reason: '类型必须显式给（required，0 会被拒）');
      expect(body['parentId'], '0', reason: 'json:",string" → 必须是字符串');
      expect(body['icon'], '200', reason: '同上，发数字会 400');
      expect(body['iconType'], 0);
      expect(body['color'], '3B7DD8');
      expect(body['comment'], '每月固定');
      expect(body.containsKey('hidden'), isFalse,
          reason: '创建请求没有 hidden 字段，新分类一定可见');
      expect(body.containsKey('type') && body.containsKey('id'), isFalse);
    });

    test('二级分类：parentId 指向一级 id', () async {
      final adapter = FakeHttpAdapter((path, body) => ok({'id': '201'}));
      final repo = CategoryRepository(_clientWith(adapter));

      await repo.addCategory(
        name: '物业费',
        type: 2,
        parentId: '200',
        icon: 210,
        color: '2F9E44',
      );

      final body = adapter.lastCallFor('/categories/add.json').body!;
      expect(body['parentId'], '200');
      expect(body['type'], 2, reason: '子分类类型必须与父分类一致（206002）');
    });

    test('修改：**没有 type 键**，parentId 原样回传（层级不可改）', () async {
      final adapter = FakeHttpAdapter((path, body) => ok(true));
      final repo = CategoryRepository(_clientWith(adapter));

      await repo.modifyCategory(
        id: '201',
        name: '房租水电（改）',
        parentId: '200',
        icon: 210,
        color: '2F9E44',
        comment: '备注',
        hidden: true,
      );

      final body = adapter.lastCallFor('/categories/modify.json').body!;
      expect(body['id'], '201');
      expect(body['name'], '房租水电（改）');
      expect(body['parentId'], '200');
      expect(body['hidden'], isTrue);
      expect(body.containsKey('type'), isFalse,
          reason: 'TransactionCategoryModifyRequest 没有 type 字段');
      expect(body['icon'], '210');
      expect(body['color'], '2F9E44');
    });

    test('hide 与 delete 的请求体', () async {
      final adapter = FakeHttpAdapter((path, body) => ok(true));
      final repo = CategoryRepository(_clientWith(adapter));

      await repo.hideCategory('201', true);
      expect(adapter.lastCallFor('/categories/hide.json').body,
          {'id': '201', 'hidden': true});

      await repo.removeCategory('200');
      final del = adapter.lastCallFor('/categories/delete.json').body!;
      expect(del, {'id': '200'});
      expect(del.containsKey('withChildren'), isFalse,
          reason: '子分类是服务端连带软删的，请求体只有 id');
    });
  });

  group('标签 payload（CategoryRepository 内的 tag 方法）', () {
    test('新建标签只有 groupId + name，**没有 color**', () async {
      final adapter = FakeHttpAdapter((path, body) => ok({'id': '7'}));
      final repo = CategoryRepository(_clientWith(adapter));

      await repo.addTag(name: '日常');

      final body = adapter.lastCallFor('/tags/add.json').body!;
      expect(body, {'groupId': '0', 'name': '日常'});
    });

    test('改名带 id + 原 groupId', () async {
      final adapter = FakeHttpAdapter((path, body) => ok(true));
      final repo = CategoryRepository(_clientWith(adapter));

      await repo.modifyTag(id: '7', name: '旅行', groupId: '0');

      expect(adapter.lastCallFor('/tags/modify.json').body,
          {'id': '7', 'groupId': '0', 'name': '旅行'});
    });

    test('hide / delete 只发 id（hide 多一个 hidden）', () async {
      final adapter = FakeHttpAdapter((path, body) => ok(true));
      final repo = CategoryRepository(_clientWith(adapter));

      await repo.hideTag('7', true);
      expect(adapter.lastCallFor('/tags/hide.json').body,
          {'id': '7', 'hidden': true});

      await repo.removeTag('7');
      expect(adapter.lastCallFor('/tags/delete.json').body, {'id': '7'});
    });
  });

  group('分类列表：按 type 分组的 map 拍平', () {
    test('subCategories 字段 + map 结构都能解析', () async {
      final adapter = FakeHttpAdapter((path, body) => ok({
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
                'subCategories': [],
              },
            ],
          }));
      final repo = CategoryRepository(_clientWith(adapter));

      final categories = await repo.list();
      // 返回的是一级列表（子分类挂在 children 上，由 Category.flatten 展开）
      expect(categories.map((c) => c.id), ['200', '300']);

      final parent = categories.firstWhere((c) => c.id == '200');
      expect(parent.children.single.id, '201');
      expect(parent.children.single.name, '食品');
    });
  });

  group('跨币种换算', () {
    test('同币种直接原样；跨币种按 rate 比值（基准约掉）', () {
      const rates = ExchangeRates(
        baseCurrency: 'EUR',
        rates: {'EUR': 1.0, 'CNY': 7.5, 'USD': 1.1},
      );

      expect(rates.convert(1234, 'CNY', 'CNY'), 1234);
      // 100 元 = 100 / 7.5 欧 ≈ 13.33 欧 → 1333 分
      expect(rates.convert(10000, 'CNY', 'EUR'), 1333);
      // 拿不到汇率必须返回 null（表单据此拒绝提交，而不是瞎算）
      expect(rates.convert(10000, 'CNY', 'JPY'), isNull);
    });
  });

  group('StatisticsRepository payload（统计三端点）', () {
    test('overview：秒区间以字符串下发，items 解析成正数最小单位', () async {
      final adapter = FakeHttpAdapter(
        (path, body) => ok({
          'startTime': 1790784000,
          'endTime': 1791255256,
          'items': [
            {
              'categoryId': '3846579121073160220',
              'accountId': '3846683640981356544',
              'amount': '1234',
            },
            {
              'categoryId': '3846579121073160262',
              'accountId': '3846683640981356544',
              'relatedAccountId': '3846683640981356545',
              'relatedAccountType': 2,
              'amount': '1000',
            },
          ],
        }),
      );
      final repo = StatisticsRepository(_clientWith(adapter));

      final overview = await repo.overview(
        startTime: 1790784000,
        endTime: 1791255256,
      );

      final query = adapter
          .lastCallFor('/transactions/statistics.json')
          .uri
          .queryParameters;
      expect(query['start_time'], '1790784000', reason: 'Unix 秒（字符串下发）');
      expect(query['end_time'], '1791255256');
      expect(overview.items, hasLength(2));
      expect(overview.items.first.amount, 1234, reason: 'amount 是最小单位字符串');
      expect(overview.items.first.isTransfer, isFalse);
      expect(overview.items.last.isTransfer, isTrue);
      expect(
        overview.items.last.relatedAccountType,
        2,
        reason: '2 = 对端是转入方（1 = 对端是转出方）',
      );
    });

    test('trends：年月是 2026-01 格式，响应是升序数组', () async {
      final adapter = FakeHttpAdapter(
        (path, body) => ok([
          {
            'year': 2026,
            'month': 9,
            'items': <dynamic>[],
          },
          {
            'year': 2026,
            'month': 10,
            'items': [
              {
                'categoryId': '201',
                'accountId': '7',
                'amount': '5000',
              },
            ],
          },
        ]),
      );
      final repo = StatisticsRepository(_clientWith(adapter));

      final trends = await repo.trends(
        startYearMonth: '2026-09',
        endYearMonth: '2026-10',
      );

      final query = adapter
          .lastCallFor('/transactions/statistics/trends.json')
          .uri
          .queryParameters;
      expect(query['start_year_month'], '2026-09', reason: '按 - 切的年月串');
      expect(query['end_year_month'], '2026-10');
      expect(trends, hasLength(2));
      expect([trends.last.year, trends.last.month], [2026, 10]);
      expect(trends.last.items.single.amount, 5000);
    });

    test('asset_trends：余额是带符号的累计值', () async {
      final adapter = FakeHttpAdapter(
        (path, body) => ok([
          {
            'year': 2026,
            'month': 10,
            'day': 6,
            'items': [
              {
                'accountId': '7',
                'accountOpeningBalance': '1000',
                'accountClosingBalance': '-500',
              },
              {
                'accountId': '8',
                'accountOpeningBalance': '0',
                'accountClosingBalance': '3444',
              },
            ],
          },
        ]),
      );
      final repo = StatisticsRepository(_clientWith(adapter));

      final days = await repo.assetTrends(startTime: 1, endTime: 2);

      expect(
        adapter.lastCallFor('/transactions/statistics/asset_trends.json'),
        isNotNull,
      );
      expect(days, hasLength(1));
      final balances = days.single.balances;
      expect(balances.first.closingMinor, -500, reason: '负债余额为负（实测信用卡）');
      expect(balances.last.closingMinor, 3444);
      expect(days.single.date, DateTime(2026, 10, 6));
    });
  });

  group('UserRepository payload（统计要的默认币种）', () {
    test('profile：GET users/profile/get.json 取 defaultCurrency', () async {
      final adapter = FakeHttpAdapter(
        (path, body) => ok({
          'username': 'admin',
          'nickname': '管理员',
          'language': 'zh-CN',
          'defaultCurrency': 'CNY',
          'defaultAccountId': '7',
        }),
      );
      final repo = UserRepository(_clientWith(adapter));

      final profile = await repo.profile();

      expect(
        adapter.lastCallFor('/users/profile/get.json').method,
        'GET',
        reason: '只读接口，不能写成 POST',
      );
      expect(profile.defaultCurrency, 'CNY');
      expect(profile.language, 'zh-CN');
    });
  });
}
