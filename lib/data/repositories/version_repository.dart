import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../dto/misc_dto.dart';

final versionProvider = FutureProvider<VersionInfo>((ref) async {
  final api = ref.watch(apiClientProvider);
  final result = await api.get('/api/v1/systems/version.json');
  return VersionInfo.fromJson(result as Map<String, dynamic>);
});
