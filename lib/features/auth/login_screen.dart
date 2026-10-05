import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../data/repositories/auth_repository.dart';

/// 登录页：用户名密码 + 可选 2FA 二次输入。
/// 成功后写入 TokenStore，GoRouter 通过 refreshListenable 自动跳到首页。
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _serverCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverCtrl.text = ref.read(serverUrlProvider);
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final server = _serverCtrl.text.trim();
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    if (server.isEmpty || username.isEmpty || password.isEmpty) {
      setState(() => _error = '服务器、用户名和密码都不能为空');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 允许用户改服务器地址（同一 Dio 实例改 baseUrl）
      ref.read(serverUrlProvider.notifier).state = server;
      final repo = ref.read(authRepositoryProvider);
      final result = await repo.login(username, password);

      if (result.needTwoFactor) {
        if (!mounted) return;
        final passcode = await _askPasscode();
        if (passcode == null) {
          setState(() => _loading = false);
          return;
        }
        final token = await repo.verifyTwoFactor(result.token, passcode);
        if (token.isEmpty) {
          setState(() {
            _loading = false;
            _error = '二次校验未返回有效 token';
          });
          return;
        }
        await repo.saveSession(token);
      } else {
        await repo.saveSession(result.token);
      }

      // 成功：路由会因 TokenStore 变更自动跳转，无需手动 navigate
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('AppException', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askPasscode() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('两步验证'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(labelText: '6 位验证码'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('验证'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'ezBookkeeping',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '登录你的记账服务',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _serverCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://example.com',
                    prefixIcon: Icon(Icons.dns_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _userCtrl,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: '密码',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
