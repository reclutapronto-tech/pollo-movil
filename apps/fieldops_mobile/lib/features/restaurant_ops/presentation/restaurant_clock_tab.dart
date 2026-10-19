import 'dart:async';

import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/features/restaurant_ops/presentation/restaurant_sync_recovery_panel.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RestaurantClockTab extends ConsumerStatefulWidget {
  const RestaurantClockTab({
    super.key,
    required this.branchId,
    required this.branchName,
    required this.requireGps,
  });

  final String branchId;
  final String branchName;
  final bool requireGps;

  @override
  ConsumerState<RestaurantClockTab> createState() => _RestaurantClockTabState();
}

class _RestaurantClockTabState extends ConsumerState<RestaurantClockTab> {
  bool _saving = false;
  DateTime? _attendanceHistoryDate;
  final Map<String, bool> _optimisticClockState = {};
  final Map<String, DateTime> _optimisticClockInAt = {};
  final Set<String> _pendingClockBranches = {};

  @override
  void initState() {
    super.initState();
    unawaited(_restorePendingClockState(widget.branchId));
  }

  @override
  void didUpdateWidget(covariant RestaurantClockTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) {
      _attendanceHistoryDate = null;
      unawaited(_restorePendingClockState(widget.branchId));
    }
  }

  Future<void> _restorePendingClockState(
    String branchId, {
    bool force = false,
  }) async {
    OpsJson? pending;
    try {
      pending = await ref
          .read(restaurantOpsRepositoryProvider)
          .pendingClockState(branchId);
    } on Object {
      return;
    }
    if (!mounted ||
        widget.branchId != branchId ||
        (!force && _pendingClockBranches.contains(branchId)))
      return;
    setState(() {
      if (pending == null) {
        _optimisticClockState.remove(branchId);
        _optimisticClockInAt.remove(branchId);
        _pendingClockBranches.remove(branchId);
        return;
      }
      final clockedIn = pending['clocked_in'] == true;
      _optimisticClockState[branchId] = clockedIn;
      _pendingClockBranches.add(branchId);
      final clockInAt = DateTime.tryParse(
        pending['clock_in_at'] as String? ?? '',
      );
      if (clockedIn && clockInAt != null) {
        _optimisticClockInAt[branchId] = clockInAt;
      } else {
        _optimisticClockInAt.remove(branchId);
      }
    });
  }

  Future<Position?> _positionIfRequired({required bool requireGps}) async {
    if (!requireGps) return null;
    final l10n = AppLocalizations.of(context)!;
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw RestaurantClockException(l10n.restaurantClockGpsServiceOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw RestaurantClockException(l10n.restaurantClockGpsPermissionRequired);
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw RestaurantClockException(
        l10n.restaurantClockGpsLocationUnavailable,
      );
    } on Object {
      throw RestaurantClockException(
        l10n.restaurantClockGpsLocationUnavailable,
      );
    }
  }

  Future<void> _record(bool clockedIn) async {
    if (_saving) return;
    final branchId = widget.branchId;
    final branchName = widget.branchName;
    final requireGps = widget.requireGps;
    final l10n = AppLocalizations.of(context)!;
    final occurredAt = DateTime.now();
    setState(() => _saving = true);
    try {
      final position = await _positionIfRequired(requireGps: requireGps);
      final result = await ref
          .read(restaurantOpsRepositoryProvider)
          .recordTimeEvent(
            branchId: branchId,
            eventType: clockedIn ? 'clock_out' : 'clock_in',
            occurredAt: occurredAt,
            latitude: position?.latitude,
            longitude: position?.longitude,
            accuracyMeters: position?.accuracy,
          );
      _invalidateAttendanceHistory(branchId);
      ref.invalidate(restaurantDashboardProvider(branchId));
      if (!mounted) return;
      setState(() {
        if (result['queued'] == true) {
          final nextClockedIn = !clockedIn;
          _optimisticClockState[branchId] = nextClockedIn;
          _pendingClockBranches.add(branchId);
          if (nextClockedIn) {
            _optimisticClockInAt[branchId] = occurredAt;
          } else {
            _optimisticClockInAt.remove(branchId);
          }
        } else {
          _optimisticClockState.remove(branchId);
          _optimisticClockInAt.remove(branchId);
          _pendingClockBranches.remove(branchId);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['queued'] == true
                ? l10n.restaurantClockQueued(branchName)
                : clockedIn
                ? l10n.restaurantClockExitSaved(branchName)
                : l10n.restaurantClockEntrySaved(branchName),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _formatClockTime(Object? value) {
    if (value is! String) return null;
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return null;
    return MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(date));
  }

  DateTime? _parseCalendarDate(Object? value) {
    if (value is! String) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) return null;
    return date;
  }

  String _calendarDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickAttendanceHistoryDate(DateTime initialDate) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _attendanceHistoryDate = DateTime(chosen.year, chosen.month, chosen.day);
    });
  }

  void _invalidateAttendanceHistory(String branchId) {
    final branchDate = ref
        .read(restaurantDashboardProvider(branchId))
        .asData
        ?.value['local_date'];
    final dates = <String>{
      if (branchDate is String) branchDate,
      if (_attendanceHistoryDate != null)
        _calendarDate(_attendanceHistoryDate!),
    };
    if (dates.isEmpty) dates.add(_calendarDate(DateTime.now()));
    for (final date in dates) {
      ref.invalidate(
        restaurantAttendanceHistoryProvider(
          (branchId: branchId, forDate: date),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.listen<AsyncValue<void>>(restaurantRealtimeProvider(widget.branchId), (
      previous,
      next,
    ) {
      if (next.hasValue) {
        final branchId = widget.branchId;
        _invalidateAttendanceHistory(branchId);
        ref.invalidate(restaurantDashboardProvider(branchId));
        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 500),
            () => _restorePendingClockState(branchId, force: true),
          ),
        );
      }
    });
    final dashboard = ref.watch(restaurantDashboardProvider(widget.branchId));
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.restaurantClockTitle),
            Text(
              widget.branchName,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error.toString()),
          ),
        ),
        data: (data) {
          final branchDate =
              _parseCalendarDate(data['local_date']) ?? DateTime.now();
          final attendanceDate = _attendanceHistoryDate ?? branchDate;
          final attendanceDateKey = _calendarDate(attendanceDate);
          final attendanceHistoryKey = (
            branchId: widget.branchId,
            forDate: attendanceDateKey,
          );
          final attendanceHistory = ref.watch(
            restaurantAttendanceHistoryProvider(attendanceHistoryKey),
          );
          final session = data['current_time_session'] as Map<String, dynamic>?;
          final clockedIn =
              _optimisticClockState[widget.branchId] ?? (session != null);
          final clockIn = clockedIn
              ? _optimisticClockInAt[widget.branchId] ??
                    DateTime.tryParse(session?['clock_in_at'] as String? ?? '')
              : null;
          final clockInLabel = clockedIn
              ? (session?['clock_in_local_time'] as String? ??
                    _formatClockTime(clockIn?.toIso8601String()))
              : null;
          final userId = Supabase.instance.client.auth.currentUser?.id;
          final members = (data['members'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>();
          final ownMemberships = members.where(
            (member) => member['user_id'] == userId,
          );
          final ownMembership = ownMemberships.isEmpty
              ? null
              : ownMemberships.first;
          final canManage = const {
            'admin',
            'supervisor',
          }.contains(ownMembership?['access_role'] as String?);
          final activeSessions =
              (data['active_time_sessions'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .toList(growable: false);
          final todaySessions =
              (data['today_time_sessions'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .toList(growable: false);
          final myTimeSessions =
              (data['my_time_sessions'] as List<dynamic>? ?? const [])
                  .whereType<Map<String, dynamic>>()
                  .toList(growable: false);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const RestaurantSyncRecoveryPanel(),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clockedIn
                            ? l10n.restaurantClockActive
                            : l10n.restaurantClockInactive,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (clockInLabel != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l10n.restaurantClockEntryTime(clockInLabel),
                          ),
                        ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : () => _record(clockedIn),
                          icon: Icon(
                            clockedIn
                                ? Icons.logout_rounded
                                : Icons.login_rounded,
                          ),
                          label: Text(
                            _saving
                                ? l10n.restaurantClockSaving
                                : clockedIn
                                ? l10n.clockOut
                                : l10n.clockIn,
                          ),
                        ),
                      ),
                      if (_pendingClockBranches.contains(widget.branchId))
                        Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Text(l10n.restaurantClockPendingSync),
                        ),
                    ],
                  ),
                ),
              ),
              if (canManage) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.restaurantClockActiveEntries,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (activeSessions.isEmpty)
                          Text(l10n.restaurantClockNoActiveEntries),
                        ...activeSessions.map((item) {
                          final time =
                              item['clock_in_local_time'] as String? ??
                              _formatClockTime(item['clock_in_at']) ??
                              l10n.restaurantClockUnavailableTime;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.how_to_reg_outlined),
                            title: Text(
                              item['employee_name'] as String? ??
                                  l10n.restaurantClockTeamMember,
                            ),
                            subtitle: Text(l10n.restaurantClockEntryAt(time)),
                          );
                        }),
                        Text(
                          l10n.restaurantClockActivePrivacy,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.restaurantClockTodayAttendance,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (todaySessions.isEmpty)
                          Text(l10n.restaurantClockNoBranchEntries),
                        ...todaySessions.map((item) {
                          final start =
                              item['clock_in_local_time'] as String? ??
                              _formatClockTime(item['clock_in_at']) ??
                              l10n.restaurantClockUnavailableTime;
                          final end =
                              item['clock_out_local_time'] as String? ??
                              _formatClockTime(item['clock_out_at']);
                          final entryLabel =
                              item['clock_in_local_date'] == data['local_date']
                              ? l10n.restaurantClockEntry
                              : l10n.restaurantClockEntryForDate(
                                  item['clock_in_local_date'] as String? ??
                                      l10n.restaurantClockPreviousDate,
                                );
                          final exitLabel = end == null
                              ? l10n.restaurantClockNoExit
                              : l10n.restaurantClockExitAt(end);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              end == null
                                  ? Icons.login_rounded
                                  : Icons.how_to_reg_outlined,
                            ),
                            title: Text(
                              item['employee_name'] as String? ??
                                  l10n.restaurantClockTeamMember,
                            ),
                            subtitle: Text(
                              l10n.restaurantClockSessionSummary(
                                entryLabel,
                                start,
                                exitLabel,
                              ),
                            ),
                          );
                        }),
                        Text(
                          l10n.restaurantClockAttendancePrivacy,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (!canManage) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.restaurantClockMyAttendance,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (myTimeSessions.isEmpty)
                          Text(l10n.restaurantClockNoMyEntriesToday),
                        ...myTimeSessions.map((item) {
                          final start =
                              item['clock_in_local_time'] as String? ??
                              _formatClockTime(item['clock_in_at']) ??
                              l10n.restaurantClockUnavailableTime;
                          final end =
                              item['clock_out_local_time'] as String? ??
                              _formatClockTime(item['clock_out_at']);
                          final date = item['clock_in_local_date'] as String?;
                          final entryLabel = date == data['local_date']
                              ? l10n.restaurantClockToday
                              : date ?? l10n.restaurantClockPreviousDate;
                          final exitLabel = end == null
                              ? l10n.restaurantClockNoExit
                              : l10n.restaurantClockExitAt(end);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              end == null
                                  ? Icons.login_rounded
                                  : Icons.how_to_reg_outlined,
                            ),
                            title: Text(entryLabel),
                            subtitle: Text(
                              l10n.restaurantClockSessionSummary(
                                l10n.restaurantClockEntry,
                                start,
                                exitLabel,
                              ),
                            ),
                          );
                        }),
                        Text(
                          l10n.restaurantClockMyPrivacy,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _attendanceHistoryCopy(context, 'title'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              _pickAttendanceHistoryDate(attendanceDate),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: Text(
                            '${_attendanceHistoryCopy(context, 'choose_date')}: '
                            '${MaterialLocalizations.of(context).formatMediumDate(attendanceDate)}',
                          ),
                        ),
                      ),
                      attendanceHistory.when(
                        loading: () => const LinearProgressIndicator(),
                        error: (error, stackTrace) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_attendanceHistoryCopy(context, 'load_error')),
                            TextButton.icon(
                              onPressed: () => ref.invalidate(
                                restaurantAttendanceHistoryProvider(
                                  attendanceHistoryKey,
                                ),
                              ),
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                _attendanceHistoryCopy(context, 'retry'),
                              ),
                            ),
                          ],
                        ),
                        data: (historyData) {
                          final sessions =
                              (historyData['sessions'] as List<dynamic>? ??
                                      const [])
                                  .whereType<Map<String, dynamic>>()
                                  .toList(growable: false);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (historyData['_offline_snapshot'] == true)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(
                                    _attendanceHistoryCopy(context, 'offline'),
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ),
                              if (sessions.isEmpty)
                                Text(
                                  _attendanceHistoryCopy(context, 'empty'),
                                ),
                              ...sessions.map((item) {
                                final clockInDate =
                                    item['clock_in_local_date'] as String?;
                                final entryLabel =
                                    clockInDate == attendanceDateKey
                                    ? l10n.restaurantClockEntry
                                    : l10n.restaurantClockEntryForDate(
                                        clockInDate ??
                                            l10n.restaurantClockPreviousDate,
                                      );
                                final start =
                                    item['clock_in_local_time'] as String? ??
                                    _formatClockTime(item['clock_in_at']) ??
                                    l10n.restaurantClockUnavailableTime;
                                final end =
                                    item['clock_out_local_time'] as String? ??
                                    _formatClockTime(item['clock_out_at']);
                                final exitLabel = end == null
                                    ? l10n.restaurantClockNoExit
                                    : l10n.restaurantClockExitAt(end);
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    end == null
                                        ? Icons.login_rounded
                                        : Icons.how_to_reg_outlined,
                                  ),
                                  title: Text(
                                    canManage
                                        ? item['employee_name'] as String? ??
                                              l10n.restaurantClockTeamMember
                                        : entryLabel,
                                  ),
                                  subtitle: Text(
                                    l10n.restaurantClockSessionSummary(
                                      entryLabel,
                                      start,
                                      exitLabel,
                                    ),
                                  ),
                                );
                              }),
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  canManage
                                      ? l10n.restaurantClockAttendancePrivacy
                                      : l10n.restaurantClockMyPrivacy,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.requireGps
                        ? l10n.restaurantClockGpsRequired
                        : l10n.restaurantClockGpsNotRequired,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.restaurantClockNoPayroll,
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          );
        },
      ),
    );
  }
}

