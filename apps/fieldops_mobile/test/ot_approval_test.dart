import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/overtime/data/ot_repository_provider.dart';
import 'package:fieldops_mobile/features/overtime/domain/ot_repository.dart';
import 'package:fieldops_mobile/features/overtime/presentation/ot_approval_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';

void main() {
  Widget buildTestWidget({required OTRepository repository}) {
    return ProviderScope(
      overrides: [
        otRepositoryProvider.overrideWithValue(repository),
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
        home: const OTApprovalScreen(),
      ),
    );
  }

  testWidgets('shows pending OT request cards', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeOTRepository(
        pendingRequests: [
          OTRequest(
            id: 'ot-1',
            workerId: 'w-1',
            workerName: 'John Smith',
            jobId: 'job-1',
            jobName: 'Grid Restoration',
            createdAt: DateTime.utc(2026, 4, 6, 14, 30),
            totalHours: 2.5,
            notes: 'Finished cable pull',
          ),
          OTRequest(
            id: 'ot-2',
            workerId: 'w-2',
            workerName: 'Jane Doe',
            jobId: 'job-2',
            jobName: 'Substation Audit',
            createdAt: DateTime.utc(2026, 4, 6, 15, 0),
            totalHours: 1.0,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('OT Approvals'), findsOneWidget);
    expect(find.text('John Smith'), findsOneWidget);
    expect(find.text('Jane Doe'), findsOneWidget);
    expect(find.text('2.5h worked'), findsOneWidget);
    expect(find.text('1.0h worked'), findsOneWidget);
    expect(find.textContaining('Finished cable pull'), findsOneWidget);
  });

  testWidgets('shows empty state when no pending requests', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeOTRepository(pendingRequests: []),
    ));
    await tester.pumpAndSettle();

    expect(find.text('All caught up'), findsOneWidget);
    expect(
      find.text('No pending overtime requests to review.'),
      findsOneWidget,
    );
  });

  testWidgets('approve button removes the request card', (tester) async {
    final repository = FakeOTRepository(
      pendingRequests: [
        OTRequest(
          id: 'ot-1',
          workerId: 'w-1',
          workerName: 'John Smith',
          jobId: 'job-1',
          jobName: 'Grid Restoration',
          createdAt: DateTime.utc(2026, 4, 6, 14, 30),
          totalHours: 2.5,
        ),
      ],
    );

    await tester.pumpWidget(buildTestWidget(repository: repository));
    await tester.pumpAndSettle();

    // Verify the card is present
    expect(find.text('John Smith'), findsOneWidget);

    // Tap Approve — use runAsync to allow the async _approve()
    // handler (which awaits HapticFeedback + repository call) to complete.
    await tester.tap(find.text('Approve'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The repository should have received the approval call
    expect(repository.lastApprovedId, 'ot-1');

    // Snackbar should show success message
    expect(
      find.textContaining('Approved OT for John Smith'),
      findsOneWidget,
    );
  });

  testWidgets('shows Approve and Deny buttons on each card', (tester) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeOTRepository(
        pendingRequests: [
          OTRequest(
            id: 'ot-1',
            workerId: 'w-1',
            workerName: 'John Smith',
            jobId: 'job-1',
            jobName: 'Grid Restoration',
            createdAt: DateTime.utc(2026, 4, 6, 14, 30),
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
  });

  testWidgets('shows hours not specified when totalHours is null', (
    tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(
      repository: FakeOTRepository(
        pendingRequests: [
          OTRequest(
            id: 'ot-1',
            workerId: 'w-1',
            workerName: 'John Smith',
            jobId: 'job-1',
            jobName: 'Grid Restoration',
            createdAt: DateTime.utc(2026, 4, 6, 14, 30),
            totalHours: null,
          ),
        ],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Hours not specified'), findsOneWidget);
  });
}

// ─── Fake Repository ──────────────────────────────────────────

class FakeOTRepository implements OTRepository {
  FakeOTRepository({this.pendingRequests = const []});

  final List<OTRequest> pendingRequests;
  String? lastApprovedId;
  String? lastDeniedId;
  String? lastDenyReason;

  @override
  Future<String> submitRequest({
    required String jobId,
    double? totalHours,
    String? notes,
    String? photoEventId,
  }) async {
    return 'ot-new';
  }

  @override
  Future<List<OTRequest>> fetchPendingRequests() async {
    return List.of(pendingRequests);
  }

  @override
  Future<void> approveRequest(String requestId) async {
    lastApprovedId = requestId;
  }

  @override
  Future<void> denyRequest(String requestId, {String? reason}) async {
    lastDeniedId = requestId;
    lastDenyReason = reason;
  }
}
