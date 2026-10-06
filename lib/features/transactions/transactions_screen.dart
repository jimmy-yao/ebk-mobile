import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/dto/account_dto.dart';
import '../../data/dto/misc_dto.dart';
import '../../data/dto/transaction_dto.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../accounts/accounts_screen.dart';
import '../categories/category_options.dart';
import 'transaction_tiles.dart';

/// 明细查询条件（作为 provider 的 key：改条件 = 重新拉取，同时按条件各自缓存）
class TxQuery {
  const TxQuery({
    required this.year,
    required this.month,
    this.type,
    this.keyword = '',
    this.categoryId,
    this.accountId,
  });

  final int year;
  final int month;

  /// 1 调整 / 2 收入 / 3 支出 / 4 转账；null = 不限
  final int? type;

  /// 关键词（空串 = 不搜）
  final String keyword;

  /// 一级分类 id（服务端会自动展开成它的子分类）
  final String? categoryId;

  final String? accountId;

  bool get hasFilter => type != null || categoryId != null || accountId != null;
  bool get isPlain => !hasFilter && keyword.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is TxQuery &&
      other.year == year &&
      other.month == month &&
      other.type == type &&
      other.keyword == keyword &&
      other.categoryId == categoryId &&
      other.accountId == accountId;

  @override
  int get hashCode =>
      Object.hash(year, month, type, keyword, categoryId, accountId);
}

final monthlyTxProvider =
    FutureProvider.autoDispose.family<TransactionPage, TxQuery>((ref, q) {
  return ref.watch(transactionRepositoryProvider).listByMonth(
        year: q.year,
        month: q.month,
        type: q.type,
        keyword: q.keyword.isEmpty ? null : q.keyword,
        categoryIds: q.categoryId,
        accountIds: q.accountId,
      );
});

/// 明细列表：按月翻页 + 按日期分组 + 关键词搜索 / 类型・账户・分类筛选
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() =>
      _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late DateTime _month;
  late final TextEditingController _searchCtrl;

  bool _searching = false;
  String _keyword = '';

  int? _type;
  String? _accountId;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _searchCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _applyKeyword() {
    setState(() {
      _keyword = _searchCtrl.text.trim();
      _searching = false;
    });
  }

  void _closeSearch() {
    setState(() {
      _searching = false;
      _searchCtrl.clear();
      _keyword = '';
    });
  }

  void _clearAll() {
    setState(() {
      _keyword = '';
      _type = null;
      _accountId = null;
      _categoryId = null;
    });
  }

  int get _activeFilterCount =>
      (_type == null ? 0 : 1) +
      (_accountId == null ? 0 : 1) +
      (_categoryId == null ? 0 : 1);

  /// 打开筛选底部弹层（在 await 之前就把列表读出来，避免 ref 失效）
  Future<void> _openFilter() async {
    final accounts = await ref.read(accountsProvider.future);
    if (!mounted) return;
    final categories = await ref.read(categoriesProvider.future);
    if (!mounted) return;

    final result = await showModalBottomSheet<_TxFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(
        initial: _TxFilter(
          type: _type,
          accountId: _accountId,
          categoryId: _categoryId,
        ),
        accounts: accounts,
        categories: categories,
      ),
    );

    if (result == null || !mounted) return;
    setState(() {
      _type = result.type;
      _accountId = result.accountId;
      _categoryId = result.categoryId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = TxQuery(
      year: _month.year,
      month: _month.month,
      type: _type,
      keyword: _keyword,
      categoryId: _categoryId,
      accountId: _accountId,
    );
    final pageAsync = ref.watch(monthlyTxProvider(query));
    final accounts = ref.watch(accountsProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: _searching
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _closeSearch,
              )
            : null,
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索备注、分类…',
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _applyKeyword,
                  ),
                ),
                onSubmitted: (_) => _applyKeyword(),
              )
            : Row(
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
        actions: [
          if (!_searching) ...[
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _searching = true),
            ),
            IconButton(
              tooltip: '筛选',
              icon: Badge(
                isLabelVisible: _activeFilterCount > 0,
                label: Text('$_activeFilterCount'),
                child: const Icon(Icons.tune),
              ),
              onPressed: _openFilter,
            ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/transactions/new'),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _FilterBar(
            keyword: _keyword,
            type: _type,
            accounts: accounts.valueOrNull ?? const [],
            categories: categories.valueOrNull ?? const [],
            accountId: _accountId,
            categoryId: _categoryId,
            onClearKeyword: () => setState(() => _keyword = ''),
            onClearType: () => setState(() => _type = null),
            onClearAccount: () => setState(() => _accountId = null),
            onClearCategory: () => setState(() => _categoryId = null),
            onClearAll: _clearAll,
          ),
          Expanded(child: _buildList(pageAsync, query)),
        ],
      ),
    );
  }

  Widget _buildList(
    AsyncValue<TransactionPage> pageAsync,
    TxQuery query,
  ) {
    return pageAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: '$e',
        onRetry: () => ref.invalidate(monthlyTxProvider(query)),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return Center(
            child: Text(query.isPlain ? '这个月还没有记录' : '没有匹配的记录'),
          );
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
          onRefresh: () async => ref.invalidate(monthlyTxProvider(query)),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  query.isPlain
                      ? '本月共 ${page.totalCount} 笔'
                      : '筛选出 ${page.totalCount} 笔',
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
    );
  }
}

