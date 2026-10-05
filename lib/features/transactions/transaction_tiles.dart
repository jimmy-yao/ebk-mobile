import 'package:flutter/material.dart';

import '../../core/util/money.dart';
import '../../data/dto/transaction_dto.dart';

/// 一条交易的列表项（首页/明细共用）
class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = transaction;
    final category = tx.category;
    final colorHex = (category?.color ?? '').replaceFirst('#', '');
    final color = _safeColor(colorHex);

    final amountColor = switch (tx.type) {
      TxType.income => const Color(0xFF1F9D6B),
      TxType.expense => theme.colorScheme.error,
      _ => theme.colorScheme.onSurfaceVariant,
    };

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.16),
        child: Text(
          category?.name.isNotEmpty == true
              ? category!.name.substring(0, 1)
              : '·',
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ),
      title: Text(category?.name ?? TxType.label(tx.type)),
      subtitle: Text(
        _subtitle(tx),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (tx.hideAmount)
            Text('***', style: theme.textTheme.titleMedium)
          else
            Text(
              _amountText(tx),
              style: theme.textTheme.titleMedium?.copyWith(color: amountColor),
            ),
          Text(
            _timeText(tx),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('明细详情页在 Phase 1 第 3 周实现')),
      ),
    );
  }

  String _amountText(Transaction tx) {
    final currency = tx.displayCurrency;
    if (tx.isTransfer) {
      final sign = tx.sourceAmount >= 0 ? '' : '-';
      return '$sign${formatAmount(tx.sourceAmount.abs(), currency)}';
    }
    final sign = tx.isIncome ? '+' : (tx.isExpense ? '-' : '');
    return '$sign${formatAmount(tx.sourceAmount.abs(), currency)}';
  }

  String _subtitle(Transaction tx) {
    final parts = <String>[];
    final accountName = tx.sourceAccount?.name;
    if (accountName != null && accountName.isNotEmpty) parts.add(accountName);
    if (tx.isTransfer && (tx.destinationAccount?.name.isNotEmpty ?? false)) {
      parts.add('→ ${tx.destinationAccount!.name}');
    }
    if (tx.comment.isNotEmpty) parts.add(tx.comment);
    if (tx.tags.isNotEmpty) {
      parts.add(tx.tags.map((t) => '#${t.name}').join(' '));
    }
    return parts.join(' · ');
  }

  String _timeText(Transaction tx) {
    final utc = DateTime.fromMillisecondsSinceEpoch(tx.time * 1000, isUtc: true);
    final local = utc.add(Duration(minutes: tx.utcOffset));
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static Color _safeColor(String hex) {
    if (hex.length != 6) return const Color(0xFF6B7280);
    final value = int.tryParse(hex, radix: 16);
    return value == null ? const Color(0xFF6B7280) : Color(0xFF000000 | value);
  }
}
