import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:fieldops_mobile/features/permits/data/permits_repository_provider.dart';
import 'package:fieldops_mobile/features/permits/domain/permits_repository.dart';
import 'package:fieldops_mobile/features/safety/data/safety_repository_provider.dart';
import 'package:fieldops_mobile/features/safety/domain/safety_repository.dart';
import 'package:fieldops_mobile/features/safety/presentation/safety_checklist_controller.dart';
import 'package:fieldops_mobile/features/safety/presentation/safety_checklist_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Worker-facing clock-in helper that gates the action behind two server
/// checks, in order:
///
///   1. **Permit gate** — `permits.check_active`. If the job requires a
///      permit and none is active, block clock-in entirely with an
///      explanatory dialog. Network failure here degrades gracefully (the
///      server will re-enforce on the actual clock event).
///   2. **Safety gate** — `safety.check`. If today's checklist is missing,
///      push [SafetyChecklistScreen]; only proceed on successful submit.
///      Network failure here also degrades gracefully (existing behaviour).
///   3. **Clock-in** via [ClockController.clockIn].
///
/// Foreman crew clock-in / clock-out / break-end paths are intentionally
/// untouched — both gates apply only to the worker self-clock flow.
Future<void> guardedClockIn(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
  required String jobName,
}) async {
  // Gate 1: permit check.
  final permitOk = await _checkPermit(context, ref, jobId: jobId);
  if (!permitOk) return;
  if (!context.mounted) return;

  // Gate 2: safety check + checklist.
  await _runSafetyGateAndClockIn(
    context,
    ref,
    jobId: jobId,
    jobName: jobName,
  );
}

/// Returns `true` if the caller may proceed past the permit gate.
///
/// Behaviour:
/// - Required + no active permit → blocking dialog, return false.
/// - Required + active permit, OR not required → return true.
/// - Offline → non-blocking SnackBar warning, return true (graceful
///   fallback; server re-enforces on the clock event).
/// - Hard server error → blocking dialog, return false.
Future<bool> _checkPermit(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
}) async {
  final repo = ref.read(permitsRepositoryProvider);

  PermitCheckResult result;
  try {
    result = await repo.checkActive(jobId: jobId);
  } on PermitsRepositoryException catch (error) {
    if (!context.mounted) return false;
    if (error.isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't verify permit status — continuing."),
        ),
      );
      return true;
    }
    await _showBlockingDialog(
      context,
      title: 'Permit check failed',
      body: "Couldn't verify permit — please try again.",
    );
    return false;
  } on Exception {
    if (!context.mounted) return false;
    await _showBlockingDialog(
      context,
      title: 'Permit check failed',
      body: "Couldn't verify permit — please try again.",
    );
    return false;
  }

  if (!context.mounted) return false;

  if (result.required && result.activePermit == null) {
    await _showPermitRequiredDialog(context, requiredType: result.requiredType);
    return false;
  }

  return true;
}

Future<void> _showPermitRequiredDialog(
  BuildContext context, {
  required String? requiredType,
}) {
  final friendly = _formatPermitType(requiredType);
  return _showBlockingDialog(
    context,
    title: 'Permit required',
    body: 'This job requires an active work permit before you can clock in. '
        'Ask your supervisor to issue a permit. (Type: $friendly)',
  );
}

Future<void> _showBlockingDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

String _formatPermitType(String? requiredType) {
  if (requiredType == null || requiredType.isEmpty) {
    return 'a work permit';
  }
  switch (requiredType) {
    case 'hv_electrical':
      return 'HV Electrical';
  }
  // Fallback: snake_case → Title Case.
  return requiredType
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}

/// Runs the existing safety gate and final clock-in. Extracted to keep
/// [guardedClockIn] readable now that the permit gate sits above it.
Future<void> _runSafetyGateAndClockIn(
  BuildContext context,
  WidgetRef ref, {
  required String jobId,
  required String jobName,
}) async {
  final safetyRepo = ref.read(safetyRepositoryProvider);

  bool alreadyCompleted = false;
  bool checkFailed = false;
  try {
    alreadyCompleted = await safetyRepo.hasCompletedToday(jobId);
  } on SafetyRepositoryException {
    checkFailed = true;
  } on Exception {
    checkFailed = true;
  }

  if (!context.mounted) return;

  if (alreadyCompleted) {
    await ref.read(clockControllerProvider.notifier).clockIn(
          jobId: jobId,
          jobName: jobName,
        );
    return;
  }

  if (checkFailed) {
    // Non-blocking warning — let the worker proceed.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't verify safety status — please complete the checklist "
          "if you haven't today.",
        ),
      ),
    );
    await ref.read(clockControllerProvider.notifier).clockIn(
          jobId: jobId,
          jobName: jobName,
        );
    return;
  }

  // Clear any stale answers from a previously cancelled attempt so the
  // worker starts with a fresh checklist.
  ref.read(safetyChecklistControllerProvider.notifier).reset();

  final submitted = await Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => SafetyChecklistScreen(
        jobId: jobId,
        jobName: jobName,
      ),
    ),
  );

  if (submitted != true) return; // Cancelled — abort silently.
  if (!context.mounted) return;

  await ref.read(clockControllerProvider.notifier).clockIn(
        jobId: jobId,
        jobName: jobName,
      );
}