/// 当前生效的搜索/筛选条件（可单个删掉，也可一键清空）
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.keyword,
    required this.type,
    required this.accounts,
    required this.categories,
    required this.accountId,
    required this.categoryId,
    required this.onClearKeyword,
    required this.onClearType,
    required this.onClearAccount,
    required this.onClearCategory,
    required this.onClearAll,
  });

  final String keyword;
  final int? type;
  final List<Account> accounts;
  final List<Category> categories;
  final String? accountId;
  final String? categoryId;
  final VoidCallback onClearKeyword;
  final VoidCallback onClearType;
  final VoidCallback onClearAccount;
  final VoidCallback onClearCategory;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (keyword.isNotEmpty) {
      chips.add(Chip(
        label: Text('搜索：$keyword'),
        onDeleted: onClearKeyword,
      ));
    }
    if (type != null) {
      chips.add(Chip(
        label: Text('类型：${TxType.label(type!)}'),
        onDeleted: onClearType,
      ));
    }
    if (accountId != null) {
      final name = accounts
          .where((a) => a.id == accountId)
          .map((a) => a.name)
          .firstOrNull;
      chips.add(Chip(
        label: Text('账户：${name ?? '—'}'),
        onDeleted: onClearAccount,
      ));
    }
    if (categoryId != null) {
      final name = categories
          .where((c) => c.id == categoryId)
          .map((c) => c.name)
          .firstOrNull;
      chips.add(Chip(
        label: Text('分类：${name ?? '—'}'),
        onDeleted: onClearCategory,
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          ...chips,
          ActionChip(
            label: const Text('清空'),
            avatar: const Icon(Icons.close, size: 16),
            onPressed: onClearAll,
          ),
        ],
      ),
    );
  }
}

class _TxFilter {
  const _TxFilter({this.type, this.accountId, this.categoryId});

  final int? type;
  final String? accountId;
  final String? categoryId;
}

/// 筛选弹层：类型 + 账户 + 一级分类（服务端自动展开成子分类）
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.initial,
    required this.accounts,
    required this.categories,
  });

  final _TxFilter initial;
  final List<Account> accounts;
  final List<Category> categories;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late int? _type = widget.initial.type;
  late String? _accountId = widget.initial.accountId;
  late String? _categoryId = widget.initial.categoryId;

  static const _types = <int?>[null, TxType.expense, TxType.income, TxType.transfer];

  void _apply() {
    Navigator.of(context).pop(
      _TxFilter(type: _type, accountId: _accountId, categoryId: _categoryId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                children: [
                  Text('类型', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final value in _types)
                        ChoiceChip(
                          label: Text(
                            value == null ? '全部' : TxType.label(value),
                          ),
                          selected: _type == value,
                          onSelected: (_) => setState(() => _type = value),
                        ),
                    ],
                  ),
                  const Divider(height: 32),
                  Text('账户', style: theme.textTheme.titleSmall),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('全部账户'),
                    trailing: _accountId == null
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : const SizedBox.shrink(),
                    onTap: () => setState(() => _accountId = null),
                  ),
                  for (final account in widget.accounts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(account.name),
                      subtitle: Text(
                        account.hidden
                            ? '${account.currency} · 已隐藏'
                            : account.currency,
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: _accountId == account.id
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : const SizedBox.shrink(),
                      onTap: () => setState(() => _accountId = account.id),
                    ),
                  const Divider(height: 32),
                  Text('分类（选一级，自动含子分类）', style: theme.textTheme.titleSmall),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('全部分类'),
                    trailing: _categoryId == null
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : const SizedBox.shrink(),
                    onTap: () => setState(() => _categoryId = null),
                  ),
                  for (final category in widget.categories)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        categoryIconOf(category.icon, category.type).icon,
                        color: categoryColorOf(category.color),
                      ),
                      title: Text(category.name),
                      subtitle: Text(
                        categoryTypeLabel(category.type),
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: _categoryId == category.id
                          ? Icon(Icons.check, color: theme.colorScheme.primary)
                          : const SizedBox.shrink(),
                      onTap: () => setState(() => _categoryId = category.id),
                    ),
                ],
              ),
            ),
            // 按钮钉在弹层底部：内容再长也不会被滚出屏幕
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(
                        const _TxFilter(),
                      ),
                      child: const Text('清空'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: const Text('应用'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
