import 'package:fieldops_mobile/features/clock/data/clock_repository_provider.dart';
import 'package:fieldops_mobile/features/clock/domain/clock_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final clockControllerProvider =
    NotifierProvider<ClockController, ClockState>(ClockController.new);

class ClockController extends Notifier<ClockState> {
  @override
  ClockState build() => const ClockState();

  Future<void> clockIn({
    required String jobId,
    required String jobName,
  }) async {
    state = state.copyWith(
      activeRequestJobId: jobId,
      clockError: null,
      offlineQueuedMessage: null,
    );
    await _handleClockAction(
      actionName: 'Clock in',
      action: () => ref.read(clockRepositoryProvider).clockIn(jobId: jobId),
      onSuccess: (result) => state = state.copyWith(
        activeRequestJobId: null,
        activeJobId: jobId,
        activeJobName: jobName,
        lastOccurredAt: result.occurredAt,
        clockedInAt: result.occurredAt,
        offlineQueuedMessage: _queuedMessage(result),
      ),
      onError: () => state = state.copyWith(activeRequestJobId: null),
    );
  }

  Future<void> clockOut() async {
    final jobId = state.activeJobId;
    final jobName = state.activeJobName;
    if (jobId == null) return;

    state = state.copyWith(
      activeRequestJobId: jobId,
      clockError: null,
      offlineQueuedMessage: null,
    );
    await _handleClockAction(
      actionName: 'Clock out',
      action: () => ref.read(clockRepositoryProvider).clockOut(jobId: jobId),
      onSuccess: (result) => state = state.copyWith(
        activeRequestJobId: null,
        activeJobId: null,
        activeJobName: null,
        lastOccurredAt: result.occurredAt,
        lastCompletedJobName: jobName,
        clockedInAt: null,
        offlineQueuedMessage: _queuedMessage(result),
      ),
      onError: () => state = state.copyWith(activeRequestJobId: null),
    );
  }

  Future<void> startBreak() async {
    final jobId = state.activeJobId;
    if (jobId == null) return;

    state = state.copyWith(
      clockError: null,
      isOnBreak: true,
      offlineQueuedMessage: null,
    );
    await _handleClockAction(
      actionName: 'Break',
      action: () => ref.read(clockRepositoryProvider).breakStart(jobId: jobId),
      onSuccess: (result) => state = state.copyWith(
        offlineQueuedMessage: _queuedMessage(result),
      ),
      onError: () => state = state.copyWith(isOnBreak: false),
    );
  }

  Future<void> endBreak() async {
    final jobId = state.activeJobId;
    if (jobId == null) return;

    state = state.copyWith(clockError: null, offlineQueuedMessage: null);
    await _handleClockAction(
      actionName: 'Break end',
      action: () => ref.read(clockRepositoryProvider).breakEnd(jobId: jobId),
      onSuccess: (result) => state = state.copyWith(
        isOnBreak: false,
        offlineQueuedMessage: _queuedMessage(result),
      ),
      onError: () {},
    );
  }

  /// Clears the one-shot offline-queued banner after UI has consumed it.
  void acknowledgeOfflineQueuedMessage() {
    if (state.offlineQueuedMessage == null) return;
    state = state.copyWith(offlineQueuedMessage: null);
  }

  static String? _queuedMessage(ClockActionResult result) =>
      result.queued ? 'Saved offline — will sync when connected.' : null;

  /// Centralised error handler for all clock actions.
  /// [onSuccess] is called with the result on success.
  /// [onError] runs first to revert optimistic state, then [clockError] is set.
  Future<void> _handleClockAction({
    required String actionName,
    required Future<ClockActionResult> Function() action,
    required void Function(ClockActionResult result) onSuccess,
    required void Function() onError,
  }) async {
    try {
      final result = await action();
      onSuccess(result);
    } on ClockRepositoryException catch (error) {
      onError();
      state = state.copyWith(
        clockError: (title: '$actionName failed', message: error.message),
      );
    } on Exception catch (_) {
      onError();
      state = state.copyWith(
        clockError: (
          title: '$actionName failed',
          message: '$actionName could not be completed right now.',
        ),
      );
    }
  }
}

