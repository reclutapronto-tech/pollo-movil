import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:fieldops_mobile/features/schedule/domain/crew_schedule_shift.dart';
import 'package:fieldops_mobile/features/schedule/domain/schedule_repository.dart';
import 'package:fieldops_mobile/features/schedule/domain/worker_schedule_shift.dart';
import 'package:fieldops_mobile/features/schedule/presentation/worker_schedule_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';

void main() {
  testWidgets('worker schedule screen shows published shifts and update badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleRepositoryProvider.overrideWithValue(
            FakeScheduleRepository(
              shifts: [
                WorkerScheduleShift(
                  id: 'shift-1',
                  jobId: 'job-1',
                  jobName: 'Grid Restoration',
                  shiftDate: DateTime.utc(2026, 4, 6),
                  startTime: '07:00',
                  endTime: '15:30',
                  status: WorkerScheduleStatus.published,
                  publishedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
                  notes: 'Crew briefing at 6:45.',
                ),
              ],
            ),
          ),
        ],
        child: MaterialApp(
          theme: buildFieldOpsTheme(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WorkerScheduleScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('My schedule'), findsOneWidget);
    expect(find.text('Grid Restoration'), findsOneWidget);
    expect(find.text('07:00 - 15:30'), findsOneWidget);
    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('Crew briefing at 6:45.'), findsOneWidget);
  });
}

class FakeScheduleRepository implements ScheduleRepository {
  FakeScheduleRepository({required this.shifts});

  final List<WorkerScheduleShift> shifts;

  @override
  Future<List<WorkerScheduleShift>> fetchMySchedule({
    DateTime? from,
    DateTime? to,
  }) async {
    return shifts;
  }

  @override
  Future<String> requestShiftSwap({
    required String shiftId,
    String? notes,
  }) async {
    return 'swap-1';
  }

  @override
  Future<List<CrewScheduleShift>> fetchCrewSchedule({
    DateTime? from,
    DateTime? to,
  }) async {
    return [];
  }

  @override
  Future<bool> saveCrewReorder(List<CrewScheduleShift> shifts) async {
    return true;
  }

  @override
  Future<List<SwapRequest>> fetchSwapRequests({String status = 'pending'}) async {
    return const [];
  }

  @override
  Future<void> approveSwap(String swapRequestId, {String? reason}) async {}

  @override
  Future<void> denySwap(String swapRequestId, {required String reason}) async {}

  @override
  Future<void> cancelSwap(String swapRequestId) async {}

  @override
  Future<int> copyWeek({
    required DateTime sourceStart,
    required DateTime sourceEnd,
    required DateTime targetStart,
  }) async {
    return 0;
  }
}
