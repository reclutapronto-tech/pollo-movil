import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/foreman/data/crew_attendance_provider.dart';
import 'package:fieldops_mobile/features/foreman/domain/crew_attendance_repository.dart';
import 'package:fieldops_mobile/features/foreman/presentation/crew_attendance_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget({required CrewAttendanceRepository repository}) {
    return ProviderScope(
      overrides: [
        crewAttendanceRepositoryProvider.overrideWithValue(repository),
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
        home: const CrewAttendanceScreen(),
      ),
    );
  }

  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('shows worker status grouped by status categories', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(buildTestWidget(
      repository: FakeCrewAttendanceRepository(
        crew: [
          const CrewMemberStatus(
            workerId: 'w-1',
            workerName: 'Alice Johnson',
            status: CrewClockStatus.late_,
            jobName: 'Grid Restoration',
          ),
          CrewMemberStatus(
            workerId: 'w-2',
            workerName: 'Bob Martinez',
            status: CrewClockStatus.clockedIn,
            jobName: 'Grid Restoration',
            clockedInAt: DateTime.now().subtract(const Duration(hours: 3)),
          ),
          CrewMemberStatus(
            workerId: 'w-3',
            workerName: 'Carol White',
            status: CrewClockStatus.onBreak,
            jobName: 'Substation Audit',
            clockedInAt: DateTime.now().subtract(const Duration(hours: 2)),
          ),
          const CrewMemberStatus(
            workerId: 'w-4',
            workerName: 'Dave Brown',
            status: CrewClockStatus.absent,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    // Screen title
    expect(find.text('Crew Attendance'), findsOneWidget);

    // First visible section headers and workers
    expect(find.text('Late'), findsAtLeastNWidgets(1));
    expect(find.text('Alice Johnson'), findsOneWidget);
    expect(find.text('Bob Martinez'), findsOneWidget);

    // Scroll down to reveal absent section
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(find.text('Absent'), findsAtLeastNWidgets(1));
    expect(find.text('Dave Brown'), findsOneWidget);
  });

  testWidgets('shows summary row with counts', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeCrewAttendanceRepository(
        crew: [
          const CrewMemberStatus(
            workerId: 'w-1',
            workerName: 'Alice Johnson',
            status: CrewClockStatus.clockedIn,
            jobName: 'Grid Restoration',
          ),
          const CrewMemberStatus(
            workerId: 'w-2',
            workerName: 'Bob Martinez',
            status: CrewClockStatus.clockedIn,
            jobName: 'Grid Restoration',
          ),
          const CrewMemberStatus(
            workerId: 'w-3',
            workerName: 'Carol White',
            status: CrewClockStatus.absent,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    // Summary row
    expect(find.text("Today's Crew"), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Break'), findsOneWidget);
  });

  testWidgets('shows empty state when no crew members', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeCrewAttendanceRepository(crew: []),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No crew members'), findsOneWidget);
    expect(
      find.text('No crew members are assigned to you today.'),
      findsOneWidget,
    );
  });

  testWidgets('shows status badges on each member tile', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeCrewAttendanceRepository(
        crew: [
          const CrewMemberStatus(
            workerId: 'w-1',
            workerName: 'Alice Johnson',
            status: CrewClockStatus.clockedIn,
            jobName: 'Grid Restoration',
          ),
          const CrewMemberStatus(
            workerId: 'w-2',
            workerName: 'Bob Martinez',
            status: CrewClockStatus.absent,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    // Status badge labels from CrewClockStatus.label
    expect(find.text('Clocked In'), findsAtLeastNWidgets(1));
    expect(find.text('Absent'), findsAtLeastNWidgets(1));
  });

  testWidgets('shows job name in member tile subtitle', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeCrewAttendanceRepository(
        crew: [
          CrewMemberStatus(
            workerId: 'w-1',
            workerName: 'Alice Johnson',
            status: CrewClockStatus.clockedIn,
            jobName: 'Grid Restoration',
            clockedInAt: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Grid Restoration'), findsOneWidget);
  });
}

// ─── Fake Repository ──────────────────────────────────────────

class FakeCrewAttendanceRepository implements CrewAttendanceRepository {
  FakeCrewAttendanceRepository({this.crew = const []});

  final List<CrewMemberStatus> crew;

  @override
  Future<List<CrewMemberStatus>> fetchCrewAttendance() async {
    return List.of(crew);
  }
}
