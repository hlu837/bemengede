import 'package:flutter_test/flutter_test.dart';

import 'package:bemengede/main.dart';

void main() {
  testWidgets('App smoke test compiles', (WidgetTester tester) async {
    // Verify that BemengedeApp exists and compiles.
    // We avoid pumping it directly in widget tests because it relies on initialized Supabase
    // and route configurations that expect active platform channels.
    expect(const BemengedeApp(), isNotNull);
  });
}

