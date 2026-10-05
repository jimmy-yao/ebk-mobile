import 'package:ebk_mobile/data/dto/account_dto.dart';
import 'package:ebk_mobile/data/dto/transaction_dto.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用一份贴近线上响应结构的样例做解析回归：
/// 字段名全部来自源码 models.TransactionInfoResponse / AccountInfoResponse。
void main() {
  group('Transaction.fromJson', () {
    // 服务端响应片段（id 用 string 序列化 int64；amount 是 int64 最小单位）
    const fixture = {
      'id': '998877665544332211',
      'type': 3,
      'categoryId': '100000000000001',
      'category': {
        'id': '100000000000001',
        'name': '餐饮',
        'color': '#F76F6F',
        'icon': '26',
        'iconType': 1,
      },
      'time': 1759286400,
      'utcOffset': 480,
      'sourceAccountId': '556677889900112233',
      'sourceAccount': {
        'id': '556677889900112233',
        'name': '现金钱包',
        'currency': 'CNY',
      },
      'destinationAccountId': '0',
      'sourceAmount': 3250,
      'destinationAmount': 0,
      'hideAmount': false,
      'tagIds': ['200000000000001'],
      'tags': [
        {'id': '200000000000001', 'name': '工作日'}
      ],
      'comment': '午饭',
      'editable': true,
      'pictures': [],
    };

    test('解析支出交易', () {
      final tx = Transaction.fromJson(fixture);

      expect(tx.id, '998877665544332211');
      expect(tx.type, TxType.expense);
      expect(tx.isExpense, isTrue);
      expect(tx.category?.name, '餐饮');
      expect(tx.sourceAmount, 3250);
      expect(tx.sourceAccount?.name, '现金钱包');
      expect(tx.displayCurrency, 'CNY');
      expect(tx.comment, '午饭');
      expect(tx.tags.single.name, '工作日');
      expect(tx.time, 1759286400);
      expect(tx.utcOffset, 480);
    });

    test('转账交易的目标账户与货币', () {
      final tx = Transaction.fromJson({
        ...fixture,
        'type': 4,
        'destinationAccount': {
          'id': '1',
          'name': '信用卡',
          'currency': 'CNY',
        },
      });

      expect(tx.isTransfer, isTrue);
      expect(tx.destinationAccount?.name, '信用卡');
      expect(tx.displayCurrency, 'CNY');
    });

    test('兼容 amount 被序列化为字符串的情况', () {
      final tx = Transaction.fromJson({...fixture, 'sourceAmount': '3250'});
      expect(tx.sourceAmount, 3250);
    });

    test('缺省字段不炸', () {
      final tx = Transaction.fromJson(const {});
      expect(tx.id, '');
      expect(tx.type, 0);
      expect(tx.tags, isEmpty);
      expect(tx.category, isNull);
    });
  });

  group('TransactionPage.fromJson', () {
    test('包装结构 items + totalCount', () {
      final page = TransactionPage.fromJson(const {
        'items': [
          {'id': '1', 'type': 3, 'sourceAmount': 100}
        ],
        'totalCount': 42,
      });

      expect(page.totalCount, 42);
      expect(page.items, hasLength(1));
      expect(page.items.single.sourceAmount, 100);
    });
  });

  group('Account.fromJson', () {
    test('解析账户（balance 是已格式化字符串）', () {
      final account = Account.fromJson(const {
        'id': '556677889900112233',
        'name': '现金钱包',
        'parentId': '0',
        'category': 0,
        'type': 1,
        'icon': '1',
        'iconType': 1,
        'color': '#3B7DD8',
        'currency': 'CNY',
        'balance': '1234.56',
        'comment': '',
        'displayOrder': 1,
        'hidden': false,
        'subAccounts': [],
      });

      expect(account.isAsset, isTrue);
      expect(account.balance, '1234.56');
      expect(account.balanceMinor, 123456);
      expect(account.currency, 'CNY');
      expect(account.hidden, isFalse);
    });

    test('负债账户', () {
      final account = Account.fromJson(const {
        'id': '2',
        'name': '信用卡',
        'category': 1,
        'currency': 'CNY',
        'balance': '-500.00',
      });
      expect(account.isAsset, isFalse);
      expect(account.balanceMinor, -50000);
    });
  });
}
