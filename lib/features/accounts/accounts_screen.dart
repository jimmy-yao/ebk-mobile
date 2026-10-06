import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/util/money.dart';
import '../../data/dto/account_dto.dart';
import '../../data/repositories/account_repository.dart';
import 'account_options.dart';

/// 账户列表（含余额）
final accountsProvider = FutureProvider.autoDispose((ref) async {
  return ref.watch(accountRepositoryProvider).list();
});

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('账户')),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: '$e',
          onRetry: () => ref.invalidate(accountsProvider),
        ),
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Center(child: Text('还没有账户，点右下角 ＋ 新建一个'));
          }
          final assets = accounts.where((a) => a.isAsset).toList();
          final liabilities = accounts.where((a) => !a.isAsset).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(accountsProvider),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (assets.isNotEmpty) ...[
                  const _SectionHeader(title: '资产'),
                  ...assets.map((a) => _AccountTile(account: a)),
                ],
                if (liabilities.isNotEmpty) ...[
                  const _SectionHeader(title: '负债'),
                  ...liabilities.map((a) => _AccountTile(account: a)),
                ],
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/accounts/new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final color = accountColorOf(account.color);
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        child: Icon(accountIconOf(account.icon).icon, color: color),
      ),
      title: Text(account.name),
      subtitle: Text(
        account.hidden ? '${account.currency} · 已隐藏' : account.currency,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            // balance 是最小单位整数串（"-1234"），必须 formatAmount 除 100
            formatAmount(account.balanceMinor, account.currency),
            style: theme.textTheme.titleMedium,
          ),
          if (account.comment.isNotEmpty)
            Text(
              account.comment,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      onTap: () => context.push('/accounts/${account.id}/edit'),
    );
  }
}

/// 共用的错误态（列表页都用它）
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ],
        ),
      ),
    );
  }
}
