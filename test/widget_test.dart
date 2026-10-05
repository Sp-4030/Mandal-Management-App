import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hindvi_app/main.dart';
import 'package:hindvi_app/models/khajani_user.dart';
import 'package:hindvi_app/services/auth_service.dart';
import 'package:hindvi_app/services/security_enforcement_service.dart';

void main() {
  testWidgets('dashboard presents core workflows and Settings icon', (
    WidgetTester tester,
  ) async {
    SecurityEnforcementService.instance.setMockConnectivity(true);
    SecurityEnforcementService.instance.setMockBypassEnabled(true);

    AuthService.instance.setCurrentUserForTesting(
      const KhajaniUser(
        userId: 'test_latest',
        name: 'अमोल पाटील',
        passwordHash: 'hash',
        salt: 'salt',
        role: KhajaniRole.latestKhajani,
        createdAt: 1700000000000,
        updatedAt: 1700000000000,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: DashboardScreen(checkUpdateOnStartup: false),
      ),
    );
    await tester.pumpAndSettle();

    // Check header and core workflows
    expect(find.text('हिंदवी स्वराज्य'), findsNWidgets(2));
    expect(find.text('मंडळ व्यवस्थापन प्रणाली'), findsOneWidget);
    expect(find.text('वर्गणी'), findsOneWidget);
    expect(find.text('प्रसाद देणगी'), findsOneWidget);
    expect(find.text('प्रसाद साहित्य'), findsOneWidget);
    expect(find.text('मागील वर्षाचा खर्च'), findsOneWidget);
    expect(find.text('महाप्रसाद बाजार'), findsOneWidget);
    expect(find.text('वार्षिक अहवाल'), findsOneWidget);

    // Old cards must NOT appear on main dashboard
    expect(find.text('बॅकअप आणि पुनर्स्थापना'), findsNothing);
    expect(find.text('मंडळ डेटा ट्रान्सफर (मायग्रेशन)'), findsNothing);

    // Settings icon is present on AppBar
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // Tap Settings icon and verify modern Settings screen opens
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('सेटिंग्ज'), findsOneWidget);
    expect(find.text('डेटा व्यवस्थापन'), findsOneWidget);
    expect(find.text('मंडळ डेटा ट्रान्सफर'), findsOneWidget);
    expect(find.text('बॅकअप'), findsOneWidget);
    expect(find.text('रिस्टोर'), findsOneWidget);
    expect(find.text('जुना / Recovery Data'), findsOneWidget);
  });
}
