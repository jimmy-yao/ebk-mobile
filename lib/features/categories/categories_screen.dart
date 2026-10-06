import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/app_exception.dart';
import '../../data/dto/misc_dto.dart';
import '../../data/repositories/category_repository.dart';
import '../accounts/accounts_screen.dart';
import 'category_options.dart';

/// 分类管理：三个类型 Tab，一级分类卡片 + 缩进的二级，菜单里增/改/隐藏/删。
///
/// 写契约（源码 `pkg/api/transaction_categories.go`、`services/transaction_categories.go`）：
/// * **只有两级** —— 二级下面再挂会报 `206004 cannot add to secondary ...`
/// * `modify` 请求体**没有 `type`**（类型建好不可改），`parentId` 也必须原样
///   回传（一级↔二级互转报 `206007`/`206008`）
/// * **删除一级会连子分类一起软删**；只要有任何流水/模板引用（含子级）
///   就报 `206006 transaction category is in use and cannot be deleted`
/// * 所有写操作都放在**模态对话框**里做，避免列表刷新把 ref 换掉后失效
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: kCategoryTypes.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('分类管理'),
          bottom: TabBar(
            tabs: [
              for (final t in kCategoryTypes) Tab(text: t.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final t in kCategoryTypes) _CategoryTab(type: t.value),
          ],
        ),
      ),
    );
  }
}

class _CategoryTab extends ConsumerWidget {
  const _CategoryTab({required this.type});

  final int type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: errorMessageOf(e),
          onRetry: () => ref.invalidate(categoriesProvider),
        ),
        data: (all) {
          final primary = all
              .where((c) => c.type == type && c.isPrimary)
              .toList(growable: false);

          if (primary.isEmpty) {
            return const Center(child: Text('还没有分类，点右下角 ＋ 新建一个'));
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(categoriesProvider),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final parent in primary)
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _CategoryRow(category: parent, depth: 0),
                        for (final child in parent.children)
                          _CategoryRow(category: child, depth: 1),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Text(
                    '分类只有两级；删除一级分类会连同其子分类一起删除。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => CategoryEditDialog(type: type, parentId: '0'),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

enum _RowAction { addChild, edit, hide, unhide, delete }

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.depth});

  final Category category;

  /// 0 = 一级，1 = 二级
  final int depth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = categoryColorOf(category.color);

    return ListTile(
      contentPadding: EdgeInsets.only(left: 12 + depth * 24, right: 4),
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: color.withValues(alpha: 0.18),
        child: Icon(
          categoryIconOf(category.icon, category.type).icon,
          size: 18,
          color: color,
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text(category.name)),
          if (category.hidden) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('隐藏', style: theme.textTheme.labelSmall),
            ),
          ],
        ],
      ),
      subtitle: depth == 0 && category.children.isNotEmpty
          ? Text(
              '${category.children.length} 个子分类',
              style: theme.textTheme.bodySmall,
            )
          : null,
      onTap: () => _run(context, _RowAction.edit),
      trailing: PopupMenuButton<_RowAction>(
        icon: const Icon(Icons.more_vert),
        onSelected: (action) => _run(context, action),
        itemBuilder: (_) => [
          // 二级不能再挂子级（服务端 206004）
          if (depth == 0)
            const PopupMenuItem(
              value: _RowAction.addChild,
              child: Text('添加子分类'),
            ),
          const PopupMenuItem(value: _RowAction.edit, child: Text('编辑')),
          PopupMenuItem(
            value: category.hidden ? _RowAction.unhide : _RowAction.hide,
            child: Text(category.hidden ? '取消隐藏' : '隐藏'),
          ),
          const PopupMenuItem(value: _RowAction.delete, child: Text('删除')),
        ],
      ),
    );
  }

  void _run(BuildContext context, _RowAction action) {
    switch (action) {
      case _RowAction.addChild:
        showDialog<void>(
          context: context,
          builder: (_) => CategoryEditDialog(
            type: category.type,
            parentId: category.id,
          ),
        );
      case _RowAction.edit:
        showDialog<void>(
          context: context,
          builder: (_) => CategoryEditDialog(existing: category),
        );
      case _RowAction.hide:
      case _RowAction.unhide:
        showDialog<void>(
          context: context,
          builder: (_) => CategoryHideDialog(
            category: category,
            hidden: !category.hidden,
          ),
        );
      case _RowAction.delete:
        showDialog<void>(
          context: context,
          builder: (_) => CategoryDeleteDialog(category: category),
        );
    }
  }
}

/// 新建/编辑分类。`existing == null` 为新建。
class CategoryEditDialog extends ConsumerStatefulWidget {
  const CategoryEditDialog({
    super.key,
    this.existing,
    this.type,
    this.parentId,
  }) : assert(existing != null || type != null);

  final Category? existing;

  /// 新建时的分类类型（1 收入 / 2 支出 / 3 转账），编辑时忽略（不可改）
  final int? type;

  /// 新建时的父分类 id（`"0"` = 一级），编辑时忽略（层级不可改）
  final String? parentId;

