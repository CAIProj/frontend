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

testWidgets('HomePage contains expected widgets', (WidgetTester tester) async {
  await tester.pumpWidget(const TrackingApp());

  // Check for a floating action button
  expect(find.byType(FloatingActionButton), findsOneWidget);

  // Check for a ListView or any other main widget you use
  expect(find.byType(ListView), findsAtLeastNWidgets(1));

  // Check for a specific text or button
  expect(find.text('About TrackIN'), findsOneWidget);
});

testWidgets('Tap + button and expect increment or dialog', (WidgetTester tester) async {
  await tester.pumpWidget(const TrackingApp());

  // Tap on a '+' icon if it exists
  await tester.tap(find.byIcon(Icons.add));
  await tester.pump();

  // Check result of the tap
  expect(find.text('1'), findsOneWidget); 
});

testWidgets('Navigate to another page', (WidgetTester tester) async {
  await tester.pumpWidget(const TrackingApp());

  // Tap on a navigation button
  await tester.tap(find.text('Details'));
  await tester.pumpAndSettle();

  // Verify the new screen
  expect(find.text('Details'), findsOneWidget); 
});


