import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/auth_service.dart';
import '../utils/record_delete.dart';

const Color _saffron = Color(0xFFFF7A00);
const Color _deepSaffron = Color(0xFFB94D00);
const Color _ink = Color(0xFF25231F);

class VarganiScreen extends StatefulWidget {
  const VarganiScreen({super.key});

  @override
  State<VarganiScreen> createState() => _VarganiScreenState();
}

class _VarganiScreenState extends State<VarganiScreen> {
  final DatabaseHelper db = DatabaseHelper.instance;
  final AuthService _authService = AuthService.instance;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController previousBalanceController =
      TextEditingController();
  final TextEditingController searchController = TextEditingController();

  List<Map<String, dynamic>> varganiList = [];
  String searchQuery = '';
  double totalAmount = 0.0;
  double previousBalance = 0.0;
  int selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    nameController.dispose();
    amountController.dispose();
    previousBalanceController.dispose();
    searchController.dispose();
    super.dispose();
  }

  // ============================================================
  // TEXT NORMALIZATION
  // ============================================================

  /// Normalizes whitespace: collapses multiple spaces/tabs into a single space
  /// and trims leading/trailing spaces without touching Marathi characters.
  String _normalizeText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ============================================================
  // LOAD DATA & SORTING
  // ============================================================

  Future<void> loadData() async {
    final data = await db.getVargani(selectedYear);
    final total = await db.getVarganiTotal(selectedYear);
    final previous = await db.getPreviousBalance(selectedYear);

    // Explicit numeric sorting: HIGH AMOUNT -> LOW AMOUNT.
    // When amounts are identical, preserve existing order by ID.
    final sorted = List<Map<String, dynamic>>.from(data);
    sorted.sort((a, b) {
      final aAmount = (a['amount'] as num?)?.toDouble() ?? 0.0;
      final bAmount = (b['amount'] as num?)?.toDouble() ?? 0.0;
      final cmp = bAmount.compareTo(aAmount);
      if (cmp != 0) return cmp;
      final aId = (a['id'] as num?)?.toInt() ?? 0;
      final bId = (b['id'] as num?)?.toInt() ?? 0;
      return aId.compareTo(bId);
    });

    if (!mounted) return;

    setState(() {
      varganiList = sorted;
      totalAmount = total;
      previousBalance = previous;
      previousBalanceController.text =
          previous == 0 ? '' : previous.toStringAsFixed(0);
    });
  }

  // ============================================================
  // SEARCH FILTERING
  // ============================================================

  /// Returns filtered list matching partial name search,
  /// preserving the descending numeric amount order.
  List<Map<String, dynamic>> get filteredVarganiList {
    final query = _normalizeText(searchQuery).toLowerCase();
    if (query.isEmpty) {
      return varganiList;
    }
    return varganiList.where((item) {
      final name =
          _normalizeText(item['name']?.toString() ?? '').toLowerCase();
      return name.contains(query);
    }).toList();
  }

  // ============================================================
  // SAVE PREVIOUS BALANCE
  // ============================================================

  Future<void> savePreviousBalance() async {
    if (!_authService.canEdit) {
      showMessage('माजी खजानी किंवा विना-परवानगी वापरकर्त्यास शिल्लक रक्कम बदलण्याची परवानगी नाही.');
      return;
    }

    final text = previousBalanceController.text.trim();

    if (text.isEmpty) {
      showMessage('कृपया मागील वर्षाची शिल्लक रक्कम भरा');
      return;
    }

    final amount = double.tryParse(text);

    if (amount == null || amount < 0) {
      showMessage('कृपया योग्य रक्कम टाका');
      return;
    }

    await db.savePreviousBalance(selectedYear, amount);

    if (!mounted) return;

    setState(() {
      previousBalance = amount;
    });

    showMessage('मागील वर्ष शिल्लक जतन झाली');
  }

  // ============================================================
  // SAME NAME CONFIRMATION DIALOG
  // ============================================================

  Future<bool> _showSameNameConfirmationDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: _deepSaffron),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'समान नाव आढळले',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'या वर्षात या नावावर आधीच नोंद आहे. तरीही ही नवीन नोंद जोडायची आहे का?\n\n'
            'होय दाबल्यास ही नवीन नोंद स्वतंत्रपणे जमा केली जाईल.',
            style: TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: _saffron,
                foregroundColor: Colors.white,
              ),
              child: const Text('होय, जोडा'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  // ============================================================
  // ADD VARGANI
  // ============================================================

  Future<void> addVargani(BuildContext dialogContext) async {
    if (!_authService.canAdd) {
      showMessage('माजी खजानी किंवा विना-परवानगी वापरकर्त्यास वर्गणी जोडण्याची परवानगी नाही.');
      return;
    }

    final name = _normalizeText(nameController.text);
    final amountText = amountController.text.trim();

    // Input Validation: Name
    if (name.isEmpty) {
      showMessage('नाव आवश्यक आहे.');
      return;
    }

    // Input Validation: Amount
    if (amountText.isEmpty) {
      showMessage('रक्कम आवश्यक आहे.');
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null) {
      showMessage('कृपया योग्य रक्कम टाका.');
      return;
    }

    if (amount <= 0) {
      showMessage('रक्कम 0 पेक्षा जास्त असावी.');
      return;
    }

    // Same-name check in currently selected year
    final hasSameName = await db.hasVarganiWithSameName(selectedYear, name);
    if (hasSameName) {
      if (!dialogContext.mounted) return;
      final confirmed =
          await _showSameNameConfirmationDialog(dialogContext);
      if (!confirmed) {
        return;
      }
    }

    await db.insertVargani({
      'name': name,
      'amount': amount,
      'year': selectedYear,
    });

    nameController.clear();
    amountController.clear();

    if (!dialogContext.mounted) return;
    Navigator.pop(dialogContext);

    await loadData();
  }

  // ============================================================
  // DELETE VARGANI
  // ============================================================

  Future<void> deleteVargani(int id) async {
    if (!_authService.canDelete) {
      showMessage('माजी खजानी किंवा विना-परवानगी वापरकर्त्यास वर्गणी हटवण्याची परवानगी नाही.');
      return;
    }

    final confirmed = await confirmRecordDelete(
      context,
      message: 'ही वर्गणीची नोंद हटवायची आहे का?',
    );
    if (!confirmed) return;
    if (!mounted) return;

    await deleteRecordAndRefresh(
      context,
      delete: () async {
        await db.deleteVargani(id);
      },
      refresh: loadData,
    );
  }

  // ============================================================
  // EDIT VARGANI
  // ============================================================

  Future<void> editVargani(Map<String, dynamic> item) async {
    if (!_authService.canEdit) {
      showMessage('माजी खजानी किंवा विना-परवानगी वापरकर्त्यास वर्गणी बदलण्याची परवानगी नाही.');
      return;
    }

    nameController.text = item['name'].toString();
    amountController.text = item['amount'].toString();
    final int itemId = item['id'];

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('वर्गणी बदला'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'नाव',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'जमा रक्कम',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('रद्द'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = _normalizeText(nameController.text);
                final amountText = amountController.text.trim();

                // Input Validation: Name
                if (name.isEmpty) {
                  showMessage('नाव आवश्यक आहे.');
                  return;
                }

                // Input Validation: Amount
                if (amountText.isEmpty) {
                  showMessage('रक्कम आवश्यक आहे.');
                  return;
                }

                final amount = double.tryParse(amountText);
                if (amount == null) {
                  showMessage('कृपया योग्य रक्कम टाका.');
                  return;
                }

                if (amount <= 0) {
                  showMessage('रक्कम 0 पेक्षा जास्त असावी.');
                  return;
                }

                // Same-name check: exclude current record ID
                final hasSameName = await db.hasVarganiWithSameName(
                  selectedYear,
                  name,
                  excludeId: itemId,
                );

                if (hasSameName) {
                  if (!dialogContext.mounted) return;
                  final confirmed =
                      await _showSameNameConfirmationDialog(dialogContext);
                  if (!confirmed) {
                    return;
                  }
                }

                await db.updateVargani(itemId, {
                  'name': name,
                  'amount': amount,
                  'year': selectedYear,
                });

                nameController.clear();
                amountController.clear();

                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);

                await loadData();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // ADD DIALOG
  // ============================================================

  void showAddDialog() {
    if (!_authService.canAdd) {
      showMessage('माजी खजानी किंवा विना-परवानगी वापरकर्त्यास वर्गणी जोडण्याची परवानगी नाही.');
      return;
    }

    nameController.clear();
    amountController.clear();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('वर्गणी जमा करा'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'नाव',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'जमा रक्कम',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('रद्द'),
            ),
            ElevatedButton(
              onPressed: () => addVargani(dialogContext),
              child: const Text('जमा करा'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SNACKBAR MESSAGE
  // ============================================================

  void showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  // ============================================================
  // UI BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final displayedList = filteredVarganiList;
    final canModify = _authService.canModify;
    final canAdd = _authService.canAdd;
    final canEdit = _authService.canEdit;
    final canDelete = _authService.canDelete;
    final canSearch = _authService.canSearch;
    final isOldKhajani = _authService.isOldKhajani;

    return Scaffold(
      appBar: AppBar(
        title: const Text('वर्गणी व्यवस्थापन'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: loadData,
          ),
        ],
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: showAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('नवीन वर्गणी'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
          children: [
            // Read-Only Warning Banner for OLD_KHAJANI
            if (isOldKhajani && !canModify) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFB74D)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.visibility_outlined,
                        color: _deepSaffron, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'माजी खजानी (केवळ वाचन मोड) - नवीन वर्गणी नोंदवणे, बदलणे किंवा हटवणे बंद आहे.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 1. Year Selector Card
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, color: _deepSaffron),
                    const SizedBox(width: 12),
                    const Text(
                      'वर्ष निवडा: ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    DropdownButton<int>(
                      value: selectedYear,
                      underline: const SizedBox(),
                      borderRadius: BorderRadius.circular(14),
                      items: List.generate(10, (index) {
                        final year = DateTime.now().year - index + 1;
                        return DropdownMenuItem(
                          value: year,
                          child: Text(
                            '$year',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        );
                      }),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          selectedYear = value;
                          searchQuery = '';
                          searchController.clear();
                        });
                        loadData();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 2. Real-time Search Box
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: TextField(
                  controller: searchController,
                  enabled: canSearch,
                  decoration: InputDecoration(
                    hintText: canSearch
                        ? 'नावानुसार वर्गणीदार शोधा...'
                        : 'शोधण्याची परवानगी नाही',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    icon: const Icon(Icons.search, color: _deepSaffron),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              searchController.clear();
                              setState(() {
                                searchQuery = '';
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 3. Previous Year Balance Section
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'मागील वर्ष शिल्लक',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: previousBalanceController,
                            enabled: canEdit,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              prefixText: '₹ ',
                              hintText: 'उदा. 8951',
                              labelText: 'शिल्लक रक्कम',
                              fillColor:
                                  canEdit ? null : const Color(0xFFF9F6F0),
                            ),
                          ),
                        ),
                        if (canEdit) ...[
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: savePreviousBalance,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('जतन'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 4. Total Card (एकूण वर्गणी)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF0E1), Color(0xFFFFE1C2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF0D2B5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'एकूण वर्गणी',
                    style: TextStyle(
                      color: _deepSaffron,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: totalAmount),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    builder: (context, amount, child) => Text(
                      '₹ ${amount.toStringAsFixed(0)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 5. Table Header Row (Marathi Headings: आ न | नाव | जमा रक्कम)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD8B3)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 36,
                    child: Text(
                      'आ न',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _deepSaffron,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'नाव',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _deepSaffron,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const Text(
                    'जमा रक्कम',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _deepSaffron,
                      fontSize: 13,
                    ),
                  ),
                  if (canEdit || canDelete)
                    const SizedBox(width: 90)
                  else
                    const SizedBox(width: 8),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // 6. Vargani Records List
            if (displayedList.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 36,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFF0E6D9)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.receipt_long_outlined,
                      size: 34,
                      color: _deepSaffron,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      searchQuery.isNotEmpty
                          ? 'शोधलेल्या नावाची कोणतीही नोंद सापडली नाही.'
                          : 'या वर्षासाठी कोणतीही नोंद उपलब्ध नाही.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF756A5D)),
                    ),
                  ],
                ),
              )
            else
              ...List.generate(displayedList.length, (index) {
                final item = displayedList[index];
                final amount = (item['amount'] as num).toDouble();
                final originalIndex = varganiList.indexOf(item);
                final serialNumber =
                    (originalIndex >= 0 ? originalIndex : index) + 1;

                return Dismissible(
                  key: ValueKey('vargani-${item['id']}'),
                  direction: canDelete
                      ? DismissDirection.endToStart
                      : DismissDirection.none,
                  background: recordDeleteBackground(),
                  confirmDismiss: (_) => confirmRecordDelete(
                    context,
                    message: 'ही वर्गणीची नोंद हटवायची आहे का?',
                  ),
                  onDismissed: (_) {
                    deleteRecordAndRefresh(
                      context,
                      delete: () async => db.deleteVargani(item['id']),
                      refresh: loadData,
                    );
                  },
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 9),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 17,
                            backgroundColor: const Color(0xFFFFF0E1),
                            foregroundColor: _deepSaffron,
                            child: Text(
                              '$serialNumber',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name'].toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '₹ ${amount.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: _deepSaffron,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (canEdit)
                            IconButton(
                              tooltip: 'बदला',
                              onPressed: () => editVargani(item),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          if (canDelete)
                            IconButton(
                              tooltip: 'हटवा',
                              onPressed: () => deleteVargani(item['id']),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
