import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/util/money.dart';
import '../../data/dto/account_dto.dart';
import '../../data/repositories/account_repository.dart';

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
            return const Center(child: Text('还没有账户，去网页端先建一个'));
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
    final colorHex = account.color.replaceFirst('#', '');
    final color = _safeColor(colorHex);
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.18),
        child: Icon(Icons.account_balance_wallet_outlined, color: color),
      ),
      title: Text(account.name),
      subtitle: Text(
        account.currency,
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
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${account.name} 的编辑页在 Phase 1 第 3 周实现')),
      ),
    );
  }

  static Color _safeColor(String hex) {
    if (hex.length != 6) return const Color(0xFF3B7DD8);
    final value = int.tryParse(hex, radix: 16);
    return value == null ? const Color(0xFF3B7DD8) : Color(0xFF000000 | value);
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
