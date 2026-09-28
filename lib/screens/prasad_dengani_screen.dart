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

  Widget _summaryTotal(String title, double amount) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF0E1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF0D2B5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF8E410C),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: amount),
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) => Text(
                money(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF25231F),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    final icon = switch (title) {
      'प्रसाद देणगी' => Icons.volunteer_activism_outlined,
      'प्रसाद साहित्य' => Icons.inventory_2_outlined,
      _ => Icons.temple_hindu_outlined,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 9),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFB94D00), size: 23),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF35291F),
            ),
          ),
        ],
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
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.94, end: 1),
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 7 * (1 - value)),
                child: child,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFFFFF0E1),
                foregroundColor: const Color(0xFFB94D00),
                child: Text('${index + 1}'),
              ),
              title: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                detail,
                style: const TextStyle(color: Color(0xFF756A5D)),
              ),
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
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
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
            'एकूण: ${money(prasadDenganiTotal)}',
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
            'एकूण: ${money(aartiVarganiTotal)}',
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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            child,
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
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
        centerTitle: false,
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _summaryTotal('प्रसाद देणगी', prasadDenganiTotal),
                        const SizedBox(width: 10),
                        _summaryTotal('आरतीतील वर्गणी', aartiVarganiTotal),
                      ],
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
