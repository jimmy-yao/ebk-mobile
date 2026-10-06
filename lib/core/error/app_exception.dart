/// 服务端统一错误形态（源码 pkg/utils/api.go GetJsonErrorResult）：
/// ```json
/// { "success": false, "errorCode": "...", "errorMessage": "...", "path": "/api/..." }
/// ```
/// HTTP 状态码单独承载语义（401 = token 失效/过期）。
class AppException implements Exception {
  AppException({
    required this.message,
    this.code,
    this.statusCode,
    this.path,
  });

  final String message;
  final String? code;
  final int? statusCode;
  final String? path;

  /// 401：token 失效/过期 → 交给路由踢回登录页
  bool get isUnauthorized => statusCode == 401;

  /// 网络层问题（超时、DNS、断网）而非业务错误
  bool get isNetwork => statusCode == null;

  @override
  String toString() =>
      'AppException($statusCode ${code ?? '-'}): $message';
}

/// 展示给用户的错误文案：业务错误只留服务端的 `errorMessage`，
/// 其余（网络超时、类型错误）原样输出
String errorMessageOf(Object error) =>
    error is AppException ? error.message : '$error';