class RestaurantClockException implements Exception {
  const RestaurantClockException(this.message);
  final String message;
  @override
  String toString() => message;
}

String _attendanceHistoryCopy(BuildContext context, String key) {
  const translations = <String, Map<String, String>>{
    'es': {
      'title': 'Historial de checadas',
      'choose_date': 'Elegir fecha',
      'empty': 'No hay checadas para esta fecha.',
      'load_error': 'No se pudo cargar el historial.',
      'retry': 'Reintentar',
      'offline': 'Mostrando la última copia guardada sin conexión.',
    },
    'en': {
      'title': 'Clock-in history',
      'choose_date': 'Choose date',
      'empty': 'No clock-ins for this date.',
      'load_error': 'Could not load the history.',
      'retry': 'Try again',
      'offline': 'Showing the last saved copy while offline.',
    },
    'fr': {
      'title': 'Historique des pointages',
      'choose_date': 'Choisir une date',
      'empty': 'Aucun pointage pour cette date.',
      'load_error': 'Impossible de charger l’historique.',
      'retry': 'Réessayer',
      'offline': 'Dernière copie enregistrée affichée hors ligne.',
    },
    'th': {
      'title': 'ประวัติการลงเวลา',
      'choose_date': 'เลือกวันที่',
      'empty': 'ไม่มีรายการลงเวลาในวันนี้ที่เลือก',
      'load_error': 'โหลดประวัติไม่สำเร็จ',
      'retry': 'ลองอีกครั้ง',
      'offline': 'กำลังแสดงข้อมูลล่าสุดที่บันทึกไว้ขณะออฟไลน์',
    },
    'zh': {
      'title': '打卡记录',
      'choose_date': '选择日期',
      'empty': '所选日期没有打卡记录。',
      'load_error': '无法加载记录。',
      'retry': '重试',
      'offline': '当前离线，显示最近保存的数据。',
    },
  };
  final language = Localizations.localeOf(context).languageCode;
  return translations[language]?[key] ?? translations['en']![key]!;
}
