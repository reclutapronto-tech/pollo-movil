import 'dart:io';

import 'package:fieldops_mobile/features/breadcrumbs/domain/breadcrumb_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseBreadcrumbRepository implements BreadcrumbRepository {
  const SupabaseBreadcrumbRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Breadcrumb>> fetchBreadcrumbs({
    required String shiftDate,
    String? userId,
    String? jobId,
  }) async {
    try {
      final params = <String, String>{
        'shift_date': shiftDate,
        if (userId != null) 'user_id': userId,
        if (jobId != null) 'job_id': jobId,
      };

      final queryString = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final response = await _client.functions.invoke(
        'breadcrumbs?$queryString',
        method: HttpMethod.get,
      );

      final data = response.data as Map<String, dynamic>;
      final list = (data['breadcrumbs'] as List<dynamic>?) ?? [];
      return list
          .map((e) => Breadcrumb.fromJson(e as Map<String, dynamic>))
          .toList();
    } on SocketException {
      throw const BreadcrumbRepositoryException(
        'No internet connection. Please try again.',
      );
    } on FunctionException catch (e) {
      throw BreadcrumbRepositoryException(
        e.reasonPhrase ?? 'Failed to load breadcrumbs.',
      );
    }
  }

  @override
  Future<void> uploadBreadcrumbs(List<Map<String, dynamic>> breadcrumbs) async {
    try {
      await _client.functions.invoke(
        'breadcrumbs',
        body: {'breadcrumbs': breadcrumbs},
      );
    } on SocketException {
      throw const BreadcrumbRepositoryException(
        'No internet connection. Breadcrumbs will be sent later.',
      );
    } on FunctionException catch (e) {
      throw BreadcrumbRepositoryException(
        e.reasonPhrase ?? 'Failed to upload breadcrumbs.',
      );
    }
  }
}
