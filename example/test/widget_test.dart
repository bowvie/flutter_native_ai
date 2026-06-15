import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_native_ai_example/main.dart';

void main() {
  testWidgets('shows the example prompt field', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Generate'), findsOneWidget);
  });
}
