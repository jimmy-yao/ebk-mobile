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
  });

  final String id;
  final String name;
  /// 2=收入 3=支出（与交易类型同值域，0/1 为系统预留）
  final int type;
  final String color;
  final int icon;
  final bool hidden;
  final String parentId;
  final List<Category> children;

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
        children: (json['children'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(Category.fromJson)
                .toList() ??
            const [],
      );
}

class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.color,
    required this.visible,
    this.count,
  });

  final String id;
  final String name;
  final String color;
  final bool visible;
  final int? count;

  factory Tag.fromJson(Map<String, dynamic> json) => Tag(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        color: json['color']?.toString() ?? '',
        visible: json['visible'] != false,
        count: json['count'] is int ? json['count'] as int : null,
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
