import 'dart:async';

import 'package:fieldops_mobile/features/clock/presentation/clock_in_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configurable OT threshold in hours (default 8).
const double otThresholdHours = 8.0;

/// Tracks cumulative shift time and fires when OT threshold is hit.
final otAutoDetectorProvider =
    NotifierProvider<OTAutoDetector, OTDetectionState>(OTAutoDetector.new);

class OTAutoDetector extends Notifier<OTDetectionState> {
  Timer? _timer;

  @override
  OTDetectionState build() {
    ref.onDispose(() => _timer?.cancel());

    final clockState = ref.watch(clockControllerProvider);

    if (!clockState.isClockedIn || clockState.clockedInAt == null) {
      _timer?.cancel();
      return const OTDetectionState();
    }

    // Start tracking from clock-in time
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
    _check(); // Check immediately

    return OTDetectionState(
      clockInTime: clockState.clockedInAt,
      thresholdHours: otThresholdHours,
    );
  }

  void _check() {
    final clockState = ref.read(clockControllerProvider);
    if (!clockState.isClockedIn || clockState.clockedInAt == null) return;

    final elapsed = DateTime.now().difference(clockState.clockedInAt!);
    final elapsedHours = elapsed.inMinutes / 60.0;

    state = state.copyWith(
      currentHours: elapsedHours,
      isOverThreshold: elapsedHours >= otThresholdHours,
    );
  }

  void dismissPrompt() {
    state = state.copyWith(promptDismissed: true);
  }
}

class OTDetectionState {
  const OTDetectionState({
    this.clockInTime,
    this.thresholdHours = otThresholdHours,
    this.currentHours = 0,
    this.isOverThreshold = false,
    this.promptDismissed = false,
  });

  final DateTime? clockInTime;
  final double thresholdHours;
  final double currentHours;
  final bool isOverThreshold;
  final bool promptDismissed;

  bool get shouldShowPrompt => isOverThreshold && !promptDismissed;

  OTDetectionState copyWith({
    DateTime? clockInTime,
    double? thresholdHours,
    double? currentHours,
    bool? isOverThreshold,
    bool? promptDismissed,
  }) {
    return OTDetectionState(
      clockInTime: clockInTime ?? this.clockInTime,
      thresholdHours: thresholdHours ?? this.thresholdHours,
      currentHours: currentHours ?? this.currentHours,
      isOverThreshold: isOverThreshold ?? this.isOverThreshold,
      promptDismissed: promptDismissed ?? this.promptDismissed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OTDetectionState &&
          currentHours == other.currentHours &&
          isOverThreshold == other.isOverThreshold &&
          promptDismissed == other.promptDismissed;

  @override
  int get hashCode =>
      Object.hash(currentHours, isOverThreshold, promptDismissed);
}
