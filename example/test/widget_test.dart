// Widget test for Synheart Behavior Example app

import 'package:flutter_test/flutter_test.dart';

import 'package:synheart_behavior_example/main.dart';

void main() {
  testWidgets('App initializes and shows SDK status',
      (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the app title is displayed
    expect(find.text('Synheart Behavior Demo'), findsOneWidget);

    // Verify that SDK status section is present
    expect(find.text('SDK Status'), findsOneWidget);
  });
}
