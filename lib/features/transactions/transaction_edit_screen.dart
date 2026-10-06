import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/util/money.dart';
import '../../data/dto/account_dto.dart';
import '../../data/dto/misc_dto.dart';
import '../../data/dto/transaction_dto.dart';
import '../../data/repositories/category_repository.dart';
import '../../data/repositories/exchange_rate_repository.dart';
import '../../data/repositories/transaction_repository.dart';
import '../accounts/accounts_screen.dart';
import 'transactions_screen.dart';

/// 记账表单：`transactionId == null` 为新建，否则为编辑（带删除）。
///
/// 契约要点全部来自源码 + `scripts/smoke.sh` 实测（见方案文档 §1）：
/// * 金额传**最小单位、正数**（支出服务端自己做扣减）
/// * 非转账 `destinationAmount` 必须为 0
/// * `categoryId`/`sourceAccountId` 是字符串化 int64
/// * `utcOffset` 东向为正（UTC+8 → 480）
class TransactionEditScreen extends ConsumerStatefulWidget {
  const TransactionEditScreen({super.key, this.transactionId});

  final String? transactionId;

  @override
  ConsumerState<TransactionEditScreen> createState() =>
      _TransactionEditScreenState();
}

class _TransactionEditScreenState
    extends ConsumerState<TransactionEditScreen> {
  int _type = TxType.expense;
  String _categoryId = '';
  String _sourceAccountId = '';
  String _destinationAccountId = '';
  DateTime _time = DateTime.now();

  final _amountCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();

  Set<String> _tagIds = {};
  bool _hideAmount = false;

  bool _loadingDetail = false;
  bool _saving = false;
  String? _error;

  bool get isEditing => widget.transactionId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) _loadDetail();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDetail() async {
    setState(() => _loadingDetail = true);
    try {
      final tx = await ref
          .read(transactionRepositoryProvider)
          .get(widget.transactionId!);
      if (tx == null) throw Exception('明细不存在或已删除');
      if (!mounted) return;
      setState(() {
        _type = tx.type;
        _categoryId = tx.categoryId;
        _sourceAccountId = tx.sourceAccountId;
        _destinationAccountId = tx.destinationAccountId;
        _time = DateTime.fromMillisecondsSinceEpoch(
          tx.time * 1000,
          isUtc: true,
        ).toLocal();
        _amountCtrl.text = minorToInput(tx.sourceAmount);
        _commentCtrl.text = tx.comment;
        _tagIds = tx.tagIds.toSet();
        _hideAmount = tx.hideAmount;
        _loadingDetail = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDetail = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (time == null || !mounted) return;
    setState(() {
      _time = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _pickAccount({
    required List<Account> accounts,
    required bool isDestination,
  }) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final a in accounts)
                // 选转入账户时排除已选的转出账户，反过来不排（允许对调）
                if (!isDestination || a.id != _sourceAccountId)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _accountColor(a).withValues(alpha: 0.16),
                      child: Icon(Icons.account_balance_wallet_outlined,
                          color: _accountColor(a), size: 18),
                    ),
                    title: Text(a.name),
                    subtitle: Text(
                        '${a.currency} · ${formatAmount(a.balanceMinor, a.currency)}'),
                    onTap: () => Navigator.of(context).pop(a.id),
                  ),
            ],
          ),
        ),
      ),
    );
    if (selected == null) return;
    setState(() {
      if (isDestination) {
        _destinationAccountId = selected;
      } else {
        _sourceAccountId = selected;
      }
    });
  }

  Future<void> _save() async {
    final amountText = _amountCtrl.text.trim();
    final amount = parseDecimalToMinor(amountText);

    if (amount <= 0) {
      setState(() => _error = '金额要大于 0');
      return;
    }
    if (_sourceAccountId.isEmpty) {
      setState(() => _error = '请选择账户');
      return;
    }

    // 分类硬性规则（服务端 isCategoryValid 实测）：必须是**该类型下的子分类**，
    // 一级分类 206005、hidden 206006、type 不符 206002、空串 200000。
    // 转账同样要选分类，所以这里不分类型统一校验。
    var validIds = <String>{};
    try {
      final categories = await ref.read(categoriesProvider.future);
      validIds = _validCategoryIds(_categoryGroups(categories));
    } catch (e) {
      setState(() => _error = '分类读取失败：$e');
      return;
    }
    if (!validIds.contains(_categoryId)) {
      setState(() => _error = '请选择${_categoryTypeName()}');
      return;
    }

    // 转账：目标账户必填；金额按汇率换算
    int destinationAmount = 0;
    String? destinationAccountId;
    if (_type == TxType.transfer) {
      if (_destinationAccountId.isEmpty) {
        setState(() => _error = '请选择转入账户');
        return;
      }
      if (_destinationAccountId == _sourceAccountId) {
        setState(() => _error = '转出和转入账户不能相同');
        return;
      }
      destinationAccountId = _destinationAccountId;

      final accounts = await ref.read(accountsProvider.future);
      final from = _accountById(accounts, _sourceAccountId)?.currency ?? '';
      final to = _accountById(accounts, _destinationAccountId)?.currency ?? '';

      if (from == to) {
        destinationAmount = amount;
      } else {
        final rates = await ref.read(exchangeRatesProvider.future);
        final converted = rates.convert(amount, from, to);
        if (converted == null) {
          setState(() => _error = '拿不到 $from → $to 的汇率，暂时只能转同币种');
          return;
        }
        destinationAmount = converted;
      }
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      final draft = TxDraft(
        type: _type,
        categoryId: _categoryId,
        time: _time.toUtc().millisecondsSinceEpoch ~/ 1000,
        utcOffset: _time.timeZoneOffset.inMinutes, // 东向为正
        sourceAccountId: _sourceAccountId,
        sourceAmount: amount,
        destinationAccountId: destinationAccountId,
        destinationAmount: destinationAmount,
        hideAmount: _hideAmount,
        tagIds: _tagIds.toList(),
        comment: _commentCtrl.text.trim(),
      );

      final repo = ref.read(transactionRepositoryProvider);
      if (isEditing) {
        await repo.modify(id: widget.transactionId!, draft: draft);
      } else {
        await repo.add(draft);
      }

      // 刷新所有相关列表（月度明细是 family，invalidate 会全清）
      ref.invalidate(monthlyTxProvider);
      ref.invalidate(accountsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEditing ? '已保存修改' : '已记一笔')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录'),
        content: const Text('删除后不可恢复，确定吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await ref
          .read(transactionRepositoryProvider)
          .remove(widget.transactionId!);
      ref.invalidate(monthlyTxProvider);
      ref.invalidate(accountsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final tagsAsync = ref.watch(tagsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑记录' : '记一笔'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: _loadingDetail
          ? const Center(child: CircularProgressIndicator())
          : accountsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorState(
                message: '$e',
                onRetry: () => ref.invalidate(accountsProvider),
              ),
              data: (accounts) {
                // 调整余额(type=1)：网页端才能改金额，App 只给看+删，绝不乱写
                if (_type == TxType.modifyBalance) {
                  return _buildAdjustOnlyView(accounts, theme);
                }

                final flatAccounts = _flattenAccounts(accounts);
                final source = _accountById(accounts, _sourceAccountId);

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // ---- 类型 ----
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                          value: TxType.expense,
                          label: Text('支出'),
                          icon: Icon(Icons.remove_circle_outline),
                        ),
                        ButtonSegment(
                          value: TxType.income,
                          label: Text('收入'),
                          icon: Icon(Icons.add_circle_outline),
                        ),
                        ButtonSegment(
                          value: TxType.transfer,
                          label: Text('转账'),
                          icon: Icon(Icons.swap_horiz),
                        ),
                      ],
                      selected: {_type},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() {
                        _type = s.first;
                        _categoryId = ''; // 类型换了分类就不匹配了
                      }),
                    ),
                    const SizedBox(height: 20),

                    // ---- 金额 ----
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Row(
                          children: [
                            Text(
                              source?.currency ?? '金额',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _amountCtrl,
                                autofocus: !isEditing,
                                keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}$'),
                                  ),
                                ],
                                style: theme.textTheme.headlineSmall,
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: '0.00',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ---- 分类 ----
                    // 实测（服务端 isCategoryValid）：**只能选子分类** ——
                    // 一级分类会报 206005，hidden 会报 206006，type 不匹配报 206002；
                    // 转账也必须选（type=3），不能传空串（Go `,string` int64 直接 200000）。
                    Text(
                      _categoryTypeName(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    categoriesAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(8),
                        child: LinearProgressIndicator(),
                      ),
                      error: (e, _) => Text('分类加载失败：$e'),
                      data: (categories) {
                        final groups = _categoryGroups(categories);
                        if (groups.isEmpty) {
                          return const Text('还没有可用的子分类，请先到网页端创建');
                        }

                        final validIds = _validCategoryIds(groups);

                        // 类型刚切换/数据刚到位时，自动预选该类型下第一个子分类
                        if (!validIds.contains(_categoryId)) {
                          final first = groups.first.value.first.id;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted && !validIds.contains(_categoryId)) {
                              setState(() => _categoryId = first);
                            }
                          });
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final group in groups) ...[
                              Text(
                                group.key.name,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final c in group.value)
                                    ChoiceChip(
                                      label: Text(c.name),
                                      selected: _categoryId == c.id,
                                      selectedColor: _safeColor(c.color)
                                          .withValues(alpha: 0.25),
                                      onSelected: (_) =>
                                          setState(() => _categoryId = c.id),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    // ---- 账户 ----
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.account_balance_wallet_outlined),
                      title: const Text('转出账户'),
                      subtitle: Text(
                        source == null
                            ? '请选择'
                            : '${source.name} · ${source.currency}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _pickAccount(
                        accounts: flatAccounts,
                        isDestination: false,
                      ),
                    ),
                    if (_type == TxType.transfer) ...[
                      const Divider(),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.savings_outlined),
                        title: const Text('转入账户'),
                        subtitle: Text(
                          _destinationAccountId.isEmpty
                              ? '请选择'
                              : _accountById(accounts, _destinationAccountId)
                                      ?.name ??
                                  '请选择',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _pickAccount(
                          accounts: flatAccounts,
                          isDestination: true,
                        ),
                      ),
                    ],
                    const Divider(),

                    // ---- 时间 ----
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule),
                      title: const Text('时间'),
                      subtitle: Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(_time),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickTime,
                    ),
                    const Divider(),

                    // ---- 标签 ----
                    tagsAsync.when(
                      loading: () => const SizedBox.shrink(),
                      error: (e, _) => const SizedBox.shrink(),
                      data: (tags) {
                        if (tags.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 12),
                            Text(
                              '标签',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final t in tags)
                                  FilterChip(
                                    label: Text(t.name),
                                    selected: _tagIds.contains(t.id),
                                    onSelected: (sel) => setState(() {
                                      if (sel) {
                                        _tagIds.add(t.id);
                                      } else {
                                        _tagIds.remove(t.id);
                                      }
                                    }),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        );
                      },
                    ),

                    // ---- 备注 ----
                    TextField(
                      controller: _commentCtrl,
                      maxLength: 255,
                      decoration: const InputDecoration(
                        labelText: '备注',
                        prefixIcon: Icon(Icons.notes_outlined),
                        counterText: '',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('隐藏金额'),
                      subtitle: const Text('列表里显示为 ***'),
                      value: _hideAmount,
                      onChanged: (v) => setState(() => _hideAmount = v),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 24),

                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isEditing ? '保存修改' : '记账'),
                    ),
                    const SizedBox(height: 32),
                  ],
                );
              },
            ),
    );
  }

  /// 当前交易类型对应的分类 type（CATEGORY_TYPE_*：1 收入 2 支出 3 转账）。
  /// 注意和交易类型 TxType（2 收入 3 支出 4 转账）**不同源**，别混用。
  int _categoryTypeOf(int txType) {
    if (txType == TxType.income) return 1;
    if (txType == TxType.transfer) return 3;
    return 2;
  }

  String _categoryTypeName() => switch (_type) {
        TxType.income => '收入分类',
        TxType.transfer => '转账分类',
        _ => '支出分类',
      };

  /// 按一级分类分组，只保留**子分类**（服务端规定一级分类不可用于记账）；
  /// 一级/子级只要 hidden 就整组剔除（服务端还会校验父分类也不 hidden）。
  List<MapEntry<Category, List<Category>>> _categoryGroups(
    List<Category> categories,
  ) {
    final wanted = _categoryTypeOf(_type);
    final out = <MapEntry<Category, List<Category>>>[];

    for (final parent in categories) {
      if (parent.type != wanted || parent.hidden) continue;
      final children = Category.flatten(parent.children)
          .where((e) => !e.key.hidden && e.key.type == wanted)
          .map((e) => e.key)
          .toList();
      if (children.isNotEmpty) out.add(MapEntry(parent, children));
    }
    return out;
  }

  static Set<String> _validCategoryIds(
    List<MapEntry<Category, List<Category>>> groups,
  ) =>
      groups.expand((g) => g.value.map((c) => c.id)).toSet();

  /// 「调整余额」(type=1) 记录的只读视图。
  ///
  /// 服务端对这类记录有特殊约束（`isCategoryValid`：categoryId 必须为 0，
  /// 否则 `ErrBalanceModificationTransactionCannotSetCategory`），金额语义是
  /// "调到某值" 的差额 —— MVP 不猜它的写入规则，只给看和删。
  Widget _buildAdjustOnlyView(List<Account> accounts, ThemeData theme) {
    final account = _accountById(accounts, _sourceAccountId);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 32),
        Icon(Icons.tune, size: 48, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Text(
          '余额调整记录',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kvRow(theme, '账户', account?.name ?? '—'),
                _kvRow(
                  theme,
                  '金额',
                  '${account?.currency ?? ''} ${_amountCtrl.text}',
                ),
                _kvRow(
                  theme,
                  '时间',
                  DateFormat('yyyy-MM-dd HH:mm').format(_time),
                ),
                if (_commentCtrl.text.isNotEmpty)
                  _kvRow(theme, '备注', _commentCtrl.text),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '这类记录由"把账户余额改到某个值"生成，MVP 暂不支持在 App 里修改金额，'
          '只能删除后到网页端重新调整。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          onPressed: _delete,
          icon: const Icon(Icons.delete_outline),
          label: const Text('删除这条记录'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _kvRow(ThemeData theme, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(key, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  static List<Account> _flattenAccounts(List<Account> accounts) {
    final out = <Account>[];

    void walk(List<Account> items) {
      for (final a in items) {
        out.add(a);
        walk(a.subAccounts);
      }
    }

    walk(accounts);
    return out;
  }

  Account? _accountById(List<Account> accounts, String id) {
    if (id.isEmpty) return null;
    for (final a in _flattenAccounts(accounts)) {
      if (a.id == id) return a;
    }
    return null;
  }

  static Color _accountColor(Account account) {
    final hex = account.color.replaceFirst('#', '');
    if (hex.length != 6) return const Color(0xFF3B7DD8);
    final value = int.tryParse(hex, radix: 16);
    return value == null
        ? const Color(0xFF3B7DD8)
        : Color(0xFF000000 | value);
  }

  static Color _safeColor(String hex) {
    if (hex.length != 6) return const Color(0xFF6B7280);
    final value = int.tryParse(hex, radix: 16);
    return value == null
        ? const Color(0xFF6B7280)
        : Color(0xFF000000 | value);
  }
}
