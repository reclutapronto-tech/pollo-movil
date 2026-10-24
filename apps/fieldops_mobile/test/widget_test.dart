import 'package:drift/native.dart';
import 'package:fieldops_mobile/app/app.dart';
import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/core/data/local_database.dart';
import 'package:fieldops_mobile/features/auth/data/auth_repository_provider.dart';
import 'package:fieldops_mobile/features/auth/domain/auth_repository.dart';
import 'package:fieldops_mobile/features/auth/domain/user_role.dart';
import 'package:fieldops_mobile/features/restaurant_ops/data/restaurant_ops_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'local-widget-test-key',
    );
  });

  testWidgets('configuration instructions scroll on a short phone screen', (
    tester,
  ) async {
    _usePhoneViewport(tester, size: const Size(320, 480));
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
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('successful sign-in opens Pollo Móvil restaurant navigation', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    final repository = FakeAuthRepository();
    await tester.pumpWidget(
      _buildTestApp(
        environment: _configuredEnvironment,
        repository: repository,
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'worker@test.com');
    await tester.enterText(find.byType(TextFormField).last, 'password123');
    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(repository.lastEmail, 'worker@test.com');
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
      hasLength(5),
    );
  });

  testWidgets('failed sign-in keeps the worker on login with an error', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _buildTestApp(
        environment: _configuredEnvironment,
        repository: FakeAuthRepository(shouldFail: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'worker@test.com');
    await tester.enterText(find.byType(TextFormField).last, 'password123');
    await tester.ensureVisible(find.text('Iniciar sesión'));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sign-in failed'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('restaurant navigation switches between operational sections', (
    tester,
  ) async {
    _usePhoneViewport(tester);
    await tester.pumpWidget(
      _buildTestApp(
        environment: _configuredEnvironment,
        repository: FakeAuthRepository(initialEmail: 'worker@test.com'),
      ),
    );
    await tester.pumpAndSettle();

    final initialNavigation = tester.widget<NavigationBar>(
      find.byType(NavigationBar),
    );
    expect(initialNavigation.destinations, hasLength(5));
    expect(initialNavigation.selectedIndex, 0);

    final initialLabels = _navigationLabels(tester);
    expect(initialLabels, hasLength(5));
    await tester.tap(find.text(initialLabels[1]));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    final currentLabels = _navigationLabels(tester);
    await tester.tap(find.text(currentLabels[3]));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
  });
}

List<String> _navigationLabels(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.byType(Text),
      ),
    )
    .map((widget) => widget.data)
    .whereType<String>()
    .toList();

const _configuredEnvironment = FieldOpsEnvironment(
  supabaseUrl: 'http://127.0.0.1:54321',
  supabaseAnonKey: 'local-widget-test-key',
);

void _usePhoneViewport(
  WidgetTester tester, {
  Size size = const Size(430, 932),
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _buildTestApp({
  required FieldOpsEnvironment environment,
  required AuthRepository repository,
}) {
  return ProviderScope(
    overrides: [
      fieldOpsEnvironmentProvider.overrideWithValue(environment),
      authRepositoryProvider.overrideWithValue(repository),
      userRoleProvider.overrideWithValue(UserRole.worker),
      restaurantBranchesProvider.overrideWith(
        (ref) async => const <OpsJson>[],
      ),
      localDatabaseProvider.overrideWith((ref) {
        final database = LocalDatabase.forTesting(NativeDatabase.memory());
        ref.onDispose(database.close);
        return database;
      }),
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
    if (shouldFail) throw Exception('bad credentials');
    _currentEmail = email;
  }

  @override
  Future<void> signOut() async {
    _currentEmail = null;
  }
}
