import 'dart:typed_data';

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/timecards/data/timecard_repository_provider.dart';
import 'package:fieldops_mobile/features/timecards/domain/timecard_repository.dart';
import 'package:fieldops_mobile/features/timecards/domain/timecard_signature.dart';
import 'package:fieldops_mobile/features/timecards/presentation/timecards_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget({required TimecardRepository repository}) {
    return ProviderScope(
      overrides: [
        timecardRepositoryProvider.overrideWithValue(repository),
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
        home: const TimecardsScreen(),
      ),
    );
  }

  testWidgets('shows timecard period cards with hours', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeTimecardRepository(
        timecards: [
          TimecardPeriod(
            id: 'tc-1',
            workerId: 'w-1',
            workerName: 'John Smith',
            periodStart: DateTime.utc(2026, 3, 23),
            periodEnd: DateTime.utc(2026, 4, 5),
            totalRegularHours: 72.0,
            totalOTHours: 8.5,
            totalDoubleTimeHours: 0.0,
          ),
          TimecardPeriod(
            id: 'tc-2',
            workerId: 'w-1',
            workerName: 'John Smith',
            periodStart: DateTime.utc(2026, 3, 9),
            periodEnd: DateTime.utc(2026, 3, 22),
            totalRegularHours: 80.0,
            totalOTHours: 4.0,
            totalDoubleTimeHours: 2.0,
            workerSignature: TimecardSignature(
              id: 'sig-1',
              timecardId: 'tc-2',
              signerId: 'w-1',
              signerName: 'John Smith',
              signerRole: 'worker',
              signedAt: DateTime.utc(2026, 3, 22, 17, 0),
            ),
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('My Timecards'), findsOneWidget);

    // First card — period dates (month/day format)
    expect(find.textContaining('3/23'), findsOneWidget);
    expect(find.textContaining('4/5'), findsOneWidget);

    // Hours for first card — total = 72.0 + 8.5 + 0.0 = 80.5h
    expect(find.text('80.5h'), findsOneWidget);
    expect(find.text('72.0h'), findsOneWidget);
    expect(find.text('8.5h'), findsOneWidget);

    // Second card — total = 80.0 + 4.0 + 2.0 = 86.0h
    expect(find.text('86.0h'), findsOneWidget);

    // Column labels
    expect(find.text('Regular'), findsNWidgets(2));
    expect(find.text('OT'), findsNWidgets(2));
    expect(find.text('2x'), findsNWidgets(2));
    expect(find.text('Total'), findsNWidgets(2));
  });

  testWidgets('shows unsigned status for cards without worker signature', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeTimecardRepository(
        timecards: [
          TimecardPeriod(
            id: 'tc-1',
            workerId: 'w-1',
            workerName: 'John Smith',
            periodStart: DateTime.utc(2026, 3, 23),
            periodEnd: DateTime.utc(2026, 4, 5),
            totalRegularHours: 40.0,
            totalOTHours: 0.0,
            totalDoubleTimeHours: 0.0,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Unsigned'), findsOneWidget);
    expect(find.text('Sign Timecard'), findsOneWidget);
  });

  testWidgets('shows awaiting supervisor for worker-signed cards', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeTimecardRepository(
        timecards: [
          TimecardPeriod(
            id: 'tc-1',
            workerId: 'w-1',
            workerName: 'John Smith',
            periodStart: DateTime.utc(2026, 3, 23),
            periodEnd: DateTime.utc(2026, 4, 5),
            totalRegularHours: 40.0,
            totalOTHours: 0.0,
            totalDoubleTimeHours: 0.0,
            workerSignature: TimecardSignature(
              id: 'sig-1',
              timecardId: 'tc-1',
              signerId: 'w-1',
              signerName: 'John Smith',
              signerRole: 'worker',
              signedAt: DateTime.utc(2026, 4, 5, 17, 0),
            ),
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Awaiting Supervisor'), findsOneWidget);
    // Sign button should not be shown for already-signed cards
    expect(find.text('Sign Timecard'), findsNothing);
  });

  testWidgets('shows fully signed status when both signatures present', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeTimecardRepository(
        timecards: [
          TimecardPeriod(
            id: 'tc-1',
            workerId: 'w-1',
            workerName: 'John Smith',
            periodStart: DateTime.utc(2026, 3, 23),
            periodEnd: DateTime.utc(2026, 4, 5),
            totalRegularHours: 40.0,
            totalOTHours: 0.0,
            totalDoubleTimeHours: 0.0,
            workerSignature: TimecardSignature(
              id: 'sig-1',
              timecardId: 'tc-1',
              signerId: 'w-1',
              signerName: 'John Smith',
              signerRole: 'worker',
              signedAt: DateTime.utc(2026, 4, 5, 17, 0),
            ),
            supervisorSignature: TimecardSignature(
              id: 'sig-2',
              timecardId: 'tc-1',
              signerId: 's-1',
              signerName: 'Manager Jones',
              signerRole: 'supervisor',
              signedAt: DateTime.utc(2026, 4, 6, 9, 0),
            ),
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Fully Signed'), findsOneWidget);
  });

  testWidgets('shows empty state when no timecards', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeTimecardRepository(timecards: []),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No timecards yet'), findsOneWidget);
    expect(
      find.text('Timecards will appear here at the end of each pay period.'),
      findsOneWidget,
    );
  });

  testWidgets('shows pay period label on each card', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeTimecardRepository(
        timecards: [
          TimecardPeriod(
            id: 'tc-1',
            workerId: 'w-1',
            workerName: 'John Smith',
            periodStart: DateTime.utc(2026, 3, 23),
            periodEnd: DateTime.utc(2026, 4, 5),
            totalRegularHours: 40.0,
            totalOTHours: 0.0,
            totalDoubleTimeHours: 0.0,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pay period'), findsOneWidget);
  });
}

// ─── Fake Repository ──────────────────────────────────────────

class FakeTimecardRepository implements TimecardRepository {
  FakeTimecardRepository({this.timecards = const []});

  final List<TimecardPeriod> timecards;
  String? lastSignedTimecardId;

  @override
  Future<List<TimecardPeriod>> fetchMyTimecards() async {
    return List.of(timecards);
  }

  @override
  Future<void> signTimecard(String timecardId, {Uint8List? signatureImage}) async {
    lastSignedTimecardId = timecardId;
  }
}
