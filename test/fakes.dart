import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 一次被录制下来的请求
class FakeCall {
  const FakeCall({
    required this.method,
    required this.path,
    required this.uri,
    this.body,
  });

  final String method;
  final String path;

  /// 完整 URI（含 query），用于断言 `visible_only` 这类查询参数
  final Uri uri;

  /// JSON body（POST 才有）
  final Map<String, dynamic>? body;
}

/// 录制请求、按 `(path, body)` 返回固定 JSON 的假 HTTP adapter。
///
/// 用它可以在**不碰网络**的前提下断言"仓库层真正发出去的 payload"，
/// 这正是契约最容易写错的地方（字段名、字符串化 id、余额是否传等）。
class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);

  final Map<String, dynamic> Function(String path, Map<String, dynamic>? body)
      handler;

  final List<FakeCall> calls = [];

  /// 最后一次同路径的请求
  FakeCall lastCallFor(String pathSuffix) {
    for (var i = calls.length - 1; i >= 0; i--) {
      if (calls[i].path.endsWith(pathSuffix)) return calls[i];
    }
    throw StateError('没有发往 $pathSuffix 的请求（实际：'
        '${calls.map((c) => c.path).join(', ')}）');
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Map<String, dynamic>? body;

    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );
      if (bytes.isNotEmpty) {
        try {
          final decoded = jsonDecode(utf8.decode(bytes));
          if (decoded is Map<String, dynamic>) body = decoded;
        } catch (_) {
          // 非 JSON 请求体（本项目不会出现）
        }
      }
    } else if (options.data is Map<String, dynamic>) {
      body = options.data as Map<String, dynamic>;
    }

    final path = options.uri.path;
    calls.add(FakeCall(
      method: options.method,
      path: path,
      uri: options.uri,
      body: body,
    ));

    final response = handler(path, body);
    // 服务端失败形态：`{success:false, errorCode, errorMessage}` + HTTP 4xx，
    // 假 adapter 照做，才能测到 AppException → 对话框内联报错这条链路
    final status = response['success'] == false ? 400 : 200;
    return ResponseBody.fromString(
      jsonEncode(response),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 统一成功响应
Map<String, dynamic> ok([dynamic result]) => {
      'success': true,
      'result': result ?? <String, dynamic>{},
    };
