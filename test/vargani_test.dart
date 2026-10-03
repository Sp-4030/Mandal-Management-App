import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Vargani Sorting & Name Normalization Unit Tests', () {
    test('Whitespace normalization collapses spaces and trims without altering Marathi letters', () {
      String normalize(String input) =>
          input.replaceAll(RegExp(r'\s+'), ' ').trim();

      expect(normalize('  विनायक   पाटील  '), equals('विनायक पाटील'));
      expect(normalize('योगेश    पाटील'), equals('योगेश पाटील'));
      expect(normalize('अमोल पाटील'), equals('अमोल पाटील'));
      expect(normalize('   सुरज   जाधव   '), equals('सुरज जाधव'));
    });

    test('Numeric sorting correctly orders high amounts to low amounts (not string sorting)', () {
      final records = [
        {'id': 1, 'name': 'सागर', 'amount': 500.0},
        {'id': 2, 'name': 'विनायक पाटील', 'amount': 2500.0},
        {'id': 3, 'name': 'योगेश पाटील', 'amount': 1600.0},
        {'id': 4, 'name': 'अमोल पाटील', 'amount': 1000.0},
        {'id': 5, 'name': 'सुरेश', 'amount': 1551.0},
        {'id': 6, 'name': 'महेश', 'amount': 1501.0},
        {'id': 7, 'name': 'गणेश', 'amount': 1500.0},
        {'id': 8, 'name': 'राहुल', 'amount': 200.0},
      ];

      records.sort((a, b) {
        final aAmount = (a['amount'] as num).toDouble();
        final bAmount = (b['amount'] as num).toDouble();
        final cmp = bAmount.compareTo(aAmount);
        if (cmp != 0) return cmp;
        final aId = (a['id'] as num).toInt();
        final bId = (b['id'] as num).toInt();
        return aId.compareTo(bId);
      });

      final amounts = records.map((r) => r['amount']).toList();
      // Must be strictly descending numerically
      expect(amounts, equals([2500.0, 1600.0, 1551.0, 1501.0, 1500.0, 1000.0, 500.0, 200.0]));
      // Note: in string sorting, '500' > '1000', but in numeric sorting 1000 > 500
      expect(records[records.indexWhere((r) => r['name'] == 'अमोल पाटील')]['amount'], equals(1000.0));
      expect(records[records.indexWhere((r) => r['name'] == 'सागर')]['amount'], equals(500.0));
    });

    test('Equal amounts preserve existing order based on ID', () {
      final records = [
        {'id': 1, 'name': 'संजय पाटील (१)', 'amount': 1500.0},
        {'id': 2, 'name': 'संजय पाटील (२)', 'amount': 1500.0},
        {'id': 3, 'name': 'अमित', 'amount': 2000.0},
      ];

      records.sort((a, b) {
        final aAmount = (a['amount'] as num).toDouble();
        final bAmount = (b['amount'] as num).toDouble();
        final cmp = bAmount.compareTo(aAmount);
        if (cmp != 0) return cmp;
        final aId = (a['id'] as num).toInt();
        final bId = (b['id'] as num).toInt();
        return aId.compareTo(bId);
      });

      expect(records[0]['name'], equals('अमित'));
      expect(records[1]['name'], equals('संजय पाटील (१)'));
      expect(records[2]['name'], equals('संजय पाटील (२)'));
    });

    test('Search filtering handles whitespace and preserves high-to-low amount sorting', () {
      final records = [
        {'id': 1, 'name': 'विनायक पाटील', 'amount': 2500.0},
        {'id': 2, 'name': 'योगेश पाटील', 'amount': 1600.0},
        {'id': 3, 'name': 'सुरज जाधव', 'amount': 1200.0},
        {'id': 4, 'name': 'अमोल   पाटील', 'amount': 1000.0},
      ];

      String normalize(String input) =>
          input.replaceAll(RegExp(r'\s+'), ' ').trim();

      List<Map<String, dynamic>> filter(String query) {
        final q = normalize(query).toLowerCase();
        if (q.isEmpty) return records;
        return records.where((r) {
          final name = normalize(r['name']?.toString() ?? '').toLowerCase();
          return name.contains(q);
        }).toList();
      }

      // Search 'पाटील' with extra spaces
      final resultPatil = filter('   पाटील   ');
      expect(resultPatil.length, equals(3));
      expect(resultPatil.map((r) => r['name']),
          containsAllInOrder(['विनायक पाटील', 'योगेश पाटील', 'अमोल   पाटील']));
      expect(resultPatil.map((r) => r['amount']), equals([2500.0, 1600.0, 1000.0]));

      // Search 'योगेश'
      final resultYogesh = filter('योगेश');
      expect(resultYogesh.length, equals(1));
      expect(resultYogesh.first['name'], equals('योगेश पाटील'));

      // Empty search returns all
      final resultEmpty = filter('   ');
      expect(resultEmpty.length, equals(4));
    });

    test('Same-name check logic correctly detects duplicate normalized name', () {
      final existingRecords = [
        {'id': 10, 'name': 'संजय पाटील', 'amount': 1500.0, 'year': 2025},
        {'id': 11, 'name': 'योगेश पाटील', 'amount': 1000.0, 'year': 2025},
      ];

      String normalize(String input) =>
          input.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

      bool hasDuplicate(String newName, {int? excludeId}) {
        final norm = normalize(newName);
        for (final row in existingRecords) {
          if (excludeId != null && row['id'] == excludeId) continue;
          if (normalize(row['name'].toString()) == norm) {
            return true;
          }
        }
        return false;
      }

      // Adding new record with same name (even with extra spaces)
      expect(hasDuplicate('  संजय    पाटील  '), isTrue);
      // Adding new record with different name
      expect(hasDuplicate('सुरेश पवार'), isFalse);

      // Editing record 10 and keeping name 'संजय पाटील' (excludeId = 10)
      expect(hasDuplicate('संजय पाटील', excludeId: 10), isFalse);

      // Editing record 10 and changing name to 'योगेश पाटील' (excludeId = 10)
      expect(hasDuplicate('योगेश पाटील', excludeId: 10), isTrue);
    });

    test('Input validation checks for Name and Amount', () {
      String? validateName(String input) {
        final trimmed = input.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (trimmed.isEmpty) return 'नाव आवश्यक आहे.';
        return null;
      }

      String? validateAmount(String input) {
        final trimmed = input.trim();
        if (trimmed.isEmpty) return 'रक्कम आवश्यक आहे.';
        final amount = double.tryParse(trimmed);
        if (amount == null) return 'कृपया योग्य रक्कम टाका.';
        if (amount <= 0) return 'रक्कम 0 पेक्षा जास्त असावी.';
        return null;
      }

      // Name tests
      expect(validateName(''), equals('नाव आवश्यक आहे.'));
      expect(validateName('   '), equals('नाव आवश्यक आहे.'));
      expect(validateName('विनायक पाटील'), isNull);

      // Amount tests
      expect(validateAmount(''), equals('रक्कम आवश्यक आहे.'));
      expect(validateAmount('   '), equals('रक्कम आवश्यक आहे.'));
      expect(validateAmount('abc'), equals('कृपया योग्य रक्कम टाका.'));
      expect(validateAmount('0'), equals('रक्कम 0 पेक्षा जास्त असावी.'));
      expect(validateAmount('-500'), equals('रक्कम 0 पेक्षा जास्त असावी.'));
      expect(validateAmount('1500'), isNull);
      expect(validateAmount('2500.50'), isNull);
    });
  });
}
