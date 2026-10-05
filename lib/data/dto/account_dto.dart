/// 账户 DTO —— 对应 `GET /api/v1/accounts/list.json` 的
/// `models.AccountInfoResponse`（源码 pkg/models/account.go）。
///
/// 注意：服务端把 int64 id 用 `json:"id,string"` 序列化成字符串。
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
    required this.hidden,
    required this.subAccounts,
  });

  final String id;
  final String name;
  final String parentId;
  /// 0=资产 1=负债
  final int category;
  final int type;
  final int icon;
  final int iconType;
  final String color;
  final String currency;
  /// 已格式化的十进制字符串，如 "12.34"（不要再除 100）
  final String balance;
  final String comment;
  final int displayOrder;
  final bool hidden;
  final List<Account> subAccounts;

  bool get isAsset => category == 0;

  /// balance → 最小单位（分），用于汇总
  int get balanceMinor {
    try {
      return _parseDecimal(balance);
    } catch (_) {
      return 0;
    }
  }

  static int _parseDecimal(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 0;
    final negative = trimmed.startsWith('-');
    final digits = negative ? trimmed.substring(1) : trimmed;
    final parts = digits.split('.');
    final major = int.tryParse(parts[0]) ?? 0;
    final fracRaw = parts.length > 1 ? parts[1] : '';
    final frac = int.tryParse(fracRaw.padRight(2, '0').substring(0, 2)) ?? 0;
    final minor = major * 100 + frac;
    return negative ? -minor : minor;
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      parentId: json['parentId']?.toString() ?? '0',
      category: _asInt(json['category']),
      type: _asInt(json['type']),
      icon: _asInt(json['icon']),
      iconType: _asInt(json['iconType']),
      color: json['color']?.toString() ?? '#3B7DD8',
      currency: json['currency']?.toString() ?? 'CNY',
      balance: json['balance']?.toString() ?? '0',
      comment: json['comment']?.toString() ?? '',
      displayOrder: _asInt(json['displayOrder']),
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
