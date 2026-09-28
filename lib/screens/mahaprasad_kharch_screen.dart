import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/mahaprasad_kharch_model.dart';
import '../utils/record_delete.dart';

class MahaprasadKharchScreen extends StatefulWidget {
  const MahaprasadKharchScreen({super.key});

  @override
  State<MahaprasadKharchScreen> createState() => _MahaprasadKharchScreenState();
}

class _MahaprasadKharchScreenState extends State<MahaprasadKharchScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;

  List<MahaprasadKharch> _items = [];

  late int selectedYear;

  double total = 0.0;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    selectedYear = DateTime.now().year;

    _loadData();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
    });

    final data = await _db.getMahaprasadKharch(selectedYear);

    final totalAmount = await _db.getMahaprasadKharchTotal(selectedYear);

    if (!mounted) return;

    setState(() {
      _items = data.map((map) => MahaprasadKharch.fromMap(map)).toList();

      total = totalAmount;

      isLoading = false;
    });
  }

  // ============================================================
  // ADD / EDIT DIALOG
  // ============================================================

  Future<void> _showAddEditDialog({MahaprasadKharch? item}) async {
    final itemController = TextEditingController(text: item?.item ?? '');

    final buyerController = TextEditingController(text: item?.buyerName ?? '');

    final amountController = TextEditingController(
      text: item != null ? item.amount.toStringAsFixed(0) : '',
    );

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            item == null
                ? 'महाप्रसाद बाजार खर्च भरा'
                : 'महाप्रसाद बाजार खर्च बदला',
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ==========================================
                  // साहित्य
                  // ==========================================

                  TextFormField(
                    controller: itemController,
                    decoration: const InputDecoration(
                      labelText: 'साहित्य',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'साहित्य भरा';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 12),

                  // ==========================================
                  // खरेदीदाराचे नाव
                  // ==========================================
                  TextFormField(
                    controller: buyerController,
                    decoration: const InputDecoration(
                      labelText: 'वस्तू खरेदीदारचे नावे',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'नाव भरा';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 12),

                  // ==========================================
                  // खर्च
                  // ==========================================
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'खर्च',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'खर्चाची रक्कम भरा';
                      }

                      final amount = double.tryParse(value.trim());

                      if (amount == null) {
                        return 'योग्य रक्कम भरा';
                      }

                      if (amount < 0) {
                        return 'रक्कम चुकीची आहे';
                      }

                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            // ================================================
            // CANCEL
            // ================================================

            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('रद्द करा'),
            ),

            // ================================================
            // SAVE
            // ================================================
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }

                final amount = double.parse(amountController.text.trim());

                final data = MahaprasadKharch(
                  id: item?.id,
                  item: itemController.text.trim(),
                  buyerName: buyerController.text.trim(),
                  amount: amount,
                  year: selectedYear,
                );

                if (item == null) {
                  await _db.insertMahaprasadKharch(data.toMap());
                } else {
                  await _db.updateMahaprasadKharch(data.id!, data.toMap());
                }

                if (!context.mounted) return;

                Navigator.pop(context);

                await _loadData();
              },
              child: Text(item == null ? 'जतन करा' : 'बदल जतन करा'),
            ),
          ],
        );
      },
    );

    itemController.dispose();
    buyerController.dispose();
    amountController.dispose();
  }

  // ============================================================
  // DELETE
  // ============================================================

  // ============================================================
  // YEAR DROPDOWN
  // ============================================================

  Widget _buildYearDropdown() {
    final currentYear = DateTime.now().year;

    final years = List.generate(6, (index) => currentYear - index);

    return DropdownButton<int>(
      value: selectedYear,
      items: years.map((year) {
        return DropdownMenuItem<int>(value: year, child: Text('$year'));
      }).toList(),
      onChanged: (value) {
        if (value == null) return;

        setState(() {
          selectedYear = value;
        });

        _loadData();
      },
    );
  }

  // ============================================================
  // TABLE HEADER
  // ============================================================

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(border: Border.all()),
      child: const Row(
        children: [
          SizedBox(
            width: 45,
            child: Text('आ न', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'साहित्य',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              'वस्तू खरेदीदारचे नावे',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SizedBox(
            width: 75,
            child: Text(
              'खर्च',
              style: TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TABLE ROW
  // ============================================================

  Widget _buildRow(MahaprasadKharch item, int index) {
    return InkWell(
      onTap: () {
        _showAddEditDialog(item: item);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: const BoxDecoration(
          border: Border(
            left: BorderSide(),
            right: BorderSide(),
            bottom: BorderSide(),
          ),
        ),
        child: Row(
          children: [
            SizedBox(width: 45, child: Text('${index + 1}')),
            Expanded(flex: 3, child: Text(item.item)),
            Expanded(flex: 4, child: Text(item.buyerName)),
            SizedBox(
              width: 75,
              child: Text(
                '₹${item.amount.toStringAsFixed(0)}',
                textAlign: TextAlign.right,
              ),
            ),
            SizedBox(
              width: 42,
              child: IconButton(
                tooltip: 'बदला',
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _showAddEditDialog(item: item),
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
        title: Text('महाप्रसाद बाजार ($selectedYear)'),
        centerTitle: true,
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _showAddEditDialog();
        },
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ========================================
                    // YEAR
                    // ========================================

                    Row(
                      children: [
                        const Text(
                          'वर्ष : ',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        _buildYearDropdown(),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ========================================
                    // TOTAL
                    // ========================================
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'एकूण खर्च',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '₹${total.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 15),

                    // ========================================
                    // TABLE HEADER
                    // ========================================
                    _buildHeader(),

                    // ========================================
                    // DATA
                    // ========================================
                    if (_items.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(30),
                        decoration: const BoxDecoration(
                          border: Border(
                            left: BorderSide(),
                            right: BorderSide(),
                            bottom: BorderSide(),
                          ),
                        ),
                        child: const Text(
                          'या वर्षासाठी कोणताही खर्च उपलब्ध नाही.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      ..._items.asMap().entries.map((entry) {
                        return Dismissible(
                          key: ValueKey(entry.value.id),
                          direction: DismissDirection.endToStart,
                          background: recordDeleteBackground(),
                          confirmDismiss: (_) => confirmRecordDelete(
                            context,
                            message: 'ही नोंद हटवायची आहे का?',
                          ),
                          onDismissed: (_) {
                            deleteRecordAndRefresh(
                              context,
                              delete: () async {
                                await _db.deleteMahaprasadKharch(
                                  entry.value.id!,
                                );
                              },
                              refresh: _loadData,
                            );
                          },
                          child: _buildRow(entry.value, entry.key),
                        );
                      }),

                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }
}
