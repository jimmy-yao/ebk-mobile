/// 分类 / 标签 / 版本 等小型 DTO
///
/// - `GET /api/v1/transaction/categories/list.json` → TransactionCategoryInfoResponse
/// - `GET /api/v1/transaction/tags/list.json`        → TransactionTagInfoResponse
/// - `GET /api/v1/systems/version.json`              → {version, latestVersion, ...}
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.type,
    required this.color,
    required this.icon,
    required this.hidden,
    required this.parentId,
    required this.children,
    this.comment = '',
    this.iconType = 0,
    this.displayOrder = 0,
  });

  final String id;
  final String name;
  /// 类型（源码 CATEGORY_TYPE_*）：1=收入 2=支出 3=转账
  final int type;
  final String color;
  final int icon;
  final bool hidden;
  final String parentId;
  final List<Category> children;
  final String comment;

  /// 0 = 预置图标，1 = 用户自定义图标
  final int iconType;
  final int displayOrder;

  /// 是否一级分类（`parentId == "0"`）。服务端只有两级
  bool get isPrimary => parentId == '0';

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        type: json['type'] is int ? json['type'] as int : 0,
        color: json['color']?.toString() ?? '',
        icon: json['icon'] is String
            ? (int.tryParse(json['icon'] as String) ?? 0)
            : (json['icon'] is int ? json['icon'] as int : 0),
        hidden: json['hidden'] == true,
        parentId: json['parentId']?.toString() ?? '0',
        comment: json['comment']?.toString() ?? '',
        iconType: json['iconType'] is int ? json['iconType'] as int : 0,
        displayOrder:
            json['displayOrder'] is int ? json['displayOrder'] as int : 0,
        // 服务端字段名是 subCategories（TransactionCategoryInfoResponse）
        children: (json['subCategories'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(Category.fromJson)
                .toList() ??
            const [],
      );

  /// 前序遍历成一维列表，`depth` 供 UI 缩进用
  static List<MapEntry<Category, int>> flatten(List<Category> categories) {
    final out = <MapEntry<Category, int>>[];

    void walk(List<Category> items, int depth) {
      for (final c in items) {
        out.add(MapEntry(c, depth));
        walk(c.children, depth + 1);
      }
    }

    walk(categories, 0);
    return out;
  }
}

class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.groupId,
    required this.hidden,
    this.displayOrder = 0,
  });

  final String id;
  final String name;

  /// 标签组 id（`"0"` = 未分组）。响应字段是 `groupId`
  final String groupId;

  final bool hidden;
  final int displayOrder;

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        groupId: json['groupId']?.toString() ?? '0',
        hidden: json['hidden'] == true,
        displayOrder:
            json['displayOrder'] is int ? json['displayOrder'] as int : 0,
      );
}

class VersionInfo {
  const VersionInfo({
    required this.version,
    required this.latestVersion,
  });

  final String version;
  final String latestVersion;

  bool get upToDate => latestVersion.isEmpty || latestVersion == version;

  factory VersionInfo.fromJson(Map<String, dynamic> json) => VersionInfo(
        version: json['version']?.toString() ?? '',
        latestVersion: json['latestVersion']?.toString() ?? '',
      );
}
