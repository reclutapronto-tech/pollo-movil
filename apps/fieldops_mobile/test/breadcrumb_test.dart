import 'package:fieldops_mobile/features/breadcrumbs/domain/breadcrumb_repository.dart';
import 'package:fieldops_mobile/features/breadcrumbs/presentation/breadcrumb_playback_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ─── Breadcrumb.fromJson ────────────────────────────────────

  group('Breadcrumb.fromJson', () {
    test('parses a complete JSON map into a Breadcrumb', () {
      final json = <String, dynamic>{
        'id': 'bc-1',
        'user_id': 'user-42',
        'job_id': 'job-7',
        'latitude': 29.7604,
        'longitude': -95.3698,
        'accuracy_m': 8.5,
        'recorded_at': '2026-04-06T14:30:00.000Z',
        'shift_date': '2026-04-06',
      };

      final bc = Breadcrumb.fromJson(json);

      expect(bc.id, 'bc-1');
      expect(bc.userId, 'user-42');
      expect(bc.jobId, 'job-7');
      expect(bc.latitude, 29.7604);
      expect(bc.longitude, -95.3698);
      expect(bc.accuracyM, 8.5);
      expect(bc.recordedAt, DateTime.parse('2026-04-06T14:30:00.000Z'));
      expect(bc.shiftDate, '2026-04-06');
    });

    test('handles integer latitude/longitude values', () {
      final json = <String, dynamic>{
        'id': 'bc-2',
        'user_id': 'user-1',
        'job_id': 'job-1',
        'latitude': 30,
        'longitude': -95,
        'accuracy_m': null,
        'recorded_at': '2026-04-06T08:00:00.000Z',
        'shift_date': '2026-04-06',
      };

      final bc = Breadcrumb.fromJson(json);

      expect(bc.latitude, 30.0);
      expect(bc.longitude, -95.0);
      expect(bc.accuracyM, isNull);
    });

    test('handles null accuracy_m', () {
      final json = <String, dynamic>{
        'id': 'bc-3',
        'user_id': 'user-1',
        'job_id': 'job-1',
        'latitude': 29.0,
        'longitude': -95.0,
        'accuracy_m': null,
        'recorded_at': '2026-04-06T08:00:00.000Z',
        'shift_date': '2026-04-06',
      };

      final bc = Breadcrumb.fromJson(json);
      expect(bc.accuracyM, isNull);
    });

    test('throws when required fields are missing', () {
      final incomplete = <String, dynamic>{
        'id': 'bc-4',
        'user_id': 'user-1',
        // missing job_id, latitude, longitude, recorded_at, shift_date
      };

      expect(() => Breadcrumb.fromJson(incomplete), throwsA(isA<TypeError>()));
    });
  });

  // ─── BreadcrumbQuery equality ───────────────────────────────

  group('BreadcrumbQuery equality', () {
    test('equal queries with same shiftDate, userId, jobId', () {
      const a = BreadcrumbQuery(
        shiftDate: '2026-04-06',
        userId: 'user-1',
        jobId: 'job-1',
      );
      const b = BreadcrumbQuery(
        shiftDate: '2026-04-06',
        userId: 'user-1',
        jobId: 'job-1',
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different shiftDate yields inequality', () {
      const a = BreadcrumbQuery(shiftDate: '2026-04-06');
      const b = BreadcrumbQuery(shiftDate: '2026-04-07');

      expect(a, isNot(equals(b)));
    });

    test('null vs non-null userId yields inequality', () {
      const a = BreadcrumbQuery(shiftDate: '2026-04-06', userId: null);
      const b = BreadcrumbQuery(shiftDate: '2026-04-06', userId: 'user-1');

      expect(a, isNot(equals(b)));
    });

    test('null vs non-null jobId yields inequality', () {
      const a = BreadcrumbQuery(shiftDate: '2026-04-06', jobId: null);
      const b = BreadcrumbQuery(shiftDate: '2026-04-06', jobId: 'job-1');

      expect(a, isNot(equals(b)));
    });

    test('queries with all null optional fields are equal', () {
      const a = BreadcrumbQuery(shiftDate: '2026-04-06');
      const b = BreadcrumbQuery(shiftDate: '2026-04-06');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  // ─── BreadcrumbRepositoryException ──────────────────────────

  group('BreadcrumbRepositoryException', () {
    test('stores the message', () {
      const ex = BreadcrumbRepositoryException('Network error');
      expect(ex.message, 'Network error');
    });

    test('is an Exception', () {
      const ex = BreadcrumbRepositoryException('fail');
      expect(ex, isA<Exception>());
    });
  });
}
