import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:attendance_tracker/main.dart' show SoftTimeApp;

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SoftTimeApp()));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
