/// 账户类别（服务端 `models.AccountCategory`，注意**不是** 0/1）：
/// 1 现金 2 支票 3 信用卡 4 虚拟 5 债务 6 应收 7 投资 8 储蓄 9 定期存款
/// 其中 3、5 是负债，其余是资产（服务端 `assetAccountCategory` 表）。
/// 响应里另外直接给了 `isAsset` / `isLiability`（omitempty，只在为真时出现），
/// DTO 优先用这两个字段，缺失时按上面的枚举兜底。
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.parentId,
    required this.category,
    required this.type,
    required this.icon,
    required this.iconType,
    required this.color,
    required this.currency,
    required this.balance,
    required this.comment,
    required this.displayOrder,
    required this.isAsset,
    required this.isLiability,
    required this.hidden,
    required this.subAccounts,
  });

  final String id;
  final String name;
  final String parentId;
  /// 1..9，见上方注释
  final int category;
  /// 1=单账户 2=带子账户（ACCOUNT_TYPE_SINGLE_ACCOUNT / MULTI_SUB_ACCOUNTS）
  final int type;
  final int icon;
  final int iconType;
  /// 6 位十六进制，**不带 #**（服务端 `len=6, validHexRGBColor`）
  final String color;
  final String currency;
  /// **最小单位整数字符串**：服务端 `Balance: utils.Int64ToString(a.Balance)`，
  /// 实测支出 1234 分后返回 `"-1234"`（不是 "−12.34" 的十进制串）。
  /// 展示时用 `formatAmount(balance)` 除 100 即可。
  final String balance;
  final String comment;
  final int displayOrder;
  final bool isAsset;
  final bool isLiability;
  final bool hidden;
  final List<Account> subAccounts;

  /// balance → 最小单位（分），用于汇总
  int get balanceMinor => int.tryParse(balance.trim()) ?? 0;

  /// 服务端 assetAccountCategory 表里算资产的类别（其余为负债）
  static const _assetCategories = <int>{1, 2, 4, 6, 7, 8, 9};

  factory Account.fromJson(Map<String, dynamic> json) {
    final category = _asInt(json['category']);
    // 响应里 isAsset/isLiability 是 omitempty（只在为真时出现），优先信它们
    final isAssetFlag = json['isAsset'] == true;
    final isLiabilityFlag = json['isLiability'] == true;

    return Account(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      parentId: json['parentId']?.toString() ?? '0',
      category: category,
      type: _asInt(json['type']),
      icon: _asInt(json['icon']),
      iconType: _asInt(json['iconType']),
      color: json['color']?.toString() ?? '3B7DD8',
      currency: json['currency']?.toString() ?? 'CNY',
      balance: json['balance']?.toString() ?? '0',
      comment: json['comment']?.toString() ?? '',
      displayOrder: _asInt(json['displayOrder']),
      isAsset: isAssetFlag || (!isLiabilityFlag && _assetCategories.contains(category)),
      isLiability: isLiabilityFlag || (!isAssetFlag && !_assetCategories.contains(category)),
      hidden: json['hidden'] == true,
      subAccounts: (json['subAccounts'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(Account.fromJson)
              .toList() ??
          const [],
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    if (value is num) return value.toInt();
    return 0;
  }
}