  @override
  ConsumerState<CategoryEditDialog> createState() =>
      _CategoryEditDialogState();
}

class _CategoryEditDialogState extends ConsumerState<CategoryEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _commentCtrl;

  late int _icon;
  late int _iconType;
  late String _color;
  late bool _hidden;

  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;
  int get _type => widget.existing?.type ?? widget.type!;
  String get _parentId => widget.existing?.parentId ?? widget.parentId!;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _commentCtrl = TextEditingController(text: e?.comment ?? '');
    _iconType = e?.iconType ?? 0;
    _icon = e?.icon ?? categoryIconsOf(_type).first.id;
    _color = (e != null && e.color.length == 6)
        ? e.color
        : kCategoryColors.first;
    _hidden = e?.hidden ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '名称不能为空');
      return;
    }
    if (name.length > 64) {
      setState(() => _error = '名称最多 64 个字符');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(categoryRepositoryProvider);
    try {
      if (_isEditing) {
        // 类型与层级都不许改：parentId 原样回传
        await repo.modifyCategory(
          id: widget.existing!.id,
          name: name,
          parentId: _parentId,
          icon: _icon,
          iconType: _iconType,
          color: _color,
          comment: _commentCtrl.text.trim(),
          hidden: _hidden,
        );
      } else {
        await repo.addCategory(
          name: name,
          type: _type,
          parentId: _parentId,
          icon: _icon,
          iconType: _iconType,
          color: _color,
          comment: _commentCtrl.text.trim(),
        );
      }
      ref.invalidate(categoriesProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessageOf(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCustomIcon = _iconType == 1;

    return AlertDialog(
      title: Text(_isEditing ? '编辑分类' : '新建分类'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtrl,
                enabled: !_saving,
                autofocus: !_isEditing,
                maxLength: 64,
                decoration: const InputDecoration(
                  labelText: '名称',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Text('图标', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              if (isCustomIcon)
                Text(
                  '当前是自定义图标，保持原样（在网页端更换）。',
                  style: theme.textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in categoryIconsOf(_type))
                      _IconPick(
                        icon: option.icon,
                        label: option.label,
                        selected: option.id == _icon,
                        onTap: () => setState(() => _icon = option.id),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              Text('颜色', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final hex in kCategoryColors)
                    _ColorPick(
                      hex: hex,
                      selected: hex == _color,
                      onTap: () => setState(() => _color = hex),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _commentCtrl,
                enabled: !_saving,
                maxLength: 255,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '备注（可选）',
                  counterText: '',
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('隐藏'),
                  subtitle: const Text('隐藏后记账时不再显示，已有明细不受影响'),
                  value: _hidden,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _hidden = v),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? '保存' : '创建'),
        ),
      ],
    );
  }
}

/// 隐藏/取消隐藏（模态里做，避免 ref 失效）
class CategoryHideDialog extends ConsumerStatefulWidget {
  const CategoryHideDialog({
    super.key,
    required this.category,
    required this.hidden,
  });

  final Category category;
  final bool hidden;

  @override
  ConsumerState<CategoryHideDialog> createState() =>
      _CategoryHideDialogState();
}

class _CategoryHideDialogState extends ConsumerState<CategoryHideDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(categoryRepositoryProvider)
          .hideCategory(widget.category.id, widget.hidden);
      ref.invalidate(categoriesProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessageOf(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(widget.hidden ? '隐藏分类' : '取消隐藏'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.hidden
                ? '隐藏「${widget.category.name}」后，记账时的分类选择里不再显示它，已有明细不受影响。'
                : '恢复显示「${widget.category.name}」。',
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _run,
          child: Text(widget.hidden ? '隐藏' : '恢复'),
        ),
      ],
    );
  }
}

/// 删除分类（**连子分类一起删**）
class CategoryDeleteDialog extends ConsumerStatefulWidget {
  const CategoryDeleteDialog({super.key, required this.category});

  final Category category;

  @override
  ConsumerState<CategoryDeleteDialog> createState() =>
      _CategoryDeleteDialogState();
}

class _CategoryDeleteDialogState extends ConsumerState<CategoryDeleteDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(categoryRepositoryProvider)
          .removeCategory(widget.category.id);
      ref.invalidate(categoriesProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = errorMessageOf(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final childrenCount = widget.category.children.length;

    return AlertDialog(
      title: const Text('删除分类'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            childrenCount > 0
                ? '删除「${widget.category.name}」会连同其下 $childrenCount 个子分类一起删除。'
                : '删除「${widget.category.name}」。',
          ),
          const SizedBox(height: 8),
          Text(
            '被明细或模板引用的分类无法删除。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _busy ? null : _run,
          child: const Text('删除'),
        ),
      ],
    );
  }
}

class _IconPick extends StatelessWidget {
  const _IconPick({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: selected
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPick extends StatelessWidget {
  const _ColorPick({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32,
        height: 32,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: categoryColorOf(hex),
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 3)
              : null,
        ),
      ),
    );
  }
}