// Kept as alias so existing imports referencing ClockInState still compile.
typedef ClockInState = ClockState;

class ClockState {
  const ClockState({
    this.activeRequestJobId,
    this.activeJobId,
    this.activeJobName,
    this.lastOccurredAt,
    this.lastCompletedJobName,
    this.isOnBreak = false,
    this.clockError,
    this.clockedInAt,
    this.offlineQueuedMessage,
  });

  final String? activeRequestJobId;
  final String? activeJobId;
  final String? activeJobName;
  final DateTime? lastOccurredAt;
  final String? lastCompletedJobName;
  final bool isOnBreak;
  final ({String title, String message})? clockError;
  /// When the current shift started. Used for shift wrap-up summary.
  final DateTime? clockedInAt;

  /// Transient one-shot message set when a clock action was persisted to the
  /// local outbox because the device was offline. The UI listener should
  /// show a SnackBar and then call
  /// [ClockController.acknowledgeOfflineQueuedMessage] to clear it.
  final String? offlineQueuedMessage;

  // Legacy accessors for widgets that read errorTitle/errorMessage
  String? get errorTitle => clockError?.title;
  String? get errorMessage => clockError?.message;

  bool get isClockedIn => activeJobId != null;
  bool isSubmitting(String jobId) => activeRequestJobId == jobId;
  bool isClockedInFor(String jobId) => activeJobId == jobId;
  bool get hasError => clockError != null;

  ClockState copyWith({
    Object? activeRequestJobId = _sentinel,
    Object? activeJobId = _sentinel,
    Object? activeJobName = _sentinel,
    Object? lastOccurredAt = _sentinel,
    Object? lastCompletedJobName = _sentinel,
    Object? isOnBreak = _sentinel,
    Object? clockError = _sentinel,
    Object? clockedInAt = _sentinel,
    Object? offlineQueuedMessage = _sentinel,
  }) {
    return ClockState(
      activeRequestJobId: activeRequestJobId == _sentinel
          ? this.activeRequestJobId
          : activeRequestJobId as String?,
      activeJobId:
          activeJobId == _sentinel ? this.activeJobId : activeJobId as String?,
      activeJobName: activeJobName == _sentinel
          ? this.activeJobName
          : activeJobName as String?,
      lastOccurredAt: lastOccurredAt == _sentinel
          ? this.lastOccurredAt
          : lastOccurredAt as DateTime?,
      lastCompletedJobName: lastCompletedJobName == _sentinel
          ? this.lastCompletedJobName
          : lastCompletedJobName as String?,
      isOnBreak:
          isOnBreak == _sentinel ? this.isOnBreak : isOnBreak as bool,
      clockError: clockError == _sentinel
          ? this.clockError
          : clockError as ({String title, String message})?,
      clockedInAt: clockedInAt == _sentinel
          ? this.clockedInAt
          : clockedInAt as DateTime?,
      offlineQueuedMessage: offlineQueuedMessage == _sentinel
          ? this.offlineQueuedMessage
          : offlineQueuedMessage as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClockState &&
          activeRequestJobId == other.activeRequestJobId &&
          activeJobId == other.activeJobId &&
          activeJobName == other.activeJobName &&
          lastOccurredAt == other.lastOccurredAt &&
          lastCompletedJobName == other.lastCompletedJobName &&
          isOnBreak == other.isOnBreak &&
          clockError == other.clockError &&
          clockedInAt == other.clockedInAt &&
          offlineQueuedMessage == other.offlineQueuedMessage;

  @override
  int get hashCode => Object.hash(
        activeRequestJobId,
        activeJobId,
        activeJobName,
        lastOccurredAt,
        lastCompletedJobName,
        isOnBreak,
        clockError,
        clockedInAt,
        offlineQueuedMessage,
      );
}

const _sentinel = Object();
