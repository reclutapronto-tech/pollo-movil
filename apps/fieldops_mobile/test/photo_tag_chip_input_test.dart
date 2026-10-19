import 'package:fieldops_mobile/features/camera/widgets/photo_tag_chip_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('PhotoTagChipInput shows typed tag as a chip after submit',
      (tester) async {
    final changes = <List<String>>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PhotoTagChipInput(
              tags: const [],
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'roof damage');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(changes, isNotEmpty);
    expect(changes.last, ['roof damage']);
  });

  testWidgets('PhotoTagChipInput renders one chip per provided tag',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PhotoTagChipInput(
              tags: const ['before', 'roof'],
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('before'), findsOneWidget);
    expect(find.text('roof'), findsOneWidget);
    expect(find.byType(InputChip), findsNWidgets(2));
  });

  testWidgets('PhotoTagChipInput ignores duplicates (case-insensitive)',
      (tester) async {
    final changes = <List<String>>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: PhotoTagChipInput(
              tags: const ['Roof'],
              onChanged: changes.add,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'roof');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    // The dup is rejected — no change event emitted.
    expect(changes, isEmpty);
  });
}
