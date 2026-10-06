/// 账户表单的可选项，全部对齐网页端常量与服务端枚举：
///
/// * 类别 1..9 ← `models.ACCOUNT_CATEGORY_*`，文案 ← `locales/zh_Hans.json`
///   （3 信用卡 / 5 负债账户为**负债**，其余是资产，见服务端 `assetAccountCategory`）
/// * 图标 id ← `src/consts/icon.ts` 的 `ALL_ACCOUNT_ICONS`（`iconType:0` 预置），
///   服务端只校验 `icon >= 1`，这里选网页端同款 id，Material 图标做近似映射
/// * 颜色只要求 **6 位 hex 且不带 #**（`validHexRGBColor`）
/// * 币种 3 位（`validCurrency`）；服务端没有"支持币种列表"接口，这里放常用 16 种 + 自定义
library;

import 'package:flutter/material.dart';

/// 账户类别
class AccountCategoryOption {
  const AccountCategoryOption(
    this.value,
    this.label, {
    this.liability = false,
  });

  final int value;
  final String label;

  /// 是否计入负债（3 信用卡、5 负债账户）
  final bool liability;
}

const kAccountCategories = <AccountCategoryOption>[
  AccountCategoryOption(1, '现金'),
  AccountCategoryOption(2, '借记账户'),
  AccountCategoryOption(3, '信用卡', liability: true),
  AccountCategoryOption(4, '虚拟账户'),
  AccountCategoryOption(5, '负债账户', liability: true),
  AccountCategoryOption(6, '应收款项'),
  AccountCategoryOption(7, '投资账户'),
  AccountCategoryOption(8, '储蓄账户'),
  AccountCategoryOption(9, '定期存款'),
];

/// 预置账户图标（`iconType = 0`）
class AccountIconOption {
  const AccountIconOption(this.id, this.icon, this.label);

  final int id;
  final IconData icon;
  final String label;
}

const kAccountIcons = <AccountIconOption>[
  AccountIconOption(1, Icons.account_balance_wallet_outlined, '钱包'),
  AccountIconOption(10, Icons.monetization_on_outlined, '硬币'),
  AccountIconOption(20, Icons.attach_money, '钞票'),
  AccountIconOption(30, Icons.savings_outlined, '存钱罐'),
  AccountIconOption(100, Icons.credit_card_outlined, '银行卡'),
  AccountIconOption(110, Icons.request_quote_outlined, '支票'),
  AccountIconOption(500, Icons.speed_outlined, '仪表'),
  AccountIconOption(510, Icons.confirmation_number_outlined, '票券'),
  AccountIconOption(520, Icons.email_outlined, '信封'),
  AccountIconOption(530, Icons.inventory_2_outlined, '盒子'),
  AccountIconOption(540, Icons.volunteer_activism_outlined, '捐赠'),
  AccountIconOption(560, Icons.shield_outlined, '盾牌'),
  AccountIconOption(700, Icons.receipt_long_outlined, '发票'),
  AccountIconOption(701, Icons.receipt_outlined, '收据'),
  AccountIconOption(800, Icons.show_chart, '趋势'),
  AccountIconOption(801, Icons.bar_chart, '柱状图'),
];

/// 账户颜色（6 位 hex，**不带 #**）
const kAccountColors = <String>[
  '3B7DD8', // 蓝
  '2F9E44', // 绿
  'E8A33D', // 橙
  'E05D5D', // 红
  '9B59B6', // 紫
  '16A2AE', // 青
  'D1467E', // 玫红
  '8B5E3C', // 棕
  '6B7280', // 灰
  '000000', // 黑
];

/// 常用币种（code, 中文名）
const kCommonCurrencies = <(String, String)>[
  ('CNY', '人民币 ￥'),
  ('USD', '美元 \$'),
  ('EUR', '欧元 €'),
  ('JPY', '日元 ¥'),
  ('HKD', '港币 HK\$'),
  ('GBP', '英镑 £'),
  ('KRW', '韩元 ₩'),
  ('TWD', '新台币 NT\$'),
  ('SGD', '新加坡元 S\$'),
  ('AUD', '澳元 A\$'),
  ('CAD', '加元 C\$'),
  ('CHF', '瑞士法郎 Fr'),
  ('THB', '泰铢 ฿'),
  ('MYR', '马来西亚林吉特 RM'),
  ('INR', '印度卢比 ₹'),
  ('RUB', '俄罗斯卢布 ₽'),
];

/// 按 id 找预置图标；找不到时兜底钱包（服务端只要 id ≥ 1 就收）
AccountIconOption accountIconOf(int id) =>
    kAccountIcons.firstWhere((e) => e.id == id,
        orElse: () => kAccountIcons.first);

/// 按 value 找类别
AccountCategoryOption accountCategoryOf(int value) =>
    kAccountCategories.firstWhere((e) => e.value == value,
        orElse: () => kAccountCategories.first);

/// 6 位 hex → Color（脏值兜底成默认蓝）
Color accountColorOf(String hex) {
  if (hex.length != 6) return const Color(0xFF3B7DD8);
  final value = int.tryParse(hex, radix: 16);
  return value == null ? const Color(0xFF3B7DD8) : Color(0xFF000000 | value);
}
