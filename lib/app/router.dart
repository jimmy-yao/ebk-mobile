import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/storage/token_store.dart';
import '../features/accounts/account_edit_screen.dart';
import '../features/accounts/accounts_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/home/home_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/statistics/statistics_screen.dart';
import '../features/tags/tags_screen.dart';
import '../features/transactions/transaction_edit_screen.dart';
import '../features/transactions/transactions_screen.dart';

/// 登录态变化时由 TokenStore.listenable 触发重新 redirect
final routerProvider = Provider<GoRouter>((ref) {
  final tokenStore = ref.watch(tokenStoreProvider);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: tokenStore.listenable,
    redirect: (context, state) {
      final loggedIn = tokenStore.hasToken;
      final atLogin = state.matchedLocation == '/login';

      if (!loggedIn && !atLogin) return '/login';
      if (loggedIn && atLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/accounts/new',
        builder: (context, state) => const AccountEditScreen(),
      ),
      // 分类/标签管理（从设置页进入，全屏压在底部导航之上）
      GoRoute(
        path: '/categories',
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/tags',
        builder: (context, state) => const TagsScreen(),
      ),
      // 统计页（三张图），从首页 AppBar 进入，压在底部导航之上
      GoRoute(
        path: '/statistics',
        builder: (context, state) => const StatisticsScreen(),
      ),
      GoRoute(
        path: '/accounts/:id/edit',
        builder: (context, state) => AccountEditScreen(
          accountId: state.pathParameters['id'],
        ),
      ),
      // 记账表单全屏压在底部导航之上（新建 / 编辑）
      GoRoute(
        path: '/transactions/new',
        builder: (context, state) => const TransactionEditScreen(),
      ),
      GoRoute(
        path: '/transactions/:id/edit',
        builder: (context, state) => TransactionEditScreen(
          transactionId: state.pathParameters['id'],
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/transactions',
              builder: (context, state) => const TransactionsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/accounts',
              builder: (context, state) => const AccountsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
});
