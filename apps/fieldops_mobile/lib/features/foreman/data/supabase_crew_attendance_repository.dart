import 'dart:io';

import 'package:fieldops_mobile/features/foreman/domain/crew_attendance_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseCrewAttendanceRepository implements CrewAttendanceRepository {
  const SupabaseCrewAttendanceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<CrewMemberStatus>> fetchCrewAttendance() async {
    try {
      final response = await _client.functions.invoke(
        'crew',
        headers: {'X-Client-Version': 'fieldops-mobile'},
        body: {'action': 'attendance'},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const CrewAttendanceException('Crew attendance response malformed.');
      }

      final items = payload['crew'] as List<dynamic>? ?? [];
      return items
          .cast<Map<String, dynamic>>()
          .map(CrewMemberStatus.fromJson)
          .toList();
    } on SocketException {
      throw const CrewAttendanceException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const CrewAttendanceException('No connection available.');
      }
      throw CrewAttendanceException(
        'Could not fetch crew attendance (${error.status}).',
      );
    }
  }
}
