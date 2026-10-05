import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../error/app_exception.dart';
import '../storage/token_store.dart';

/// 服务器地址（登录页可改）
final serverUrlProvider =
    StateProvider<String>((ref) => kDefaultServerUrl);

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: ref.watch(serverUrlProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});

/// ezBookkeeping HTTP 客户端。
///
/// 契约要点（均已从源码核实，见 scripts/smoke.sh）：
/// * 成功: `{success:true, result:...}`；本类负责解包，业务层只拿 `result`
/// * 失败: `{success:false, errorCode, errorMessage, path}` + 对应 HTTP 状态
/// * `/api/v1/*` **只认** `Authorization: bearer` header（JWTAuthorizationByHeader）
/// * 必带 `X-Timezone-Offset`（分钟，东向为正，UTC+8 → 480），
///   缺了列表接口直接报 `ErrClientTimezoneOffsetInvalid`
class ApiClient {
  ApiClient({required String baseUrl, required this.tokenStore})
      :
        dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: <String, String>{
              'Accept': 'application/json',
              'Accept-Language': 'zh-CN',
            },
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['X-Timezone-Offset'] =
              DateTime.now().timeZoneOffset.inMinutes;
          options.headers['X-Timezone-Name'] =
              DateTime.now().timeZoneName;
          final token = tokenStore.token;
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    );
  }

  final Dio dio;
  final TokenStore tokenStore;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final data = await _raw(() => dio.get(path, queryParameters: query));
    return _unwrap(data);
  }

  Future<dynamic> post(
    String path, {
    Object? body,
    Map<String, dynamic>? headers,
  }) async {
    final data =
        await _raw(() => dio.post(path, data: body, options: headers != null ? Options(headers: headers) : null));
    return _unwrap(data);
  }

  Future<dynamic> _raw(Future<Response> Function() call) async {
    try {
      final response = await call();
      return response.data;
    } on DioException catch (e) {
      throw _mapError(e);
    }
  }

  dynamic _unwrap(dynamic data) {
    if (data is! Map<String, dynamic>) return data;

    if (data['success'] == true) return data['result'];

    throw AppException(
      message: (data['errorMessage'] as String?) ?? '请求失败',
      code: data['errorCode']?.toString(),
      path: data['path']?.toString(),
    );
  }

  AppException _mapError(DioException e) {
    final status = e.response?.statusCode;
    final body = e.response?.data;

    String? code;
    String message;

    if (body is Map<String, dynamic>) {
      code = body['errorCode']?.toString();
      message = (body['errorMessage'] as String?) ?? e.message ?? '请求失败';
    } else {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          message = '连接超时，请检查网络';
        case DioExceptionType.connectionError:
          message = '无法连接服务器';
        default:
          message = e.message ?? '请求失败';
      }
    }

    // 401：token 失效/过期 → 清掉本地 token，路由会自动踢回登录页
    if (status == 401 && tokenStore.hasToken) {
      tokenStore.clear();
    }

    return AppException(
      message: message,
      code: code,
      statusCode: status,
      path: e.requestOptions.path,
    );
  }
}
