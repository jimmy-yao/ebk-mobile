import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/dto/transaction_dto.dart';
import '../../data/repositories/transaction_repository.dart';
import '../accounts/accounts_screen.dart';
import 'transaction_tiles.dart';

/// 按 (年,月) 缓存的明细页
class MonthKey {
  const MonthKey(this.year, this.month);

  final int year;
  final int month;

  @override
  bool operator ==(Object other) =>
      other is MonthKey && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

final monthlyTxProvider =
    FutureProvider.autoDispose.family<TransactionPage, MonthKey>((ref, key) {
  return ref
      .watch(transactionRepositoryProvider)
      .listByMonth(year: key.year, month: key.month);
});

/// 明细列表：按月翻页 + 按日期分组
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  @override
  Widget build(BuildContext context) {
    final key = MonthKey(_month.year, _month.month);
    final pageAsync = ref.watch(monthlyTxProvider(key));

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shiftMonth(-1),
            ),
            Text(DateFormat('yyyy年M月').format(_month)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shiftMonth(1),
            ),
          ],
        ),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('记账表单在 Phase 1 第 3 周实现')),
        ),
        child: const Icon(Icons.add),
      ),
      body: pageAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(monthlyTxProvider(key)),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return const Center(child: Text('这个月还没有记录'));
          }

          // 按本地日期分组（tx.time 是 Unix 秒，utcOffset 是该条记录的本地时区偏移）
          final groups = <String, List<Transaction>>{};
          final groupOrder = <String>[];
          for (final tx in page.items) {
            final utc = DateTime.fromMillisecondsSinceEpoch(
              tx.time * 1000,
              isUtc: true,
            );
            final local = utc.add(Duration(minutes: tx.utcOffset));
            final label = DateFormat('M月d日 EEEE').format(local);
            if (!groups.containsKey(label)) {
              groups[label] = [];
              groupOrder.add(label);
            }
            groups[label]!.add(tx);
          }

          return RefreshIndicator(
            onRefresh: () async =>
                ref.invalidate(monthlyTxProvider(key)),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    '本月共 ${page.totalCount} 笔',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final label in groupOrder) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                  Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final tx in groups[label]!)
                          TransactionTile(transaction: tx),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
