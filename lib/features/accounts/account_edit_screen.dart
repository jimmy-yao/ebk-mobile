import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/util/money.dart';
import '../../data/dto/account_dto.dart';
import '../../data/repositories/account_repository.dart';
import 'account_options.dart';
import 'accounts_screen.dart';

/// 账户表单：`accountId == null` 为新建，否则为编辑（带删除/隐藏）。
///
/// 写契约（源码 `models.AccountCreateRequest` / `AccountModifyRequest` + 实测）：
/// * 新建：初始余额**非 0 必须同时给 `balanceTime`**（本页默认取当前时间）
/// * 编辑：**不能传 `balance`/`balanceTime`**（`204021 not supported to
///   modify account balance`，余额只能由明细流水推算）
/// * `icon` 字符串化 int64、`color` 6 位不带 #、`currency` 3 位
class AccountEditScreen extends ConsumerStatefulWidget {
  const AccountEditScreen({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<AccountEditScreen> createState() => _AccountEditScreenState();
}

class _AccountEditScreenState extends ConsumerState<AccountEditScreen> {
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();

  int _category = 1;
  int _icon = 1;
  String _color = '3B7DD8';
  String _currency = 'CNY';
  bool _hidden = false;

  Account? _existing;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  bool get isEditing => widget.accountId != null;

  @override
  void initState() {
    super.initState();
    if (isEditing) _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 优先用已缓存的列表（省一次请求），找不到再单查
      Account? found;
      final cached = await ref.read(accountsProvider.future);
      for (final a in cached) {
        if (a.id == widget.accountId) {
          found = a;
          break;
        }
      }
      found ??= await ref
          .read(accountRepositoryProvider)
          .get(widget.accountId!);
      final account = found;
      if (account == null) throw Exception('账户不存在或已删除');

      if (!mounted) return;
      setState(() {
        _existing = account;
        _nameCtrl.text = account.name;
        _category = account.category;
        _icon = account.icon;
        _color = account.color;
        _currency = account.currency;
        _commentCtrl.text = account.comment;
        _hidden = account.hidden;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pickCurrency() async {
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择币种'),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.6,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final (code, label) in kCommonCurrencies)
                    ListTile(
                      leading: _currency == code
                          ? Icon(Icons.radio_button_checked,
                              color: Theme.of(context).colorScheme.primary)
                          : const Icon(Icons.radio_button_unchecked,
                              color: Colors.transparent),
                      title: Text('$code · $label'),
                      onTap: () => Navigator.of(context).pop(code),
                    ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('其他币种（3 位代码）'),
                    onTap: () async {
                      final custom = await showDialog<String>(
                        context: context,
                        builder: (context) => const _CustomCurrencyDialog(),
                      );
                      if (custom != null && context.mounted) {
                        Navigator.of(context).pop(custom);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (picked != null && mounted) {
      setState(() => _currency = picked);
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final comment = _commentCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => _error = '请填写账户名称');
      return;
    }
    if (name.length > 64) {
      setState(() => _error = '名称最多 64 个字符');
      return;
    }
    if (comment.length > 255) {
      setState(() => _error = '备注最多 255 个字符');
      return;
    }

    // 余额只在**新建**时提交；编辑时服务端见到 balance 键就报 204021
    var balance = 0;
    if (!isEditing && _balanceCtrl.text.trim().isNotEmpty) {
      balance = parseDecimalToMinor(_balanceCtrl.text.trim());
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    try {
      final repo = ref.read(accountRepositoryProvider);
      if (isEditing) {
        await repo.modify(
          id: widget.accountId!,
          name: name,
          category: _category,
          icon: _icon,
          iconType: 0,
          color: _color,
          currency: _currency,
          comment: comment,
          hidden: _hidden,
        );
      } else {
        await repo.add(
          name: name,
          category: _category,
          icon: _icon,
          iconType: 0,
          color: _color,
          currency: _currency,
          balance: balance,
          comment: comment,
        );
      }

      ref.invalidate(accountsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isEditing ? '账户已更新' : '账户已创建')),
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
        title: const Text('删除这个账户'),
        content: const Text('账户下还有明细时服务端会拒绝删除。确定继续吗？'),
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
      await ref.read(accountRepositoryProvider).remove(widget.accountId!);
      ref.invalidate(accountsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账户已删除')),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? '编辑账户' : '新建账户'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除账户',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _nameCtrl,
                  maxLength: 64,
                  decoration: const InputDecoration(
                    labelText: '账户名称',
                    prefixIcon: Icon(Icons.badge_outlined),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 8),

                // ---- 类别（负债类别的余额在服务端算负数方向） ----
                Text(
                  '类别',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in kAccountCategories)
                      ChoiceChip(
                        label: Text(c.liability ? '${c.label}·负债' : c.label),
                        selected: _category == c.value,
                        selectedColor:
                            theme.colorScheme.primaryContainer,
                        onSelected: (_) => setState(() => _category = c.value),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---- 币种 ----
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.currency_exchange),
                  title: const Text('币种'),
                  subtitle: Text(
                    '$_currency · ${_currencyLabel(_currency)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickCurrency,
                ),
                const Divider(),

                if (!isEditing) ...[
                  // ---- 初始余额（仅新建） ----
                  TextField(
                    controller: _balanceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}$'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      labelText: '初始余额',
                      helperText: '留空按 0；时间取当前时刻（服务端要求余额非 0 必须给 balanceTime）',
                    ),
                  ),
                ] else ...[
                  // ---- 当前余额（只读，改不了） ----
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_balance_outlined),
                    title: const Text('当前余额'),
                    subtitle: Text(
                      _existing == null
                          ? '—'
                          : '${formatAmount(_existing!.balanceMinor, _existing!.currency)} $_currency（由明细流水推算，不能直接改）',
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // ---- 图标 ----
                Text(
                  '图标',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in kAccountIcons)
                      ChoiceChip(
                        avatar: Icon(
                          o.icon,
                          size: 18,
                          color: _icon == o.id
                              ? theme.colorScheme.onPrimaryContainer
                              : accountColorOf(_color),
                        ),
                        label: Text(o.label),
                        selected: _icon == o.id,
                        selectedColor: theme.colorScheme.primaryContainer,
                        onSelected: (_) => setState(() => _icon = o.id),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // ---- 颜色 ----
                Text(
                  '颜色',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final hex in kAccountColors)
                      GestureDetector(
                        onTap: () => setState(() => _color = hex),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accountColorOf(hex),
                            shape: BoxShape.circle,
                            border: _color == hex
                                ? Border.all(
                                    color: theme.colorScheme.primary,
                                    width: 3,
                                  )
                                : null,
                          ),
                          child: _color == hex
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 18)
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _commentCtrl,
                  maxLength: 255,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    prefixIcon: Icon(Icons.notes_outlined),
                    counterText: '',
                  ),
                ),

                if (isEditing)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('隐藏账户'),
                    subtitle: const Text('隐藏后不在账户页展示（数据保留）'),
                    value: _hidden,
                    onChanged: (v) => setState(() => _hidden = v),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isEditing ? '保存修改' : '创建账户'),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  static String _currencyLabel(String code) {
    for (final (c, label) in kCommonCurrencies) {
      if (c == code) return label;
    }
    return '自定义';
  }
}

class _CustomCurrencyDialog extends StatefulWidget {
  const _CustomCurrencyDialog();

  @override
  State<_CustomCurrencyDialog> createState() => _CustomCurrencyDialogState();
}

class _CustomCurrencyDialogState extends State<_CustomCurrencyDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义币种'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        maxLength: 3,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'ISO 4217 代码（3 位）',
          hintText: '例如 VND',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final code = _ctrl.text.trim().toUpperCase();
            if (code.length == 3) Navigator.of(context).pop(code);
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}
