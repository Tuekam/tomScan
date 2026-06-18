import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomscan/main.dart';

void main() {
  testWidgets('TomScan app', (WidgetTester tester) async {
    await tester.pumpWidget(const TomScanApp());
    expect(find.text('Diagnostic'), findsOneWidget);
  });
}
