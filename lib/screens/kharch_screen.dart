import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../utils/record_delete.dart';

class KharchScreen extends StatefulWidget {
  const KharchScreen({super.key});

  @override
  State<KharchScreen> createState() => _KharchScreenState();
}

class _KharchScreenState extends State<KharchScreen> {
  final DatabaseHelper db = DatabaseHelper.instance;

  late int previousYear;

  List<Map<String, dynamic>> kharchList = [];
  double total = 0;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    previousYear = DateTime.now().year;

    loadData();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> loadData() async {
    setState(() {
      isLoading = true;
    });

    kharchList = await db.getKharch(previousYear);
    total = await db.getKharchTotal(previousYear);

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
  // ADD / EDIT DIALOG
  // ============================================================

  Future<void> showKharchDialog({
    int? id,
    String? oldItem,
    String? oldBuyerName,
    double? oldAmount,
  }) async {
    final itemController = TextEditingController(text: oldItem ?? '');

    final buyerNameController = TextEditingController(text: oldBuyerName ?? '');

    final amountController = TextEditingController(
      text: oldAmount == null ? '' : oldAmount.toString(),
    );

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(id == null ? 'मागील वर्षाचा खर्च जमा करा' : 'खर्च बदला'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // साहित्य / वस्तू
                  TextFormField(
                    controller: itemController,
                    decoration: const InputDecoration(
                      labelText: 'साहित्य/वस्तू',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'साहित्य/वस्तू टाका';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 15),

                  // ठरविणारा व आणाऱ्यांचे नावे
                  TextFormField(
                    controller: buyerNameController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ठरविणारा व आणाऱ्यांचे नावे',
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

                  // खर्च रक्कम
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'खर्च रक्कम',
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
          direction: DismissDirection.endToStart,
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
                        IconButton(
                          tooltip: 'हटवा',
                          icon: const Icon(
                            Icons.delete,
                            size: 20,
                            color: Colors.red,
                          ),
                          onPressed: () async {
                            if (!await confirmDelete()) return;
                            if (!mounted) return;
                            await deleteRecordAndRefresh(
                              context,
                              delete: () async {
                                await db.deleteKharch(row['id']);
                              },
                              refresh: loadData,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
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
                    // ==================================================
                    // YEAR CARD
                    // ==================================================

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'वर्ष',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DropdownButton<int>(
                              value: previousYear,
                              underline: const SizedBox.shrink(),
                              items: List.generate(6, (index) {
                                final year = DateTime.now().year - index;
                                return DropdownMenuItem<int>(
                                  value: year,
                                  child: Text('$year'),
                                );
                              }),
                              onChanged: (year) async {
                                if (year == null) return;
                                setState(() => previousYear = year);
                                await loadData();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    // ==================================================
                    // TITLE
                    // ==================================================
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0E1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF0D2B5)),
                      ),
                      child: Text(
                        'मागील वर्षाचा खर्च',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // ==================================================
                    // TABLE
                    // ==================================================
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: total),
                                  duration: const Duration(milliseconds: 420),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, amount, child) => Text(
                                    'एकूण खर्च: ${money(amount)}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFB94D00),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const Divider(),
                            buildTable(),
                            const SizedBox(height: 5),

                            // ==================================================
                            // ADD BUTTON
                            // ==================================================
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
