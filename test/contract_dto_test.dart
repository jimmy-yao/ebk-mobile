/// 契约回归测试：只放**实测踩过坑**的解析规则，防止"想当然"的改动悄悄回归。
///
/// 事实来源：`scripts/smoke.sh --crud` 与 2026-10 对 ezBookkeeping 2.0.1 的
/// 实测（详见方案文档 §1）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ebk_mobile/core/util/money.dart';
import 'package:ebk_mobile/data/dto/account_dto.dart';
import 'package:ebk_mobile/data/dto/misc_dto.dart';

void main() {
  group('账户 balance 是最小单位整数字符串', () {
    // 源码：models/account.go → Balance: utils.Int64ToString(a.Balance)
    // 实测：支出 1234 分后 accounts/list.json 返回 "-1234"
    test('fromJson 后 balanceMinor 直接就是分', () {
      final account = Account.fromJson(const {
        'id': '1',
        'name': '现金',
        'category': 1,
        'type': 1,
        'icon': '1',
        'iconType': 0,
        'color': '3B7DD8',
        'currency': 'CNY',
        'balance': '-1234',
      });

      expect(account.balanceMinor, -1234);
      expect(formatAmount(account.balanceMinor, 'CNY'), '-12.34');
      expect(account.isAsset, true);
      expect(account.isLiability, false);
    });

    test('缺省/脏值不炸', () {
      expect(Account.fromJson(const {}).balanceMinor, 0);
      expect(Account.fromJson(const {'balance': 'abc'}).balanceMinor, 0);
    });
  });

  group('分类列表', () {
    // 实测：list.json 返回的是 {"1":[...], "2":[...], "3":[...]} 分组 map，
    // 每个一级分类下挂 subCategories —— JSON 字段叫 subCategories，不是 children
    test('子分类挂在 subCategories 下', () {
      final parent = Category.fromJson(const {
        'id': '100',
        'name': '食品饮料',
        'type': 2,
        'parentId': '0',
        'hidden': false,
        'subCategories': [
          {'id': '101', 'name': '食品', 'type': 2, 'parentId': '100', 'hidden': false},
          {'id': '102', 'name': '饮料', 'type': 2, 'parentId': '100', 'hidden': true},
        ],
      });

      expect(parent.children.map((c) => c.id), ['101', '102']);
      expect(parent.children[1].hidden, isTrue);
    });

    test('flatten 按前序给出深度（深度 ≥1 才是可记账的子分类）', () {
      final tree = [
        Category.fromJson(const {
          'id': '100',
          'name': '食品饮料',
          'type': 2,
          'parentId': '0',
          'subCategories': [
            {'id': '101', 'name': '食品', 'type': 2, 'parentId': '100'},
          ],
        }),
      ];

      final flat = Category.flatten(tree);
      expect(flat.length, 2);
      expect(flat[0].value, 0); // 一级分类：服务端 206005 拒绝用于记账
      expect(flat[1].value, 1); // 子分类：可用
      expect(flat[1].key.id, '101');
    });
  });
}
