// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tracking_app/main.dart';
import 'package:tracking_app/pages/home_page.dart';

void main() {
  testWidgets('App loads HomePage', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TrackingApp());

    // Verify that our counter starts at 0.
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('TrackIN'), findsOneWidget);
  
  });
}

