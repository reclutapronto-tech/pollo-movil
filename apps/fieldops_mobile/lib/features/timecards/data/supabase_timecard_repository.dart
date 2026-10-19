import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fieldops_mobile/features/timecards/domain/timecard_repository.dart';
import 'package:fieldops_mobile/features/timecards/domain/timecard_signature.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class SupabaseTimecardRepository implements TimecardRepository {
  const SupabaseTimecardRepository(this._client, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  final SupabaseClient _client;
  final Uuid _uuid;

  @override
  Future<List<TimecardPeriod>> fetchMyTimecards() async {
    try {
      final response = await _client.functions.invoke(
        'timecards',
        headers: {'X-Client-Version': 'fieldops-mobile'},
        body: {'action': 'list'},
      );

      final payload = response.data;
      if (payload is! Map<String, dynamic>) {
        throw const TimecardRepositoryException(
          'Timecard response malformed.',
        );
      }

      final items = payload['timecards'] as List<dynamic>? ?? [];
      return items
          .cast<Map<String, dynamic>>()
          .map(_parsePeriod)
          .toList();
    } on SocketException {
      throw const TimecardRepositoryException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const TimecardRepositoryException('No connection available.');
      }
      throw TimecardRepositoryException(
        'Could not fetch timecards (${error.status}).',
      );
    }
  }

  @override
  Future<void> signTimecard(
    String timecardId, {
    Uint8List? signatureImage,
  }) async {
    try {
      await _client.functions.invoke(
        'timecards',
        headers: {
          'Idempotency-Key': _uuid.v4(),
          'X-Client-Version': 'fieldops-mobile',
        },
        body: {
          'action': 'sign',
          'timecard_id': timecardId,
          if (signatureImage != null)
            'signature': base64Encode(signatureImage),
        },
      );
    } on SocketException {
      throw const TimecardRepositoryException('No connection available.');
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw const TimecardRepositoryException('No connection available.');
      }
      throw TimecardRepositoryException(
        'Could not sign timecard (${error.status}).',
      );
    }
  }

  TimecardPeriod _parsePeriod(Map<String, dynamic> json) {
    return TimecardPeriod(
      id: json['id'] as String,
      workerId: json['worker_id'] as String? ?? '',
      workerName: json['worker_name'] as String? ?? '',
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      totalRegularHours: (json['regular_hours'] as num?)?.toDouble() ?? 0,
      totalOTHours: (json['ot_hours'] as num?)?.toDouble() ?? 0,
      totalDoubleTimeHours: (json['double_time_hours'] as num?)?.toDouble() ?? 0,
      workerSignature: json['worker_signature'] != null
          ? _parseSignature(json['worker_signature'] as Map<String, dynamic>)
          : null,
      supervisorSignature: json['supervisor_signature'] != null
          ? _parseSignature(json['supervisor_signature'] as Map<String, dynamic>)
          : null,
    );
  }

  TimecardSignature _parseSignature(Map<String, dynamic> json) {
    return TimecardSignature(
      id: json['id'] as String? ?? '',
      timecardId: json['timecard_id'] as String? ?? '',
      signerId: json['signer_id'] as String? ?? '',
      signerName: json['signer_name'] as String? ?? '',
      signerRole: json['signer_role'] as String? ?? '',
      signedAt: DateTime.parse(json['signed_at'] as String),
      signatureImagePath: json['signature_image_path'] as String?,
    );
  }
}
