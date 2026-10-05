/// 交易明细 DTO —— 对应 `GET /api/v1/transactions/list/by_month.json`
/// 返回的 `models.TransactionInfoResponse`（源码 pkg/models/transaction.go）。
///
/// 交易类型（源码常量）：1=调整余额 2=收入 3=支出 4=转账
class TxType {
  static const int modifyBalance = 1;
  static const int income = 2;
  static const int expense = 3;
  static const int transfer = 4;

  static String label(int type) => switch (type) {
        modifyBalance => '调整余额',
        income => '收入',
        expense => '支出',
        transfer => '转账',
        _ => '未知',
      };
}

class TxCategory {
  const TxCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    required this.iconType,
  });

  final String id;
  final String name;
  final String color;
  final int icon;
  final int iconType;

  factory TxCategory.fromJson(Map<String, dynamic> json) => TxCategory(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        color: json['color']?.toString() ?? '',
        icon: json['icon'] is String
            ? (int.tryParse(json['icon'] as String) ?? 0)
            : (json['icon'] is int ? json['icon'] as int : 0),
        iconType: json['iconType'] is int ? json['iconType'] as int : 0,
      );
}

class TxTag {
  const TxTag({required this.id, required this.name});

  final String id;
  final String name;

  factory TxTag.fromJson(Map<String, dynamic> json) => TxTag(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
      );
}

/// 只保留列表展示需要的账户字段
class TxAccountRef {
  const TxAccountRef({
    required this.id,
    required this.name,
    required this.currency,
  });

  final String id;
  final String name;
  final String currency;

  factory TxAccountRef.fromJson(Map<String, dynamic> json) => TxAccountRef(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        currency: json['currency']?.toString() ?? '',
      );
}

class Transaction {
  const Transaction({
    required this.id,
    required this.type,
    required this.categoryId,
    required this.category,
    required this.time,
    required this.utcOffset,
    required this.sourceAccountId,
    required this.sourceAccount,
    required this.destinationAccountId,
    required this.destinationAccount,
    required this.sourceAmount,
    required this.destinationAmount,
    required this.hideAmount,
    required this.tagIds,
    required this.tags,
    required this.comment,
    required this.editable,
    required this.pictures,
  });

  final String id;
  final int type;
  final String categoryId;
  final TxCategory? category;
  /// Unix 秒（列表接口按本地时区字段另有 time 实现，见 utcOffset）
  final int time;
  final int utcOffset;
  final String sourceAccountId;
  final TxAccountRef? sourceAccount;
  final String destinationAccountId;
  final TxAccountRef? destinationAccount;
  /// 最小单位（分）
  final int sourceAmount;
  final int? destinationAmount;
  final bool hideAmount;
  final List<String> tagIds;
  final List<TxTag> tags;
  final String comment;
  final bool editable;
  final List<String> pictures;

  bool get isIncome => type == TxType.income;
  bool get isExpense => type == TxType.expense;
  bool get isTransfer => type == TxType.transfer;

  /// 展示用货币：转账时显示目标账户货币
  String get displayCurrency {
    if (isTransfer) {
      return destinationAccount?.currency ?? sourceAccount?.currency ?? '';
    }
    return sourceAccount?.currency ?? '';
  }

  /// 转账类交易源/目标金额都可能是负值，展示时取源金额绝对值语义交给 UI
  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id']?.toString() ?? '',
      type: json['type'] is int ? json['type'] as int : 0,
      categoryId: json['categoryId']?.toString() ?? '',
      category: json['category'] is Map<String, dynamic>
          ? TxCategory.fromJson(json['category'] as Map<String, dynamic>)
          : null,
      time: json['time'] is int
          ? json['time'] as int
          : (int.tryParse('${json['time'] ?? 0}') ?? 0),
      utcOffset: json['utcOffset'] is int ? json['utcOffset'] as int : 0,
      sourceAccountId: json['sourceAccountId']?.toString() ?? '',
      sourceAccount: json['sourceAccount'] is Map<String, dynamic>
          ? TxAccountRef.fromJson(
              json['sourceAccount'] as Map<String, dynamic>)
          : null,
      destinationAccountId: json['destinationAccountId']?.toString() ?? '',
      destinationAccount: json['destinationAccount'] is Map<String, dynamic>
          ? TxAccountRef.fromJson(
              json['destinationAccount'] as Map<String, dynamic>)
          : null,
      sourceAmount: json['sourceAmount'] is int
          ? json['sourceAmount'] as int
          : (int.tryParse('${json['sourceAmount'] ?? 0}') ?? 0),
      destinationAmount: json['destinationAmount'] is int
          ? json['destinationAmount'] as int
          : (json['destinationAmount'] is String
              ? int.tryParse(json['destinationAmount'] as String)
              : null),
      hideAmount: json['hideAmount'] == true,
      tagIds: (json['tagIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      tags: (json['tags'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(TxTag.fromJson)
              .toList() ??
          const [],
      comment: json['comment']?.toString() ?? '',
      editable: json['editable'] == true,
      pictures: (json['pictures'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// `list/by_month.json` 响应（TransactionInfoPageWrapperResponse2）
class TransactionPage {
  const TransactionPage({required this.items, required this.totalCount});

  final List<Transaction> items;
  final int totalCount;

  factory TransactionPage.fromJson(Map<String, dynamic> json) => TransactionPage(
        items: (json['items'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(Transaction.fromJson)
                .toList() ??
            const [],
        totalCount: json['totalCount'] is int
            ? json['totalCount'] as int
            : (int.tryParse('${json['totalCount'] ?? 0}') ?? 0),
      );
}
