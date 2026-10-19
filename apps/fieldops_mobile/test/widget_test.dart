import 'package:drift/native.dart';
import 'package:fieldops_mobile/app/app.dart';
import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:fieldops_mobile/features/auth/domain/auth_repository.dart';
import 'package:fieldops_mobile/features/auth/domain/user_role.dart';
import 'package:fieldops_mobile/features/clock/data/clock_repository_provider.dart';
import 'package:fieldops_mobile/features/clock/domain/clock_repository.dart';
import 'package:fieldops_mobile/features/jobs/data/jobs_repository_provider.dart';
import 'package:fieldops_mobile/features/jobs/domain/job_summary.dart';
import 'package:fieldops_mobile/features/jobs/domain/jobs_repository.dart';
import 'package:fieldops_mobile/features/home/data/worker_hours_repository_provider.dart';
import 'package:fieldops_mobile/features/home/domain/worker_hours_repository.dart';
import 'package:fieldops_mobile/features/home/domain/worker_hours_snapshot.dart';
import 'package:fieldops_mobile/features/schedule/data/schedule_repository_provider.dart';
import 'package:fieldops_mobile/features/schedule/domain/crew_schedule_shift.dart';
import 'package:fieldops_mobile/features/schedule/domain/schedule_repository.dart';
import 'package:fieldops_mobile/features/schedule/domain/worker_schedule_shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('shows configuration screen when Supabase env is missing', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _buildTestApp(
        environment: const FieldOpsEnvironment(
          supabaseUrl: '',
          supabaseAnonKey: '',
        ),
        repository: FakeAuthRepository(),
      ),
    );

    expect(find.text('Mobile app needs Supabase config'), findsOneWidget);
  });

  testWidgets('successful sign in transitions to assigned jobs', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final repository = FakeAuthRepository();
    await tester.pumpWidget(
      _buildTestApp(
        environment: const FieldOpsEnvironment(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabaseAnonKey: 'anon-key',
        ),
        repository: repository,
        jobsRepository: FakeJobsRepository(
          jobs: const [
            JobSummary(
              jobId: 'job-1',
              jobName: 'Grid Restoration',
              geofenceRadiusM: 150,
              taskCount: 2,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'worker@test.com');
    await tester.enterText(find.byType(TextFormField).last, 'password123');
    await tester.ensureVisible(find.text('Sign in to worker app'));
    await tester.tap(find.text('Sign in to worker app'));
    await tester.pumpAndSettle();

    expect(repository.lastEmail, 'worker@test.com');
    // After sign-in, the MainShell renders with the Home tab active
    expect(find.text('FieldOps'), findsOneWidget);
    // Navigate to Jobs tab to see assigned jobs
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    expect(find.text('Grid Restoration'), findsOneWidget);
  });

  testWidgets('failed sign in shows an inline error message', (tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _buildTestApp(
        environment: const FieldOpsEnvironment(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabaseAnonKey: 'anon-key',
        ),
        repository: FakeAuthRepository(shouldFail: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'worker@test.com');
    await tester.enterText(find.byType(TextFormField).last, 'password123');
    await tester.ensureVisible(find.text('Sign in to worker app'));
    await tester.tap(find.text('Sign in to worker app'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sign-in failed'), findsOneWidget);
  });

  testWidgets('signed-in worker sees assigned jobs', (tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _buildTestApp(
        environment: const FieldOpsEnvironment(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabaseAnonKey: 'anon-key',
        ),
        repository: FakeAuthRepository(initialEmail: 'worker@test.com'),
        jobsRepository: FakeJobsRepository(
          jobs: const [
            JobSummary(
              jobId: 'job-1',
              jobName: 'Grid Restoration',
              geofenceRadiusM: 150,
              taskCount: 2,
            ),
            JobSummary(
              jobId: 'job-2',
              jobName: 'Substation Audit',
              geofenceRadiusM: 250,
              taskCount: 0,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to Jobs tab to see assigned jobs
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    expect(find.text('My Jobs'), findsOneWidget);
    expect(find.text('Grid Restoration'), findsOneWidget);
    expect(find.text('Substation Audit'), findsOneWidget);
    expect(find.textContaining('2 tasks'), findsOneWidget);
  });

  testWidgets('signed-in worker sees live hour totals', (tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _buildTestApp(
        environment: const FieldOpsEnvironment(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabaseAnonKey: 'anon-key',
        ),
        repository: FakeAuthRepository(initialEmail: 'worker@test.com'),
        jobsRepository: FakeJobsRepository(
          jobs: const [
            JobSummary(
              jobId: 'job-1',
              jobName: 'Grid Restoration',
              geofenceRadiusM: 150,
              taskCount: 2,
            ),
          ],
        ),
        workerHoursRepository: FakeWorkerHoursRepository(
          snapshot: const WorkerHoursSnapshot(
            hoursToday: 3.0,
            hoursThisWeek: 18.5,
            hoursThisMonth: 64.0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3.0h'), findsOneWidget);
    expect(find.text('18.5h'), findsOneWidget);
    expect(find.text('64.0h'), findsOneWidget);
  });

  testWidgets('offline jobs failure shows retryable state', (tester) async {
    _usePhoneViewport(tester);
    final jobsRepository = FakeJobsRepository(
      fallbackFailure: const JobsRepositoryException.offline(),
    );

    await tester.pumpWidget(
      _buildTestApp(
        environment: const FieldOpsEnvironment(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabaseAnonKey: 'anon-key',
        ),
        repository: FakeAuthRepository(initialEmail: 'worker@test.com'),
        jobsRepository: jobsRepository,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    final firstFetchCount = jobsRepository.fetchCount;

    // Navigate to Jobs tab to see the error state
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();

    expect(find.text('You are offline'), findsOneWidget);
    expect(find.text('Retry jobs'), findsOneWidget);

    await tester.tap(find.text('Retry jobs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(jobsRepository.fetchCount, greaterThan(firstFetchCount));
    expect(find.text('You are offline'), findsOneWidget);
  });

  testWidgets('worker can clock in from an assigned job card', (tester) async {
    _usePhoneViewport(tester);
    final clockRepository = FakeClockRepository();
    await tester.pumpWidget(
      _buildTestApp(
        environment: const FieldOpsEnvironment(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabaseAnonKey: 'anon-key',
        ),
        repository: FakeAuthRepository(initialEmail: 'worker@test.com'),
        jobsRepository: FakeJobsRepository(
          jobs: const [
            JobSummary(
              jobId: 'job-1',
              jobName: 'Grid Restoration',
              geofenceRadiusM: 150,
              taskCount: 2,
            ),
          ],
        ),
        clockRepository: clockRepository,
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to Jobs tab and clock in
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clock in').first);
    await tester.pumpAndSettle();

    expect(clockRepository.lastJobId, 'job-1');
    // Navigate to Home to verify clock status
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Clocked in'), findsOneWidget);
    expect(find.textContaining('Grid Restoration'), findsWidgets);
  });

  testWidgets('camera FAB appears only when clocked in', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final clockRepository = FakeClockRepository();
    await tester.pumpWidget(
      _buildTestApp(
        environment: const FieldOpsEnvironment(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabaseAnonKey: 'anon-key',
        ),
        repository: FakeAuthRepository(initialEmail: 'worker@test.com'),
        jobsRepository: FakeJobsRepository(
          jobs: const [
            JobSummary(
              jobId: 'job-1',
              jobName: 'Grid Restoration',
              geofenceRadiusM: 150,
              taskCount: 2,
            ),
          ],
        ),
        clockRepository: clockRepository,
      ),
    );
    await tester.pumpAndSettle();

    // Before clocking in, no camera FAB
    expect(find.byType(FloatingActionButton), findsNothing);

    // Navigate to Jobs tab and clock in
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clock in').first);
    await tester.pumpAndSettle();

    // After clocking in, camera FAB appears on the MainShell scaffold
    expect(find.byType(FloatingActionButton), findsOneWidget);
    // Job tasks still visible
    expect(find.textContaining('2 tasks'), findsOneWidget);
  });

  testWidgets('worker can clock out after clocking in', (tester) async {
    _usePhoneViewport(tester);
    final clockRepository = FakeClockRepository();
    await tester.pumpWidget(
      _buildTestApp(
        environment: const FieldOpsEnvironment(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabaseAnonKey: 'anon-key',
        ),
        repository: FakeAuthRepository(initialEmail: 'worker@test.com'),
        jobsRepository: FakeJobsRepository(
          jobs: const [
            JobSummary(
              jobId: 'job-1',
              jobName: 'Grid Restoration',
              geofenceRadiusM: 150,
              taskCount: 2,
            ),
          ],
        ),
        clockRepository: clockRepository,
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to Jobs tab and clock in
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clock in').first);
    await tester.pumpAndSettle();

    // Navigate to Home tab where clock status panel shows
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Clocked in'), findsOneWidget);

    // Now clock out — triggers the shift wrap-up dialog first
    await tester.tap(find.text('Clock out'));
    await tester.pumpAndSettle();

    // The ShiftWrapupDialog shows; submit to complete clock-out
    expect(find.text('Submit & Clock Out'), findsOneWidget);
    await tester.tap(find.text('Submit & Clock Out'));
    await tester.pumpAndSettle();

    expect(clockRepository.lastClockOutJobId, 'job-1');
    expect(find.text('Ready to clock in'), findsOneWidget);
    expect(
      find.textContaining('Clocked out of Grid Restoration'),
      findsOneWidget,
    );
  });

  testWidgets('clock in failure surfaces an inline message', (tester) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _buildTestApp(
        environment: const FieldOpsEnvironment(
          supabaseUrl: 'http://127.0.0.1:54321',
          supabaseAnonKey: 'anon-key',
        ),
        repository: FakeAuthRepository(initialEmail: 'worker@test.com'),
        jobsRepository: FakeJobsRepository(
          jobs: const [
            JobSummary(
              jobId: 'job-1',
              jobName: 'Grid Restoration',
              geofenceRadiusM: 150,
              taskCount: 2,
            ),
          ],
        ),
        clockRepository: FakeClockRepository(
          failure: const ClockRepositoryException.offline(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Navigate to Jobs tab and attempt clock in
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clock in').first);
    await tester.pumpAndSettle();

    // Navigate to Home tab where error panel shows
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('Clock in failed'), findsOneWidget);
    expect(
      find.textContaining('Connection is unavailable for clock events.'),
      findsOneWidget,
    );
  });
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _buildTestApp({
  required FieldOpsEnvironment environment,
  required AuthRepository repository,
  JobsRepository? jobsRepository,
  ClockRepository? clockRepository,
  WorkerHoursRepository? workerHoursRepository,
  ScheduleRepository? scheduleRepository,
}) {
  return ProviderScope(
    overrides: [
      fieldOpsEnvironmentProvider.overrideWithValue(environment),
      authRepositoryProvider.overrideWithValue(repository),
      // Stub Supabase-dependent providers so tests never call Supabase.instance.
      userRoleProvider.overrideWithValue(UserRole.worker),
      // Use an in-memory Drift database — avoids FlutterSecureStorage + SQLCipher
      // which are unavailable in the test environment.
      localDatabaseProvider.overrideWith(
        (ref) {
          final db = LocalDatabase.forTesting(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        },
      ),
      if (jobsRepository != null)
        jobsRepositoryProvider.overrideWithValue(jobsRepository),
      if (clockRepository != null)
        clockRepositoryProvider.overrideWithValue(clockRepository),
      if (workerHoursRepository != null)
        workerHoursRepositoryProvider.overrideWithValue(workerHoursRepository),
      if (scheduleRepository != null)
        scheduleRepositoryProvider.overrideWithValue(scheduleRepository),
    ],
    child: const FieldOpsApp(),
  );
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.shouldFail = false, String? initialEmail})
    : _currentEmail = initialEmail;

  final bool shouldFail;
  String? lastEmail;
  String? _currentEmail;

  @override
  bool get isAuthenticated => _currentEmail != null;

  @override
  String? get currentUserEmail => _currentEmail;

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    if (shouldFail) {
      throw Exception('bad credentials');
    }
    _currentEmail = email;
  }

  @override
  Future<void> signOut() async {
    _currentEmail = null;
  }
}

class FakeJobsRepository implements JobsRepository {
  FakeJobsRepository({
    this.jobs = const [],
    List<JobsRepositoryException?>? failures,
    this.fallbackFailure,
  }) : _failures = failures ?? const [];

  final List<JobSummary> jobs;
  final List<JobsRepositoryException?> _failures;
  final JobsRepositoryException? fallbackFailure;
  int fetchCount = 0;

  @override
  Future<List<JobSummary>> fetchActiveJobs() async {
    final index = fetchCount;
    fetchCount += 1;
    if (index < _failures.length && _failures[index] != null) {
      throw _failures[index]!;
    }
    if (index >= _failures.length && fallbackFailure != null) {
      throw fallbackFailure!;
    }
    return jobs;
  }
}

class FakeClockRepository implements ClockRepository {
  FakeClockRepository({this.failure});

  final ClockRepositoryException? failure;
  String? lastJobId;
  String? lastClockOutJobId;

  @override
  Future<ClockActionResult> clockIn({required String jobId}) async {
    lastJobId = jobId;
    if (failure != null) {
      throw failure!;
    }

    return ClockActionResult(
      eventId: 'clock-event-1',
      occurredAt: DateTime.utc(2026, 4, 3, 12, 0),
    );
  }

  @override
  Future<ClockActionResult> clockOut({required String jobId}) async {
    lastClockOutJobId = jobId;
    if (failure != null) {
      throw failure!;
    }

    return ClockActionResult(
      eventId: 'clock-event-2',
      occurredAt: DateTime.utc(2026, 4, 3, 17, 0),
    );
  }

  @override
  Future<ClockActionResult> breakStart({required String jobId}) async {
    if (failure != null) throw failure!;
    return ClockActionResult(
      eventId: 'break-start-1',
      occurredAt: DateTime.utc(2026, 4, 3, 14, 0),
    );
  }

  @override
  Future<ClockActionResult> breakEnd({required String jobId}) async {
    if (failure != null) throw failure!;
    return ClockActionResult(
      eventId: 'break-end-1',
      occurredAt: DateTime.utc(2026, 4, 3, 14, 30),
    );
  }
}

class FakeWorkerHoursRepository implements WorkerHoursRepository {
  FakeWorkerHoursRepository({required this.snapshot, this.failure});

  final WorkerHoursSnapshot snapshot;
  final WorkerHoursRepositoryException? failure;

  @override
  Future<WorkerHoursSnapshot> fetchSummary() async {
    if (failure != null) {
      throw failure!;
    }
    return snapshot;
  }
}

class FakeScheduleRepository implements ScheduleRepository {
  FakeScheduleRepository({this.shifts = const []});

  final List<WorkerScheduleShift> shifts;

  @override
  Future<List<WorkerScheduleShift>> fetchMySchedule({
    DateTime? from,
    DateTime? to,
  }) async {
    return shifts;
  }

  @override
  Future<String> requestShiftSwap({
    required String shiftId,
    String? notes,
  }) async {
    return 'swap-1';
  }

  @override
  Future<List<CrewScheduleShift>> fetchCrewSchedule({
    DateTime? from,
    DateTime? to,
  }) async {
    return [];
  }

  @override
  Future<bool> saveCrewReorder(List<CrewScheduleShift> shifts) async {
    return true;
  }

  @override
  Future<List<SwapRequest>> fetchSwapRequests({String status = 'pending'}) async {
    return const [];
  }

  @override
  Future<void> approveSwap(String swapRequestId, {String? reason}) async {}

  @override
  Future<void> denySwap(String swapRequestId, {required String reason}) async {}

  @override
  Future<void> cancelSwap(String swapRequestId) async {}

  @override
  Future<int> copyWeek({
    required DateTime sourceStart,
    required DateTime sourceEnd,
    required DateTime targetStart,
  }) async {
    return 0;
  }
}
