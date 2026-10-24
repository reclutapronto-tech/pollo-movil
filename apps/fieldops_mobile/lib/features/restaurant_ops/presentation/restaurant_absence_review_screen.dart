import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:fieldops_mobile/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RestaurantAbsenceReviewScreen extends ConsumerStatefulWidget {
  const RestaurantAbsenceReviewScreen({
    super.key,
    required this.branchId,
    required this.onReviewed,
  });

  final String branchId;
  final VoidCallback onReviewed;

  @override
  ConsumerState<RestaurantAbsenceReviewScreen> createState() =>
      _RestaurantAbsenceReviewScreenState();
}

class _RestaurantAbsenceReviewScreenState
    extends ConsumerState<RestaurantAbsenceReviewScreen> {
  late Future<OpsJson> _requests;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _requests = _fetch();
  }

  Future<OpsJson> _fetch() => ref
      .read(restaurantOpsRepositoryProvider)
      .fetchPendingAbsences(widget.branchId);

  Future<void> _refresh() async {
    final request = _fetch();
    setState(() => _requests = request);
    try {
      await request;
    } catch (_) {
      // FutureBuilder displays the request failure and offers a retry.
    }
  }

  Future<void> _review(String id, String status) async {
    final l10n = AppLocalizations.of(context)!;
    if (_busyId != null) return;
    setState(() => _busyId = id);
    try {
      await ref
          .read(restaurantOpsRepositoryProvider)
          .reviewAbsence(
            branchId: widget.branchId,
            absenceId: id,
            status: status,
          );
      if (!mounted) return;
      widget.onReviewed();
      setState(() {
        _busyId = null;
        _requests = _fetch();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? l10n.restaurantAbsenceApproved
                : l10n.restaurantAbsenceRejected,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.restaurantAbsenceReviewError(error.toString())),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ref.listen<AsyncValue<void>>(restaurantRealtimeProvider(widget.branchId), (
      _,
      next,
    ) {
      if (next.hasValue && _busyId == null) _refresh();
    });
    return Scaffold(
      appBar: AppBar(title: Text(l10n.restaurantAbsenceReviewTitle)),
      body: FutureBuilder<OpsJson>(
        future: _requests,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.restaurantAbsenceLoadError),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _requests = _fetch()),
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data ?? const <String, dynamic>{};
          final offlineSnapshot = data['_offline_snapshot'] == true;
          final absences = (data['absences'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          if (absences.isEmpty && !offlineSnapshot) {
            return Center(child: Text(l10n.restaurantAbsenceNone));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount:
                  (absences.isEmpty ? 1 : absences.length) +
                  (offlineSnapshot ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (offlineSnapshot && index == 0) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(l10n.restaurantAbsenceOfflineNotice),
                  );
                }
                final absenceIndex = index - (offlineSnapshot ? 1 : 0);
                if (absences.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(l10n.restaurantAbsenceOfflineEmpty),
                    ),
                  );
                }
                final absence = absences[absenceIndex];
                final id = absence['id'] as String;
                final note = absence['note'] as String?;
                final startDate = DateTime.tryParse(
                  absence['start_date'] as String? ?? '',
                );
                final endDate = DateTime.tryParse(
                  absence['end_date'] as String? ?? '',
                );
                final dateRange = startDate != null && endDate != null
                    ? '${MaterialLocalizations.of(context).formatMediumDate(startDate)} – ${MaterialLocalizations.of(context).formatMediumDate(endDate)}'
                    : '${absence['start_date'] ?? ''} – ${absence['end_date'] ?? ''}';
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          absence['employee_name'] as String? ??
                              l10n.restaurantShiftTeamMember,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(dateRange),
                        if (note != null && note.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(note),
                        ],
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: !offlineSnapshot && _busyId == null
                                  ? () => _review(id, 'denied')
                                  : null,
                              icon: const Icon(Icons.close_rounded),
                              label: Text(l10n.restaurantAbsenceReject),
                            ),
                            FilledButton.icon(
                              onPressed: !offlineSnapshot && _busyId == null
                                  ? () => _review(id, 'approved')
                                  : null,
                              icon: _busyId == id
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded),
                              label: Text(l10n.restaurantAbsenceApprove),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
