import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/version_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverUrl = ref.watch(serverUrlProvider);
    final versionAsync = ref.watch(versionProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const _Header(title: '服务端'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('服务器地址'),
            subtitle: Text(serverUrl),
          ),
          versionAsync.when(
            loading: () => const ListTile(
              leading: Icon(Icons.system_update_outlined),
              title: Text('版本检查中…'),
            ),
            error: (e, _) => ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('版本检查失败'),
              subtitle: Text('$e'),
            ),
            data: (info) => ListTile(
              leading: const Icon(Icons.system_update_outlined),
              title: Text('服务端版本 ${info.version}'),
              subtitle: Text(
                info.upToDate ? '已是最新版本' : '有新版本 ${info.latestVersion}',
              ),
            ),
          ),
          const Divider(),
          const _Header(title: '应用'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text(
              'Flutter 原生客户端（Android 优先）\n'
              '记账表单与统计图表按 Phase 1 计划推进',
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('退出登录'),
                    content: const Text('退出后需要重新输入用户名密码。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('退出'),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await ref.read(authRepositoryProvider).logout();
                  // TokenStore 变更 → GoRouter 自动跳登录页
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

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
