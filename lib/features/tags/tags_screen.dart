import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/app_exception.dart';
import '../../data/dto/misc_dto.dart';
import '../../data/repositories/category_repository.dart';
import '../accounts/accounts_screen.dart';

/// 标签管理：列表 + 新建/改名/隐藏/删除。
///
/// 契约（`models.TransactionTag*Request`）：
/// * 只有 `name`（≤64）与可选 `groupId`，**没有颜色字段**
/// * `id`/`groupId` 都是字符串化 int64，未分组填 `"0"`
/// * 被明细引用的标签删不掉：`207004 transaction tag is in use and cannot
///   be deleted`
/// * 标签组（`tags/groups/*`）Phase 2 再做，这里统一落在未分组
///
/// 与分类页一样，写操作都在模态对话框里完成（ref 才不会在 await 中失效）。
class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('标签管理')),
      body: tagsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorState(
          message: errorMessageOf(e),
          onRetry: () => ref.invalidate(tagsProvider),
        ),
        data: (tags) {
          if (tags.isEmpty) {
            return const Center(child: Text('还没有标签，点右下角 ＋ 新建一个'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tagsProvider),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [for (final tag in tags) _TagTile(tag: tag)],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const TagEditDialog(),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}

enum _TagAction { rename, hide, unhide, delete }

class _TagTile extends StatelessWidget {
  const _TagTile({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(Icons.label_outline,
            size: 18, color: theme.colorScheme.onPrimaryContainer),
      ),
      title: Text(tag.name),
      subtitle: tag.hidden
          ? Text('已隐藏', style: theme.textTheme.bodySmall)
          : null,
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => TagEditDialog(existing: tag),
      ),
      trailing: PopupMenuButton<_TagAction>(
        icon: const Icon(Icons.more_vert),
        onSelected: (action) => _run(context, action),
        itemBuilder: (_) => [
          const PopupMenuItem(value: _TagAction.rename, child: Text('改名')),
          PopupMenuItem(
            value: tag.hidden ? _TagAction.unhide : _TagAction.hide,
            child: Text(tag.hidden ? '取消隐藏' : '隐藏'),
          ),
          const PopupMenuItem(value: _TagAction.delete, child: Text('删除')),
        ],
      ),
    );
  }

  void _run(BuildContext context, _TagAction action) {
    switch (action) {
      case _TagAction.rename:
        showDialog<void>(
          context: context,
          builder: (_) => TagEditDialog(existing: tag),
        );
      case _TagAction.hide:
      case _TagAction.unhide:
        showDialog<void>(
          context: context,
          builder: (_) => TagHideDialog(tag: tag, hidden: !tag.hidden),
        );
      case _TagAction.delete:
        showDialog<void>(
          context: context,
          builder: (_) => TagDeleteDialog(tag: tag),
        );
    }
  }
}

/// 新建/改名标签
class TagEditDialog extends ConsumerStatefulWidget {
  const TagEditDialog({super.key, this.existing});

  final Tag? existing;

  @override
  ConsumerState<TagEditDialog> createState() => _TagEditDialogState();
}

class _TagEditDialogState extends ConsumerState<TagEditDialog> {
  late final TextEditingController _nameCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '标签名不能为空');
      return;
    }
    if (name.length > 64) {
      setState(() => _error = '标签名最多 64 个字符');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final repo = ref.read(categoryRepositoryProvider);
    final existing = widget.existing;
    try {
      if (existing == null) {
        await repo.addTag(name: name);
      } else {
        await repo.modifyTag(
          id: existing.id,
          name: name,
          groupId: existing.groupId,
        );
      }
      ref.invalidate(tagsProvider);
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
    final isEditing = widget.existing != null;

    return AlertDialog(
      title: Text(isEditing ? '改名' : '新建标签'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              enabled: !_saving,
              autofocus: !isEditing,
              maxLength: 64,
              decoration: const InputDecoration(
                labelText: '标签名',
                counterText: '',
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
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
              : Text(isEditing ? '保存' : '创建'),
        ),
      ],
    );
  }
}

/// 隐藏/取消隐藏标签
class TagHideDialog extends ConsumerStatefulWidget {
  const TagHideDialog({super.key, required this.tag, required this.hidden});

  final Tag tag;
  final bool hidden;

  @override
  ConsumerState<TagHideDialog> createState() => _TagHideDialogState();
}

class _TagHideDialogState extends ConsumerState<TagHideDialog> {
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
          .hideTag(widget.tag.id, widget.hidden);
      ref.invalidate(tagsProvider);
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
      title: Text(widget.hidden ? '隐藏标签' : '取消隐藏'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.hidden
                ? '隐藏「${widget.tag.name}」后，新建明细时不再显示它，已有明细不受影响。'
                : '恢复显示「${widget.tag.name}」。',
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

/// 删除标签
class TagDeleteDialog extends ConsumerStatefulWidget {
  const TagDeleteDialog({super.key, required this.tag});

  final Tag tag;

  @override
  ConsumerState<TagDeleteDialog> createState() => _TagDeleteDialogState();
}

class _TagDeleteDialogState extends ConsumerState<TagDeleteDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(categoryRepositoryProvider).removeTag(widget.tag.id);
      ref.invalidate(tagsProvider);
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
      title: const Text('删除标签'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('删除「${widget.tag.name}」。'),
          const SizedBox(height: 8),
          Text(
            '被明细引用的标签无法删除。',
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
