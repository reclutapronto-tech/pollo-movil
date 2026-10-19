import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/features/safety/data/safety_repository_provider.dart';
import 'package:fieldops_mobile/features/safety/domain/safety_checklist.dart';
import 'package:fieldops_mobile/features/safety/domain/safety_repository.dart';
import 'package:fieldops_mobile/features/safety/presentation/safety_checklist_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';

void main() {
  void usePhoneViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget buildTestWidget({required SafetyRepository repository}) {
    return ProviderScope(
      overrides: [
        safetyRepositoryProvider.overrideWithValue(repository),
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
        home: const SafetyChecklistScreen(
          jobId: 'job-1',
          jobName: 'Grid Restoration',
        ),
      ),
    );
  }

  /// Scrolls the question into view and taps the given semantics label.
  Future<void> scrollAndTap(
    WidgetTester tester,
    String semanticsLabel,
  ) async {
    var finder = find.bySemanticsLabel(semanticsLabel);

    // Scroll until the button is rendered
    for (var attempt = 0; attempt < 5 && finder.evaluate().isEmpty; attempt++) {
      await tester.drag(
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      finder = find.bySemanticsLabel(semanticsLabel);
    }

    // Use ensureVisible to make sure it's not behind the bottom bar
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Answers all safety questions Yes by using their Semantics labels.
  Future<void> answerAllYes(WidgetTester tester) async {
    for (final q in defaultSafetyQuestions) {
      await scrollAndTap(tester, 'Yes, confirm: ${q.question}');
    }
  }

  /// Answer first question No, rest Yes.
  Future<void> answerFirstNoRestYes(WidgetTester tester) async {
    for (var i = 0; i < defaultSafetyQuestions.length; i++) {
      final q = defaultSafetyQuestions[i];
      if (i == 0) {
        await scrollAndTap(tester, 'No, flag concern: ${q.question}');
      } else {
        await scrollAndTap(tester, 'Yes, confirm: ${q.question}');
      }
    }
  }

  testWidgets('shows safety checklist header and first question cards', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(buildTestWidget(
      repository: FakeSafetyRepository(),
    ));
    await tester.pumpAndSettle();

    // Header
    expect(find.text('Safety Checklist'), findsOneWidget);
    expect(find.text('Grid Restoration'), findsOneWidget);

    // First question visible
    expect(
      find.textContaining('Are you wearing all required PPE'),
      findsOneWidget,
    );
    // Second question visible
    expect(
      find.textContaining('Have you identified any new hazards'),
      findsOneWidget,
    );
  });

  testWidgets('scrolling reveals remaining question cards', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(buildTestWidget(
      repository: FakeSafetyRepository(),
    ));
    await tester.pumpAndSettle();

    // Scroll down to reveal later questions
    await tester.drag(
      find.byType(ListView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Do you know the emergency plan'),
      findsOneWidget,
    );
  });

  testWidgets('shows Yes and No/Flag buttons for visible questions', (
    tester,
  ) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(buildTestWidget(
      repository: FakeSafetyRepository(),
    ));
    await tester.pumpAndSettle();

    // At least some Yes/No buttons should be visible
    expect(find.text('Yes'), findsWidgets);
    expect(find.text('No / Flag'), findsWidgets);
  });

  testWidgets('submit button is disabled until all questions are answered', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final repository = FakeSafetyRepository();
    await tester.pumpWidget(buildTestWidget(repository: repository));
    await tester.pumpAndSettle();

    // The submit text should be visible at the bottom
    expect(find.text('Confirm & Start Shift'), findsOneWidget);

    // The Semantics label wrapping the button indicates its purpose
    expect(
      find.bySemanticsLabel('Submit safety checklist'),
      findsOneWidget,
    );

    // Tapping submit before answering should not trigger submission
    await tester.tap(find.text('Confirm & Start Shift'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(repository.lastJobId, isNull);
  });

  testWidgets('can toggle Yes/No answers on questions', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(buildTestWidget(
      repository: FakeSafetyRepository(),
    ));
    await tester.pumpAndSettle();

    // Tap the first Yes button using semantics
    final yesLabel =
        'Yes, confirm: ${defaultSafetyQuestions.first.question}';
    await tester.tap(find.bySemanticsLabel(yesLabel));
    await tester.pumpAndSettle();

    // Toggle to No / Flag
    final noLabel =
        'No, flag concern: ${defaultSafetyQuestions.first.question}';
    await tester.tap(find.bySemanticsLabel(noLabel));
    await tester.pumpAndSettle();

    // Should still show buttons (no crash)
    expect(find.text('Yes'), findsWidgets);
  });

  testWidgets('submit button enables after all questions answered', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final repository = FakeSafetyRepository();
    await tester.pumpWidget(buildTestWidget(repository: repository));
    await tester.pumpAndSettle();

    // Answer all 5 questions
    await answerAllYes(tester);

    // Tapping submit should now work (button is enabled)
    await tester.tap(find.text('Confirm & Start Shift'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Repository was called -- button was enabled
    expect(repository.lastJobId, 'job-1');
  });

  testWidgets('submitting the checklist calls the repository', (
    tester,
  ) async {
    usePhoneViewport(tester);
    final repository = FakeSafetyRepository();
    await tester.pumpWidget(buildTestWidget(repository: repository));
    await tester.pumpAndSettle();

    // Answer all questions
    await answerAllYes(tester);

    // Tap submit
    await tester.tap(find.text('Confirm & Start Shift'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // The fake repository should have received the submission
    expect(repository.lastJobId, 'job-1');
    expect(repository.lastResponses, hasLength(defaultSafetyQuestions.length));
  });

  testWidgets('flagged answers show warning banner', (tester) async {
    usePhoneViewport(tester);
    await tester.pumpWidget(buildTestWidget(
      repository: FakeSafetyRepository(),
    ));
    await tester.pumpAndSettle();

    // Answer first as No/Flag, rest as Yes
    await answerFirstNoRestYes(tester);

    // Flagged warning should appear in the bottom bar
    expect(
      find.textContaining('You flagged safety concerns'),
      findsOneWidget,
    );
  });
}

// ─── Fake Repository ──────────────────────────────────────────

class FakeSafetyRepository implements SafetyRepository {
  FakeSafetyRepository({this.shouldFail = false});

  final bool shouldFail;
  String? lastJobId;
  List<SafetyChecklistResponse>? lastResponses;

  @override
  Future<String> submitChecklist({
    required String jobId,
    required List<SafetyChecklistResponse> responses,
  }) async {
    if (shouldFail) {
      throw const SafetyRepositoryException('Network error');
    }
    lastJobId = jobId;
    lastResponses = responses;
    return 'checklist-1';
  }

  @override
  Future<bool> hasCompletedToday(String jobId) async => false;
}
