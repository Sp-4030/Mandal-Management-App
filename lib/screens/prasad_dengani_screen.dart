import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../utils/record_delete.dart';

class PrasadDenganiScreen extends StatefulWidget {
  const PrasadDenganiScreen({super.key});

  @override
  State<PrasadDenganiScreen> createState() => _PrasadDenganiScreenState();
}

class _PrasadDenganiScreenState extends State<PrasadDenganiScreen> {
  final DatabaseHelper db = DatabaseHelper.instance;

  int selectedYear = DateTime.now().year;

  List<Map<String, dynamic>> prasadDengani = [];
  List<Map<String, dynamic>> prasadSahitya = [];
  List<Map<String, dynamic>> aartiVargani = [];

  double prasadDenganiTotal = 0;
  double aartiVarganiTotal = 0;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> loadData() async {
    setState(() {
      isLoading = true;
    });

    prasadDengani = await db.getPrasadDengani(selectedYear);
    prasadSahitya = await db.getPrasadSahitya(selectedYear);
    aartiVargani = await db.getAartiVargani(selectedYear);

    prasadDenganiTotal = await db.getPrasadDenganiTotal(selectedYear);

    aartiVarganiTotal = await db.getAartiVarganiTotal(selectedYear);

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
  // PRASAD DENGANI DIALOG
  // ============================================================

  Future<void> showPrasadDenganiDialog({
    int? id,
    String? oldName,
    double? oldAmount,
  }) async {
    final nameController = TextEditingController(text: oldName ?? '');

    final amountController = TextEditingController(
      text: oldAmount == null ? '' : oldAmount.toString(),
    );

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            id == null ? 'प्रसाद देणगी जमा करा' : 'प्रसाद देणगी बदला',
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'नाव',
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
                  'name': nameController.text.trim(),
                  'amount': double.parse(amountController.text.trim()),
                  'year': selectedYear,
                };

                if (id == null) {
                  await db.insertPrasadDengani(data);
                } else {
                  await db.updatePrasadDengani(id, data);
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
  // PRASAD SAHITYA DIALOG
  // ============================================================

  Future<void> showPrasadSahityaDialog({
    int? id,
    String? oldName,
    String? oldItem,
  }) async {
    final nameController = TextEditingController(text: oldName ?? '');

    final itemController = TextEditingController(text: oldItem ?? '');

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            id == null ? 'प्रसाद साहित्य जमा करा' : 'प्रसाद साहित्य बदला',
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'नाव',
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
                  controller: itemController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'देणारे साहित्य',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'साहित्य टाका';
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
                  'name': nameController.text.trim(),
                  'item': itemController.text.trim(),
                  'year': selectedYear,
                };

                if (id == null) {
                  await db.insertPrasadSahitya(data);
                } else {
                  await db.updatePrasadSahitya(id, data);
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
  // AARTI VARGANI DIALOG
  // ============================================================

  Future<void> showAartiVarganiDialog({
    int? id,
    String? oldName,
    double? oldAmount,
  }) async {
    final nameController = TextEditingController(text: oldName ?? '');

    final amountController = TextEditingController(
      text: oldAmount == null ? '' : oldAmount.toString(),
    );

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            id == null ? 'आरतीतिल वर्गणी जमा करा' : 'आरतीतिल वर्गणी बदला',
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'नाव',
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
                  'name': nameController.text.trim(),
                  'amount': double.parse(amountController.text.trim()),
                  'year': selectedYear,
                };

                if (id == null) {
                  await db.insertAartiVargani(data);
                } else {
                  await db.updateAartiVargani(id, data);
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
  // DELETE CONFIRMATION
  // ============================================================

  Future<bool> confirmDelete() {
    return confirmRecordDelete(context, message: 'ही नोंद हटवायची आहे का?');
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget sectionTitle(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ============================================================
  // PRASAD DENGANI TABLE
  // ============================================================

  Widget _buildSwipeRecord({
    required String key,
    required int index,
    required String name,
    required String detail,
    required VoidCallback onEdit,
    required Future<void> Function() onDelete,
  }) {
    return Dismissible(
      key: ValueKey(key),
      direction: DismissDirection.endToStart,
      background: recordDeleteBackground(),
      confirmDismiss: (_) => confirmDelete(),
      onDismissed: (_) {
        deleteRecordAndRefresh(context, delete: onDelete, refresh: loadData);
      },
      child: Column(
        children: [
          ListTile(
            leading: SizedBox(width: 24, child: Text('${index + 1}')),
            title: Text(name),
            subtitle: Text(detail),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'बदला',
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: 'हटवा',
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  onPressed: () async {
                    if (!await confirmDelete()) return;
                    if (!mounted) return;
                    await deleteRecordAndRefresh(
                      context,
                      delete: onDelete,
                      refresh: loadData,
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget buildPrasadDenganiTable() {
    return Column(
      children: [
        if (prasadDengani.isEmpty)
          const Padding(
            padding: EdgeInsets.all(15),
            child: Text('या वर्षासाठी कोणतीही नोंद उपलब्ध नाही.'),
          )
        else
          ...List.generate(prasadDengani.length, (index) {
            final row = prasadDengani[index];
            final amount = (row['amount'] as num).toDouble();
            return _buildSwipeRecord(
              key: 'prasad-dengani-${row['id']}',
              index: index,
              name: row['name']?.toString() ?? '',
              detail: money(amount),
              onEdit: () => showPrasadDenganiDialog(
                id: row['id'],
                oldName: row['name'],
                oldAmount: amount,
              ),
              onDelete: () async {
                await db.deletePrasadDengani(row['id']);
              },
            );
          }),
        const Divider(),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Total: ${money(prasadDenganiTotal)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PRASAD SAHITYA TABLE
  // ============================================================

  Widget buildPrasadSahityaTable() {
    return Column(
      children: [
        if (prasadSahitya.isEmpty)
          const Padding(
            padding: EdgeInsets.all(15),
            child: Text('या वर्षासाठी कोणतीही नोंद उपलब्ध नाही.'),
          )
        else
          ...List.generate(prasadSahitya.length, (index) {
            final row = prasadSahitya[index];
            return _buildSwipeRecord(
              key: 'prasad-sahitya-${row['id']}',
              index: index,
              name: row['name']?.toString() ?? '',
              detail: 'देणारे साहित्य: ${row['item'] ?? ''}',
              onEdit: () => showPrasadSahityaDialog(
                id: row['id'],
                oldName: row['name'],
                oldItem: row['item'],
              ),
              onDelete: () async {
                await db.deletePrasadSahitya(row['id']);
              },
            );
          }),
      ],
    );
  }

  // ============================================================
  // AARTI VARGANI TABLE
  // ============================================================

  Widget buildAartiVarganiTable() {
    return Column(
      children: [
        if (aartiVargani.isEmpty)
          const Padding(
            padding: EdgeInsets.all(15),
            child: Text('या वर्षासाठी कोणतीही नोंद उपलब्ध नाही.'),
          )
        else
          ...List.generate(aartiVargani.length, (index) {
            final row = aartiVargani[index];
            final amount = (row['amount'] as num).toDouble();
            return _buildSwipeRecord(
              key: 'aarti-vargani-${row['id']}',
              index: index,
              name: row['name']?.toString() ?? '',
              detail: money(amount),
              onEdit: () => showAartiVarganiDialog(
                id: row['id'],
                oldName: row['name'],
                oldAmount: amount,
              ),
              onDelete: () async {
                await db.deleteAartiVargani(row['id']);
              },
            );
          }),
        const Divider(),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'Total: ${money(aartiVarganiTotal)}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CARD
  // ============================================================

  Widget sectionCard({required Widget child, required VoidCallback onAdd}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            child,
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('नवीन नोंद'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('प्रसाद देणगी'),
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
                    // YEAR
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Text(
                              'वर्ष:',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 15),
                            DropdownButton<int>(
                              value: selectedYear,
                              items: List.generate(11, (index) {
                                final year = DateTime.now().year - 5 + index;

                                return DropdownMenuItem<int>(
                                  value: year,
                                  child: Text('$year'),
                                );
                              }),
                              onChanged: (value) async {
                                if (value == null) return;

                                setState(() {
                                  selectedYear = value;
                                });

                                await loadData();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ------------------------------------------------
                    // प्रसाद देणगी
                    // ------------------------------------------------
                    sectionTitle('प्रसाद देणगी'),

                    sectionCard(
                      child: buildPrasadDenganiTable(),
                      onAdd: () {
                        showPrasadDenganiDialog();
                      },
                    ),

                    // ------------------------------------------------
                    // प्रसाद साहित्य
                    // ------------------------------------------------
                    sectionTitle('प्रसाद साहित्य'),

                    sectionCard(
                      child: buildPrasadSahityaTable(),
                      onAdd: () {
                        showPrasadSahityaDialog();
                      },
                    ),

                    // ------------------------------------------------
                    // आरतीतिल वर्गणी
                    // ------------------------------------------------
                    sectionTitle('आरतीतिल वर्गणी'),

                    sectionCard(
                      child: buildAartiVarganiTable(),
                      onAdd: () {
                        showAartiVarganiDialog();
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
