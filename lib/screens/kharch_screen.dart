import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/auth_service.dart';
import '../utils/record_delete.dart';

class KharchScreen extends StatefulWidget {
  final bool initialLoading;
  const KharchScreen({super.key, this.initialLoading = true});

  @override
  State<KharchScreen> createState() => _KharchScreenState();
}

class _KharchScreenState extends State<KharchScreen> {
  final DatabaseHelper db = DatabaseHelper.instance;
  final AuthService _authService = AuthService.instance;

  late int previousYear;

  List<Map<String, dynamic>> kharchList = [];
  double total = 0;

  late bool isLoading;

  @override
  void initState() {
    super.initState();

    previousYear = DateTime.now().year;
    isLoading = widget.initialLoading;
    if (widget.initialLoading) {
      loadData();
    }
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> loadData() async {
    setState(() {
      isLoading = true;
    });

    try {
      kharchList = await db.getKharch(previousYear);
      total = await db.getKharchTotal(previousYear);
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });
  }

  // ============================================================
  // MONEY FORMAT
  // ============================================================

  String money(double amount) {
    if (amount == amount.roundToDouble()) {
      return '₹${amount.toInt()}';
    }

    return '₹${amount.toStringAsFixed(2)}';
  }

  // ============================================================
  // DIALOG
  // ============================================================

  Future<void> showKharchDialog({
    int? id,
    String? oldItem,
    String? oldBuyerName,
    double? oldAmount,
  }) async {
    if (id == null && !_authService.canAdd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'माजी खजानी किंवा विना-परवानगी वापरकर्त्यास खर्च जोडण्याची परवानगी नाही.',
          ),
        ),
      );
      return;
    }
    if (id != null && !_authService.canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'माजी खजानी किंवा विना-परवानगी वापरकर्त्यास खर्च बदलण्याची परवानगी नाही.',
          ),
        ),
      );
      return;
    }

    final itemController = TextEditingController(text: oldItem ?? '');

    final buyerNameController =
        TextEditingController(text: oldBuyerName ?? '');

    final amountController = TextEditingController(
      text: oldAmount == null ? '' : oldAmount.toString(),
    );

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(id == null ? 'खर्च जोडा' : 'खर्च बदला'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: itemController,
                  decoration: const InputDecoration(
                    labelText: 'खर्च वस्तू',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'वस्तू टाका';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: buyerNameController,
                  decoration: const InputDecoration(
                    labelText: 'खरेदीदाराचे नाव',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'नाव टाका';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'रक्कम',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'रक्कम टाका';
                    }

                    final amount = double.tryParse(value.trim());

                    if (amount == null || amount < 0) {
                      return 'योग्य रक्कम टाका';
                    }

                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }

                final data = {
                  'item': itemController.text.trim(),
                  'buyer_name': buyerNameController.text.trim(),
                  'amount': double.parse(amountController.text.trim()),
                  'year': previousYear,
                };

                if (id == null) {
                  await db.insertKharch(data);
                } else {
                  await db.updateKharch(id, data);
                }

                if (!context.mounted) return;

                Navigator.pop(context);

                await loadData();
              },
              child: const Text('जतन करा'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // DELETE
  // ============================================================

  Future<bool> confirmDelete() async {
    return confirmRecordDelete(context, message: 'ही नोंद हटवायची आहे का?');
  }

  // ============================================================
  // TABLE
  // ============================================================

  Widget buildTable() {
    final canEdit = _authService.canEdit;
    final canDelete = _authService.canDelete;

    if (kharchList.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text(
            'या वर्षासाठी कोणतीही नोंद उपलब्ध नाही.',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Column(
      children: List.generate(kharchList.length, (index) {
        final row = kharchList[index];
        final amount = (row['amount'] as num).toDouble();
        return Dismissible(
          key: ValueKey('kharch-${row['id']}'),
          direction:
              canDelete ? DismissDirection.endToStart : DismissDirection.none,
          background: recordDeleteBackground(),
          confirmDismiss: (_) => confirmDelete(),
          onDismissed: (_) {
            deleteRecordAndRefresh(
              context,
              delete: () async {
                await db.deleteKharch(row['id']);
              },
              refresh: loadData,
            );
          },
          child: Column(
            children: [
              ListTile(
                leading: SizedBox(width: 24, child: Text('${index + 1}')),
                title: Text(row['item']?.toString() ?? ''),
                subtitle: Text(row['buyer_name']?.toString() ?? ''),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(money(amount)),
                    if (canEdit)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'बदला',
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () => showKharchDialog(
                              id: row['id'],
                              oldItem: row['item'],
                              oldBuyerName: row['buyer_name'],
                              oldAmount: amount,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const Divider(),
            ],
          ),
        );
      }),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final canAdd = _authService.canAdd;
    final canModify = _authService.canModify;
    final isOldKhajani = _authService.isOldKhajani;

    return Scaffold(
      appBar: AppBar(
        title: Text('मागील वर्षाचा खर्च ($previousYear)'),
        actions: [
          IconButton(onPressed: loadData, icon: const Icon(Icons.refresh)),
        ],
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Read-only notice for OLD_KHAJANI
                    if (isOldKhajani && !canModify) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFB74D)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.visibility_outlined,
                                color: Color(0xFFB94D00), size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'माजी खजानी (केवळ वाचन मोड) - नवीन खर्च नोंदवणे, बदलणे किंवा हटवणे बंद आहे.',
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

                    // ==================================================
                    // YEAR SELECTOR
                    // ==================================================
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Text(
                              'वर्ष निवडा:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            DropdownButton<int>(
                              value: previousYear,
                              items: List.generate(10, (index) {
                                final y = DateTime.now().year - index;
                                return DropdownMenuItem(
                                  value: y,
                                  child: Text('$y'),
                                );
                              }),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    previousYear = val;
                                  });
                                  loadData();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ==================================================
                    // EXPENSE LIST CARD
                    // ==================================================
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            ListTile(
                              title: const Text(
                                'खर्च तपशील',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              trailing: Text(
                                'एकूण: ${money(total)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red,
                                ),
                              ),
                            ),

                            const Divider(),
                            buildTable(),
                            const SizedBox(height: 5),

                            // ==================================================
                            // ADD BUTTON
                            // ==================================================
                            if (canAdd)
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.icon(
                                  onPressed: () {
                                    showKharchDialog();
                                  },
                                  icon: const Icon(Icons.add),
                                  label: const Text('नवीन नोंद'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
