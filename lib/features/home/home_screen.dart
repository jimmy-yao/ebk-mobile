import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/util/money.dart';
import '../../data/dto/transaction_dto.dart';
import '../accounts/accounts_screen.dart';
import '../transactions/transactions_screen.dart';
import '../transactions/transaction_tiles.dart';

/// 首页：本月收支汇总 + 最近几笔
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final key = TxQuery(year: now.year, month: now.month);
    final pageAsync = ref.watch(monthlyTxProvider(key));

    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: '统计',
            onPressed: () => context.push('/statistics'),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(monthlyTxProvider(key)),
          ),
        ],
      ),
      body: pageAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(monthlyTxProvider(key)),
        ),
        data: (page) {
          final totals = _monthTotals(page.items);
          final recent = page.items.take(5).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(monthlyTxProvider(key)),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('yyyy年M月').format(now),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 12),
                        if (totals.isEmpty)
                          const Text('本月还没有记录')
                        else
                          ...totals.entries.map(
                            (e) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 56,
                                    child: Text('支出'),
                                  ),
                                  Text(
                                    e.value.expense,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                  ),
                                  const Spacer(),
                                  const SizedBox(
                                    width: 48,
                                    child: Text('收入'),
                                  ),
                                  Text(
                                    e.value.income,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: const Color(0xFF1F9D6B),
                                        ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    e.key,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '最近记录',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: 8),
                if (recent.isEmpty)
                  const Text('暂无记录')
                else
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (final tx in recent)
                          TransactionTile(transaction: tx),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CurrencyTotal {
  const _CurrencyTotal({required this.expense, required this.income});

  final String expense;
  final String income;
}

/// 按币种汇总本月支出/收入（跨币种不能直接相加）
Map<String, _CurrencyTotal> _monthTotals(List<Transaction> items) {
  // currency → [expenseMinor, incomeMinor]
  final raw = <String, List<int>>{};

  for (final tx in items) {
    if (tx.hideAmount) continue;
    final currency = tx.displayCurrency;
    if (currency.isEmpty) continue;
    if (!tx.isExpense && !tx.isIncome) continue;
    final bucket = raw.putIfAbsent(currency, () => [0, 0]);
    if (tx.isExpense) {
      bucket[0] += tx.sourceAmount.abs();
    } else {
      bucket[1] += tx.sourceAmount.abs();
    }
  }

  return raw.map(
    (currency, amounts) => MapEntry(
      currency,
      _CurrencyTotal(
        expense: formatAmount(amounts[0], currency),
        income: formatAmount(amounts[1], currency),
      ),
    ),
  );
}
