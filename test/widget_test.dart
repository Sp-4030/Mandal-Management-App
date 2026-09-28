// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:hindvi_app/main.dart';

void main() {
  testWidgets('dashboard presents the mandal workflows', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HindviApp());
    await tester.pumpAndSettle();

    expect(find.text('हिंदवी स्वराज्य'), findsNWidgets(2));
    expect(find.text('मंडळ व्यवस्थापन प्रणाली'), findsOneWidget);
    expect(find.text('वर्गणी'), findsOneWidget);
    expect(find.text('प्रसाद देणगी'), findsOneWidget);
    expect(find.text('प्रसाद साहित्य'), findsOneWidget);
    expect(find.text('वार्षिक अहवाल'), findsOneWidget);
    expect(find.text('बॅकअप आणि पुनर्स्थापना'), findsOneWidget);
  });
}
