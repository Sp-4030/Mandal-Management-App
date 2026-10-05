import 'package:flutter_test/flutter_test.dart';
import 'package:developer_app/main.dart';
import 'package:developer_app/services/developer_auth_service.dart';

void main() {
  setUp(() {
    DeveloperAuthService.instance.resetForTesting();
  });

  tearDown(() {
    DeveloperAuthService.instance.resetForTesting();
  });

  testWidgets('Developer App renders login screen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const DeveloperApp(autoConnect: false));
    await tester.pumpAndSettle();

    // Verify login screen elements are present
    expect(find.text('Developer Management App'), findsOneWidget);
    expect(find.text('Developer लॉगिन'), findsOneWidget);
  });
}
