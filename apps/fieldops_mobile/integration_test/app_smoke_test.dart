import 'package:fieldops_mobile/main.dart' as app;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('launches and requires explicit Supabase configuration', (tester) async {
    await app.main();
    await tester.pumpAndSettle();

    expect(find.text('Mobile app needs Supabase config'), findsOneWidget);
    expect(find.textContaining('Emulador Android:'), findsOneWidget);
  });
}
