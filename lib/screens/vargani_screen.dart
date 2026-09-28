import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../utils/record_delete.dart';

class VarganiScreen extends StatefulWidget {
  const VarganiScreen({super.key});

  @override
  State<VarganiScreen> createState() => _VarganiScreenState();
}

class _VarganiScreenState extends State<VarganiScreen> {
  final DatabaseHelper db = DatabaseHelper.instance;

  final TextEditingController nameController = TextEditingController();

  final TextEditingController amountController = TextEditingController();

  final TextEditingController previousBalanceController =
      TextEditingController();

  List<Map<String, dynamic>> varganiList = [];

  double totalAmount = 0.0;

  double previousBalance = 0.0;

  int selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> loadData() async {
    final data = await db.getVargani(selectedYear);

    final total = await db.getVarganiTotal(selectedYear);

    final previous = await db.getPreviousBalance(selectedYear);

    if (!mounted) return;

    setState(() {
      varganiList = data;
      totalAmount = total;
      previousBalance = previous;

      previousBalanceController.text = previous == 0
          ? ''
          : previous.toStringAsFixed(0);
    });
  }

  // ============================================================
  // SAVE PREVIOUS BALANCE
  // ============================================================

  Future<void> savePreviousBalance() async {
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
  // ADD VARGANI
  // ============================================================

  Future<void> addVargani() async {
    final name = nameController.text.trim();

    final amountText = amountController.text.trim();

    if (name.isEmpty || amountText.isEmpty) {
      showMessage('कृपया नाव आणि रक्कम भरा');
      return;
    }

    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      showMessage('कृपया योग्य रक्कम टाका');
      return;
    }

    await db.insertVargani({
      'name': name,
      'amount': amount,
      'year': selectedYear,
    });

    nameController.clear();
    amountController.clear();

    if (!mounted) return;

    Navigator.pop(context);

    await loadData();
  }

  // ============================================================
  // DELETE VARGANI
  // ============================================================

  Future<void> deleteVargani(int id) async {
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
    nameController.text = item['name'].toString();

    amountController.text = item['amount'].toString();

    await showDialog(
      context: context,
      builder: (context) {
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
                Navigator.pop(context);
              },
              child: const Text('रद्द'),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();

                final amount = double.tryParse(amountController.text.trim());

                if (name.isEmpty || amount == null || amount <= 0) {
                  return;
                }

                await db.updateVargani(item['id'], {
                  'name': name,
                  'amount': amount,
                  'year': selectedYear,
                });

                nameController.clear();
                amountController.clear();

                if (!context.mounted) {
                  return;
                }

                Navigator.pop(context);

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
    nameController.clear();
    amountController.clear();

    showDialog(
      context: context,
      builder: (context) {
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
                Navigator.pop(context);
              },
              child: const Text('रद्द'),
            ),
            ElevatedButton(onPressed: addVargani, child: const Text('जमा करा')),
          ],
        );
      },
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    nameController.dispose();
    amountController.dispose();
    previousBalanceController.dispose();

    super.dispose();
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('वर्गणी'), centerTitle: true),

      floatingActionButton: FloatingActionButton(
        onPressed: showAddDialog,
        child: const Icon(Icons.add),
      ),

      body: Column(
        children: [
          // ======================================================
          // YEAR
          // ======================================================

          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text(
                  'वर्ष:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(width: 15),

                DropdownButton<int>(
                  value: selectedYear,
                  items: List.generate(6, (index) {
                    final year = DateTime.now().year - index;

                    return DropdownMenuItem<int>(
                      value: year,
                      child: Text(year.toString()),
                    );
                  }),
                  onChanged: (value) async {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      selectedYear = value;
                    });

                    await loadData();
                  },
                ),
              ],
            ),
          ),

          // ======================================================
          // PREVIOUS YEAR BALANCE
          // ======================================================
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'मागील वर्ष शिल्लक',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: previousBalanceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          prefixText: '₹ ',
                          hintText: 'उदा. 8951',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    ElevatedButton(
                      onPressed: savePreviousBalance,
                      child: const Text('जतन करा'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ======================================================
          // TOTAL
          // ======================================================
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.green.shade50,
              border: Border.all(color: Colors.green),
            ),
            child: Column(
              children: [
                const Text(
                  'एकूण वर्गणी',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 5),

                Text(
                  '₹ ${totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ======================================================
          // TABLE HEADER
          // ======================================================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            color: Colors.grey.shade200,
            child: const Row(
              children: [
                SizedBox(
                  width: 45,
                  child: Text(
                    'आ न',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                Expanded(
                  child: Text(
                    'नाव',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                SizedBox(
                  width: 100,
                  child: Text(
                    'जमा रक्कम',
                    style: TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.right,
                  ),
                ),

                SizedBox(width: 80),
              ],
            ),
          ),

          // ======================================================
          // DATA LIST
          // ======================================================
          Expanded(
            child: varganiList.isEmpty
                ? const Center(
                    child: Text(
                      'या वर्षासाठी कोणतीही नोंद उपलब्ध नाही.',
                      style: TextStyle(fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    itemCount: varganiList.length,
                    itemBuilder: (context, index) {
                      final item = varganiList[index];

                      return Dismissible(
                        key: ValueKey('vargani-${item['id']}'),
                        direction: DismissDirection.endToStart,
                        background: recordDeleteBackground(),
                        confirmDismiss: (_) => confirmRecordDelete(
                          context,
                          message: 'ही वर्गणीची नोंद हटवायची आहे का?',
                        ),
                        onDismissed: (_) {
                          deleteRecordAndRefresh(
                            context,
                            delete: () async {
                              await db.deleteVargani(item['id']);
                            },
                            refresh: loadData,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: 45, child: Text('${index + 1}')),

                              Expanded(child: Text(item['name'].toString())),

                              SizedBox(
                                width: 100,
                                child: Text(
                                  '₹ ${item['amount']}',
                                  textAlign: TextAlign.right,
                                ),
                              ),

                              SizedBox(
                                width: 80,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, size: 20),
                                      onPressed: () {
                                        editVargani(item);
                                      },
                                    ),

                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        size: 20,
                                        color: Colors.red,
                                      ),
                                      onPressed: () {
                                        deleteVargani(item['id']);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
