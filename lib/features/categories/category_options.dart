/// 分类表单的可选项，对齐网页端 `src/consts/icon.ts` 的 `ALL_CATEGORY_ICONS`
/// 分段与服务端 `TransactionCategoryType`：
///
/// * 图标按类型分段：1..1999 支出 / 2000..3999 收入 / 4000..4099 转账，
///   服务端对 `iconType:0` 只校验 `icon >= 1`，这里用网页端同款 id 保证
///   网页端也能正常渲染图标
/// * 颜色 6 位 hex **不带 #**（`binding:"required,len=6,validHexRGBColor"`）
library;

import 'package:flutter/material.dart';

/// 分类类型（1 收入 / 2 支出 / 3 转账），顺序即 Tab 顺序
class CategoryTypeOption {
  const CategoryTypeOption(this.value, this.label);

  final int value;
  final String label;
}

const kCategoryTypes = <CategoryTypeOption>[
  CategoryTypeOption(2, '支出'),
  CategoryTypeOption(1, '收入'),
  CategoryTypeOption(3, '转账'),
];

/// 预置分类图标（`iconType = 0`）
class CategoryIconOption {
  const CategoryIconOption(this.id, this.icon, this.label);

  final int id;
  final IconData icon;
  final String label;
}

/// 支出分类图标（`src/consts/icon.ts` 1..1999 段的代表 id）
const kExpenseCategoryIcons = <CategoryIconOption>[
  CategoryIconOption(1, Icons.restaurant_outlined, '餐饮'),
  CategoryIconOption(30, Icons.local_cafe_outlined, '咖啡'),
  CategoryIconOption(100, Icons.checkroom_outlined, '服饰'),
  CategoryIconOption(200, Icons.home_outlined, '家居'),
  CategoryIconOption(330, Icons.directions_car_outlined, '交通'),
  CategoryIconOption(400, Icons.phone_iphone, '通讯'),
  CategoryIconOption(500, Icons.favorite_outline, '娱乐'),
  CategoryIconOption(600, Icons.menu_book_outlined, '教育'),
  CategoryIconOption(700, Icons.card_giftcard_outlined, '人情'),
  CategoryIconOption(800, Icons.local_hospital_outlined, '医疗'),
  CategoryIconOption(900, Icons.account_balance_outlined, '金融'),
  CategoryIconOption(1000, Icons.edit_outlined, '其他'),
];

/// 收入分类图标（2000..3999 段）
const kIncomeCategoryIcons = <CategoryIconOption>[
  CategoryIconOption(2000, Icons.work_outline, '工作'),
  CategoryIconOption(2010, Icons.account_balance_wallet_outlined, '薪酬'),
  CategoryIconOption(2020, Icons.emoji_events_outlined, '奖金'),
  CategoryIconOption(2080, Icons.access_time_outlined, '兼职'),
  CategoryIconOption(2100, Icons.show_chart, '理财'),
  CategoryIconOption(3010, Icons.add_circle_outline, '其他'),
];

/// 转账分类图标（4000..4099 段，服务端只有 2 个）
const kTransferCategoryIcons = <CategoryIconOption>[
  CategoryIconOption(4000, Icons.swap_horiz, '划转'),
  CategoryIconOption(4900, Icons.arrow_circle_right_outlined, '转入'),
];

/// 分类颜色（6 位 hex，**不带 #**）
const kCategoryColors = <String>[
  'E8A33D', // 橙（网页端分类默认色系）
  '3B7DD8', // 蓝
  '2F9E44', // 绿
  'E05D5D', // 红
  '9B59B6', // 紫
  '16A2AE', // 青
  'D1467E', // 玫红
  '8B5E3C', // 棕
  '6B7280', // 灰
  '000000', // 黑
];

/// 该类型的图标集（新建分类时按类型切换）
List<CategoryIconOption> categoryIconsOf(int type) => switch (type) {
      1 => kIncomeCategoryIcons,
      3 => kTransferCategoryIcons,
      _ => kExpenseCategoryIcons,
    };

/// 类型文案
String categoryTypeLabel(int type) => switch (type) {
      1 => '收入',
      3 => '转账',
      _ => '支出',
    };

/// 按 id 找图标；找不到时兜底到该类型的第一个（服务端只要 id ≥ 1 就收）
CategoryIconOption categoryIconOf(int id, int type) {
  final icons = categoryIconsOf(type);
  return icons.firstWhere((e) => e.id == id, orElse: () => icons.first);
}

/// 6 位 hex → Color（脏值兜底成默认橙）
Color categoryColorOf(String hex) {
  if (hex.length != 6) return const Color(0xFFE8A33D);
  final value = int.tryParse(hex, radix: 16);
  return value == null ? const Color(0xFFE8A33D) : Color(0xFF000000 | value);
}
