import 'package:fieldops_mobile/features/breadcrumbs/data/breadcrumb_repository_provider.dart';
import 'package:fieldops_mobile/features/breadcrumbs/domain/breadcrumb_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Query parameters for fetching breadcrumbs.
class BreadcrumbQuery {
  const BreadcrumbQuery({
    required this.shiftDate,
    this.userId,
    this.jobId,
  });

  final String shiftDate;
  final String? userId;
  final String? jobId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BreadcrumbQuery &&
          shiftDate == other.shiftDate &&
          userId == other.userId &&
          jobId == other.jobId;

  @override
  int get hashCode => Object.hash(shiftDate, userId, jobId);
}

/// Provider that fetches breadcrumbs for a given query.
final breadcrumbPlaybackControllerProvider = FutureProvider.autoDispose
    .family<List<Breadcrumb>, BreadcrumbQuery>((ref, query) {
  return ref.read(breadcrumbRepositoryProvider).fetchBreadcrumbs(
        shiftDate: query.shiftDate,
        userId: query.userId,
        jobId: query.jobId,
      );
});
