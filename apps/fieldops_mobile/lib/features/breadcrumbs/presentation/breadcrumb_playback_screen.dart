import 'dart:async';
import 'dart:math' as math;

import 'package:fieldops_mobile/app/theme/app_theme.dart';
import 'package:fieldops_mobile/app/widgets/skeleton_loader.dart';
import 'package:fieldops_mobile/features/breadcrumbs/domain/breadcrumb_repository.dart';
import 'package:fieldops_mobile/features/breadcrumbs/presentation/breadcrumb_playback_controller.dart';
import 'package:fieldops_mobile/features/breadcrumbs/presentation/widgets/breadcrumb_map.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Displays and replays a worker's GPS breadcrumb trail for a shift.
class BreadcrumbPlaybackScreen extends ConsumerStatefulWidget {
  const BreadcrumbPlaybackScreen({
    super.key,
    required this.shiftDate,
    required this.jobName,
    this.userId,
    this.jobId,
  });

  final String shiftDate;
  final String jobName;
  final String? userId;
  final String? jobId;

  @override
  ConsumerState<BreadcrumbPlaybackScreen> createState() =>
      _BreadcrumbPlaybackScreenState();
}

class _BreadcrumbPlaybackScreenState
    extends ConsumerState<BreadcrumbPlaybackScreen> {
  int _playbackIndex = 0;
  bool _isPlaying = false;
  Timer? _timer;

  BreadcrumbQuery get _query => BreadcrumbQuery(
        shiftDate: widget.shiftDate,
        userId: widget.userId,
        jobId: widget.jobId,
      );

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPlayback(int totalPoints) {
    if (totalPoints <= 1) return;
    setState(() {
      _isPlaying = true;
      _playbackIndex = 0;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
      if (_playbackIndex >= totalPoints - 1) {
        timer.cancel();
        setState(() => _isPlaying = false);
        return;
      }
      setState(() => _playbackIndex++);
    });
  }

  void _stopPlayback() {
    _timer?.cancel();
    setState(() => _isPlaying = false);
  }

  void _resetPlayback(int totalPoints) {
    _timer?.cancel();
    setState(() {
      _playbackIndex = totalPoints - 1;
      _isPlaying = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = context.palette;
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(breadcrumbPlaybackControllerProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.jobName),
        leading: const BackButton(),
      ),
      body: state.when(
        data: (breadcrumbs) {
          if (breadcrumbs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.route_rounded,
                      size: 48,
                      color: Colors.black.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No route data',
                      style: textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'GPS breadcrumbs were not recorded for this shift.',
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            );
          }

          // Ensure playback index is within bounds
          final maxIndex = breadcrumbs.length - 1;
          final currentIndex =
              _isPlaying ? _playbackIndex : _playbackIndex.clamp(0, maxIndex);
          final currentBreadcrumb = breadcrumbs[currentIndex];

          return Column(
            children: [
              // Map area
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: BreadcrumbMap(
                    breadcrumbs: breadcrumbs,
                    playbackIndex: currentIndex,
                    trailColor: palette.signal,
                  ),
                ),
              ),

              // Info bar
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: palette.surfaceWhite,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 18,
                      color: palette.signal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${currentBreadcrumb.latitude.toStringAsFixed(5)}, '
                        '${currentBreadcrumb.longitude.toStringAsFixed(5)}',
                        style: textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Text(
                      _formatTime(currentBreadcrumb.recordedAt),
                      style: textTheme.labelMedium?.copyWith(
                        color: palette.steel,
                      ),
                    ),
                  ],
                ),
              ),

              // Stats row
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _StatChip(
                      icon: Icons.my_location_rounded,
                      label: '${breadcrumbs.length} points',
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      icon: Icons.schedule_rounded,
                      label: _durationLabel(breadcrumbs),
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      icon: Icons.straighten_rounded,
                      label: _distanceLabel(breadcrumbs),
                    ),
                  ],
                ),
              ),

              // Playback slider
              if (breadcrumbs.length > 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Slider(
                    value: currentIndex.toDouble(),
                    max: maxIndex.toDouble(),
                    divisions: maxIndex > 0 ? maxIndex : 1,
                    onChanged: (value) {
                      if (_isPlaying) _stopPlayback();
                      setState(() => _playbackIndex = value.round());
                    },
                  ),
                ),

              // Playback controls
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _resetPlayback(breadcrumbs.length),
                      icon: const Icon(Icons.replay_rounded),
                      tooltip: 'Reset',
                    ),
                    const SizedBox(width: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        await HapticFeedback.lightImpact();
                        if (_isPlaying) {
                          _stopPlayback();
                        } else {
                          _startPlayback(breadcrumbs.length);
                        }
                      },
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(_isPlaying ? 'Pause' : 'Play route'),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      onPressed: () {
                        if (_isPlaying) _stopPlayback();
                        setState(
                          () => _playbackIndex =
                              (_playbackIndex + 1).clamp(0, maxIndex),
                        );
                      },
                      icon: const Icon(Icons.skip_next_rounded),
                      tooltip: 'Next point',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.all(20),
          child: SkeletonLoader(itemCount: 3),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 48,
                  color: Colors.black.withValues(alpha: 0.3),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.scheduleUnavailable,
                  style: textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => ref.invalidate(
                    breadcrumbPlaybackControllerProvider(_query),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _durationLabel(List<Breadcrumb> bcs) {
    if (bcs.length < 2) return '--';
    final dur = bcs.last.recordedAt.difference(bcs.first.recordedAt);
    final hours = dur.inHours;
    final mins = dur.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }

  String _distanceLabel(List<Breadcrumb> bcs) {
    if (bcs.length < 2) return '--';
    var totalMeters = 0.0;
    for (var i = 1; i < bcs.length; i++) {
      totalMeters += _haversine(
        bcs[i - 1].latitude,
        bcs[i - 1].longitude,
        bcs[i].latitude,
        bcs[i].longitude,
      );
    }
    if (totalMeters < 1000) {
      return '${totalMeters.round()} m';
    }
    return '${(totalMeters / 1000).toStringAsFixed(1)} km';
  }

  /// Haversine distance in meters.
  double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final sinDLat = math.sin(dLat / 2);
    final sinDLng = math.sin(dLng / 2);
    final a = sinDLat * sinDLat +
        math.cos(_toRad(lat1)) * math.cos(_toRad(lat2)) * sinDLng * sinDLng;
    return r * 2 * math.asin(math.sqrt(a));
  }

  static double _toRad(double deg) => deg * math.pi / 180;
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
