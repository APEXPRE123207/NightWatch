import 'package:flutter_test/flutter_test.dart';
import 'package:night_watch_flutter/main.dart';

void main() {
  testWidgets('NightWatchApp builds and renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const NightWatchApp());

    // Verify Title & Navigation Destinations
    expect(find.text('🌙 NIGHT WATCH'), findsOneWidget);
    expect(find.text('Night Watch'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
  });
}
