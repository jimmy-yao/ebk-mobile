/// 分类 / 标签管理页的界面冒烟：渲染、Tab 切换、真实提交 payload，
/// 以及服务端拒绝（206006 分类被引用）时错误在对话框内联展示。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ebk_mobile/core/network/api_client.dart';
import 'package:ebk_mobile/core/storage/token_store.dart';
import 'package:ebk_mobile/features/categories/categories_screen.dart';
import 'package:ebk_mobile/features/tags/tags_screen.dart';

import 'fakes.dart';

Map<String, dynamic> _cat(
  String id,
  String name,
  int type, {
  String parentId = '0',
  String icon = '1',
  List<Map<String, dynamic>> children = const [],
}) =>
    {
      'id': id,
      'name': name,
      'parentId': parentId,
      'type': type,
      'icon': icon,
      'iconType': 0,
      'color': 'E8A33D',
      'comment': '',
      'displayOrder': 1,
      'hidden': false,
      if (children.isNotEmpty) 'subCategories': children,
    };

final _categoriesJson = <String, dynamic>{
  '2': [
    _cat(
      '200',
      '食品饮料',
      2,
      icon: '1',
      children: [
        _cat('201', '食品', 2, parentId: '200', icon: '2'),
      ],
    ),
    _cat('290', '交通', 2, icon: '330'),
  ],
  '1': [
    _cat('2000', '工作', 1, icon: '2000'),
  ],
  '3': [
    _cat('4000', '划转', 3, icon: '4000'),
  ],
};

final _tagsJson = <dynamic>[
  {'id': '7', 'name': '旅行', 'groupId': '0', 'displayOrder': 1, 'hidden': false},
];

FakeHttpAdapter _categoriesAdapter() => FakeHttpAdapter((path, body) {
      if (path.endsWith('/transaction/categories/list.json')) {
        return ok(_categoriesJson);
      }
      if (path.endsWith('/categories/add.json')) return ok({'id': '300'});
      if (path.endsWith('/categories/modify.json')) return ok(true);
      if (path.endsWith('/categories/hide.json')) return ok(true);
      if (path.endsWith('/categories/delete.json')) {
        // "食品饮料" 被明细引用 → 服务端拒绝
        if (body?['id'] == '200') {
          return <String, dynamic>{
            'success': false,
            'errorCode': '206006',
            'errorMessage': 'transaction category is in use and cannot be deleted',
          };
        }
        return ok(true);
      }
      if (path.endsWith('/transaction/tags/list.json')) return ok(_tagsJson);
      if (path.endsWith('/tags/add.json')) return ok({'id': '8'});
      if (path.endsWith('/tags/modify.json')) return ok(true);
      if (path.endsWith('/tags/hide.json')) return ok(true);
      if (path.endsWith('/tags/delete.json')) return ok(true);
      return ok(null);
    });

ProviderContainer _container(FakeHttpAdapter adapter) {
  final client = ApiClient(
    baseUrl: 'https://fake.test',
    tokenStore: TokenStore(),
  );
  client.dio.httpClientAdapter = adapter;

  return ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(client),
      tokenStoreProvider.overrideWithValue(TokenStore()),
    ],
  );
}

Widget _wrap(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(container: container, child: MaterialApp(home: child));

void main() {
  testWidgets('分类页：三个类型 Tab，一级与二级都渲染出来', (tester) async {
    final container = _container(_categoriesAdapter());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, const CategoriesScreen()));
    await tester.pumpAndSettle();

    for (final tab in ['支出', '收入', '转账']) {
      expect(find.text(tab), findsWidgets, reason: '$tab Tab 存在');
    }
    expect(find.text('食品饮料'), findsOneWidget, reason: '一级分类');
    expect(find.text('食品'), findsOneWidget, reason: '二级分类');
    expect(find.text('1 个子分类'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // 切到"收入"Tab
    await tester.tap(find.text('收入'));
    await tester.pumpAndSettle();
    expect(find.text('工作'), findsOneWidget);
    expect(find.text('食品饮料'), findsNothing);
  });

  testWidgets('新建分类：提交的 payload 用字符串 id 且带 type', (tester) async {
    final adapter = _categoriesAdapter();
    final container = _container(adapter);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, const CategoriesScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('新建分类'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '  房租水电  ');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    final body = adapter.lastCallFor('/categories/add.json').body!;
    expect(body['name'], '房租水电', reason: '提交前要 trim');
    expect(body['type'], 2, reason: '默认落在当前"支出"Tab');
    expect(body['parentId'], '0');
    expect(body['icon'], '1');
    expect(body['color'], 'E8A33D');
    expect(body.containsKey('hidden'), isFalse);
    expect(find.text('新建分类'), findsNothing, reason: '成功后对话框关闭');
  });

  testWidgets('删除被明细引用的分类 → 206006 就地显示，对话框不关', (tester) async {
    final container = _container(_categoriesAdapter());
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, const CategoriesScreen()));
    await tester.pumpAndSettle();

    final row = find.widgetWithText(ListTile, '食品饮料');
    // PopupMenuButton 是泛型类，byType 直接匹配不到，按图标找
    await tester.tap(find.descendant(of: row, matching: find.byIcon(Icons.more_vert)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除分类'), findsOneWidget);
    expect(find.textContaining('会连同其下 1 个子分类'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(
      find.text('transaction category is in use and cannot be deleted'),
      findsOneWidget,
      reason: '服务端 errorMessage 要原样显示出来',
    );
    expect(find.text('删除分类'), findsOneWidget, reason: '失败后对话框保持打开');
  });

  testWidgets('标签页：列表渲染 + 新建 payload 只有 name/groupId', (tester) async {
    final adapter = _categoriesAdapter();
    final container = _container(adapter);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, const TagsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('旅行'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '日常');
    await tester.tap(find.widgetWithText(FilledButton, '创建'));
    await tester.pumpAndSettle();

    expect(
      adapter.lastCallFor('/tags/add.json').body,
      {'groupId': '0', 'name': '日常'},
      reason: '标签没有颜色字段，未分组 groupId=0',
    );
    expect(find.text('新建标签'), findsNothing);
  });

  testWidgets('标签改名：带上 id 与原 groupId', (tester) async {
    final adapter = _categoriesAdapter();
    final container = _container(adapter);
    addTearDown(container.dispose);

    await tester.pumpWidget(_wrap(container, const TagsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('旅行'));
    await tester.pumpAndSettle();
    expect(find.text('改名'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '旅行计划');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(
      adapter.lastCallFor('/tags/modify.json').body,
      {'id': '7', 'groupId': '0', 'name': '旅行计划'},
    );
  });
}
