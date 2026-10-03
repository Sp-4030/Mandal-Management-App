import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hindvi_app/screens/app_update_screen.dart';
import 'package:hindvi_app/screens/settings_screen.dart';
import 'package:hindvi_app/services/update_service.dart';

class MockHttpClientRequest extends Fake implements HttpClientRequest {
  final int statusCode;
  final String body;

  MockHttpClientRequest({required this.statusCode, required this.body});

  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async {
    return MockHttpClientResponse(statusCode: statusCode, body: body);
  }
}

class MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  MockHttpClientResponse({required this.statusCode, required this.body});

  @override
  final HttpHeaders headers = MockHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(utf8.encode(body)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpHeaders extends Fake implements HttpHeaders {
  final Map<String, String> _map = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _map[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => _map[name.toLowerCase()];
}

class MockHttpClient extends Fake implements HttpClient {
  final int statusCode;
  final String body;

  MockHttpClient({required this.statusCode, required this.body});

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return MockHttpClientRequest(statusCode: statusCode, body: body);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Semantic Version Comparison Tests', () {
    test('Correctly strips leading v and compares versions', () {
      final v1 = AppVersion.parse('v1.0.0');
      final v2 = AppVersion.parse('1.0.0');
      expect(v1.compareTo(v2), equals(0));
      expect(v1.isNewerThan(v2), isFalse);
    });

    test('1.0.0 < 1.1.0', () {
      final current = AppVersion.parse('1.0.0');
      final latest = AppVersion.parse('v1.1.0');
      expect(latest.isNewerThan(current), isTrue);
      expect(current.isNewerThan(latest), isFalse);
    });

    test('1.1.0 < 1.2.0', () {
      final current = AppVersion.parse('1.1.0');
      final latest = AppVersion.parse('1.2.0');
      expect(latest.isNewerThan(current), isTrue);
    });

    test('1.9.0 < 2.0.0', () {
      final current = AppVersion.parse('1.9.0');
      final latest = AppVersion.parse('2.0.0');
      expect(latest.isNewerThan(current), isTrue);
    });

    test('Numeric segment comparison handles 1.9.0 < 1.10.0 correctly', () {
      final current = AppVersion.parse('1.9.0');
      final latest = AppVersion.parse('1.10.0');
      expect(latest.isNewerThan(current), isTrue);
      expect(current.isNewerThan(latest), isFalse);
    });

    test('Handles build numbers such as 1.0.0+1 and 1.1.0+2', () {
      final current = AppVersion.parse('1.0.0+1');
      final latest = AppVersion.parse('1.1.0+2');
      expect(latest.isNewerThan(current), isTrue);

      final sameBase = AppVersion.parse('1.0.0+2');
      expect(sameBase.isNewerThan(current), isFalse);
    });

    test('Display version formats correctly', () {
      expect(AppVersion.parse('v1.0.0').displayVersion, equals('1.0.0'));
      expect(AppVersion.parse('1.2.3+4').displayVersion, equals('1.2.3'));
      expect(AppVersion.parse('v2.5').displayVersion, equals('2.5.0'));
    });
  });

  group('UpdateInfo & Asset Parsing Tests', () {
    test('Parses GitHub Release JSON with app-release.apk asset', () {
      final mockJson = {
        'tag_name': 'v1.1.0',
        'name': 'Hindvi App v1.1.0',
        'body': '* Improved PDF generation\n* Added App Update feature',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url':
                'https://github.com/Sp-4030/Mandal-Management-App/releases/download/v1.1.0/app-release.apk',
            'size': 76605456,
          }
        ]
      };

      final info = UpdateInfo.fromJson(mockJson);
      expect(info.tagName, equals('v1.1.0'));
      expect(info.versionName, equals('1.1.0'));
      expect(info.hasApk, isTrue);
      expect(info.apkFileName, equals('app-release.apk'));
      expect(info.apkDownloadUrl, contains('app-release.apk'));
      expect(info.apkSizeBytes, equals(76605456));
      expect(info.body, contains('Improved PDF generation'));
    });

    test('Correctly identifies missing APK asset without crashing', () {
      final mockJsonNoApk = {
        'tag_name': 'v1.1.0',
        'name': 'Hindvi App v1.1.0',
        'body': 'Notes without APK',
        'assets': <dynamic>[]
      };

      final info = UpdateInfo.fromJson(mockJsonNoApk);
      expect(info.hasApk, isFalse);
      expect(info.apkDownloadUrl, isNull);
    });
  });

  group('Update Check Scenarios with Mock Client', () {
    test('Scenario 1: Installed 1.0.0 vs Release v1.0.0 returns upToDate', () async {
      final releaseJson = jsonEncode({
        'tag_name': 'v1.0.0',
        'name': 'Hindvi App v1.0.0',
        'body': 'Initial release',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://github.com/.../app-release.apk',
            'size': 76605456,
          }
        ]
      });

      final mockClient = MockHttpClient(statusCode: 200, body: releaseJson);
      final service = UpdateService();
      final result = await service.checkForUpdate(
        currentVersionOverride: '1.0.0',
        httpClientOverride: mockClient,
      );

      expect(result.status, equals(UpdateCheckStatus.upToDate));
      expect(result.currentVersion, equals('1.0.0'));
      expect(result.latestVersion, equals('1.0.0'));
    });

    test('Scenario 2: Installed 1.0.0 vs Release v1.1.0 returns updateAvailable', () async {
      final releaseJson = jsonEncode({
        'tag_name': 'v1.1.0',
        'name': 'Hindvi App v1.1.0',
        'body': '* Improved PDF\n* Added App Update',
        'assets': [
          {
            'name': 'app-release.apk',
            'browser_download_url': 'https://github.com/.../app-release.apk',
            'size': 76605456,
          }
        ]
      });

      final mockClient = MockHttpClient(statusCode: 200, body: releaseJson);
      final service = UpdateService();
      final result = await service.checkForUpdate(
        currentVersionOverride: '1.0.0',
        httpClientOverride: mockClient,
      );

      expect(result.status, equals(UpdateCheckStatus.updateAvailable));
      expect(result.currentVersion, equals('1.0.0'));
      expect(result.latestVersion, equals('1.1.0'));
      expect(result.updateInfo?.hasApk, isTrue);
      expect(result.updateInfo?.body, contains('Improved PDF'));
    });

    test('Scenario 3: Newer version without APK asset returns noApkAvailable', () async {
      final releaseJson = jsonEncode({
        'tag_name': 'v1.1.0',
        'name': 'Hindvi App v1.1.0',
        'body': 'No asset release',
        'assets': <dynamic>[]
      });

      final mockClient = MockHttpClient(statusCode: 200, body: releaseJson);
      final service = UpdateService();
      final result = await service.checkForUpdate(
        currentVersionOverride: '1.0.0',
        httpClientOverride: mockClient,
      );

      expect(result.status, equals(UpdateCheckStatus.noApkAvailable));
      expect(result.errorMessage, equals('या आवृत्तीसाठी APK उपलब्ध नाही.'));
    });

    test('Scenario 4: GitHub API 404 returns release not found error', () async {
      final mockClient = MockHttpClient(statusCode: 404, body: 'Not Found');
      final service = UpdateService();
      final result = await service.checkForUpdate(
        currentVersionOverride: '1.0.0',
        httpClientOverride: mockClient,
      );

      expect(result.status, equals(UpdateCheckStatus.error));
      expect(result.errorMessage, equals('कोणतेही नवीन अपडेट सापडले नाही.'));
    });
  });

  group('Settings Screen Update Option & Navigation Tests', () {
    testWidgets('Settings screen renders App Update option', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('सेटिंग्ज'), findsOneWidget);
      expect(find.text('डेटा व्यवस्थापन'), findsOneWidget);
      expect(find.text('मंडळ डेटा ट्रान्सफर'), findsOneWidget);
      expect(find.text('बॅकअप'), findsOneWidget);
      expect(find.text('रिस्टोर'), findsOneWidget);
      expect(find.text('जुना / Recovery Data'), findsOneWidget);
      expect(find.text('App Update'), findsOneWidget);
    });

    testWidgets('Tapping App Update navigates to AppUpdateScreen', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: SettingsScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('App Update'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(AppUpdateScreen), findsOneWidget);
      expect(find.text('📱 App Update'), findsOneWidget);
      expect(find.text('Check for Updates'), findsOneWidget);
    });
  });

  group('Mandatory Blocking Update UI Tests', () {
    testWidgets('Mandatory update screen is blocking and displays required info', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const updateInfo = UpdateInfo(
        tagName: 'v1.1.0',
        versionName: '1.1.0',
        title: 'Hindvi Swarajya v1.1.0',
        body: '• नवीन वर्गणी शोध सुविधा\n• अनिवार्य अॅप अपडेट',
        apkDownloadUrl:
            'https://github.com/Sp-4030/Mandal-Management-App/releases/download/v1.1.0/app-release.apk',
        apkSizeBytes: 76605456,
        apkFileName: 'app-release.apk',
      );

      final checkResult = UpdateCheckResult.updateAvailable(
        currentVersion: '1.0.0',
        latestVersion: '1.1.0',
        updateInfo: updateInfo,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: AppUpdateScreen(
            isMandatory: true,
            initialCheckResult: checkResult,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title shows Hindvi Swarajya
      expect(find.text('हिंदवी स्वराज्य'), findsNWidgets(2));
      // Subtitle shows Update available
      expect(find.text('नवीन अपडेट उपलब्ध आहे'), findsNWidgets(2));
      // Current and New versions displayed
      expect(find.text('1.0.0'), findsAtLeastNWidgets(1));
      expect(find.text('1.1.0'), findsAtLeastNWidgets(1));
      // Release notes
      expect(find.textContaining('नवीन वर्गणी शोध सुविधा'), findsOneWidget);
      // Update Now button
      expect(find.text('Update Now'), findsOneWidget);

      // No back button in AppBar
      expect(find.byIcon(Icons.arrow_back), findsNothing);
      expect(find.byIcon(Icons.arrow_back_ios), findsNothing);

      // Check PopScope is blocking
      final popScopeFinder =
          find.byWidgetPredicate((w) => w is PopScope && !w.canPop);
      expect(popScopeFinder, findsOneWidget);

      // "Check for Update" manual button is NOT present in mandatory mode
      expect(find.text('Check for Update'), findsNothing);
    });
  });
}
