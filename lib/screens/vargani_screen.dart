import 'package:flutter/material.dart';

import '../database/database_helper.dart';
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
      appBar: AppBar(
        title: const Text('वर्गणी'),
        actions: [
          IconButton(
            tooltip: 'पुन्हा लोड करा',
            onPressed: loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('नवीन वर्गणी'),
      ),
      body: RefreshIndicator(
        onRefresh: loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 92),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, color: _saffron),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'वर्ष',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    DropdownButton<int>(
                      value: selectedYear,
                      underline: const SizedBox.shrink(),
                      items: List.generate(6, (index) {
                        final year = DateTime.now().year - index;
                        return DropdownMenuItem<int>(
                          value: year,
                          child: Text('$year'),
                        );
                      }),
                      onChanged: (value) async {
                        if (value == null) return;
                        setState(() => selectedYear = value);
                        await loadData();
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              prefixText: '₹ ',
                              hintText: 'उदा. 8951',
                              labelText: 'शिल्लक रक्कम',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: savePreviousBalance,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('जतन'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
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
            if (varganiList.isEmpty)
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
                child: const Column(
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 34,
                      color: _deepSaffron,
                    ),
                    SizedBox(height: 10),
                    Text(
                      'या वर्षासाठी कोणतीही नोंद उपलब्ध नाही.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...List.generate(varganiList.length, (index) {
                final item = varganiList[index];
                final amount = (item['amount'] as num).toDouble();
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
                            backgroundColor: const Color(0xFFFFF0E1),
                            foregroundColor: _deepSaffron,
                            child: Text('${index + 1}'),
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
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: _deepSaffron,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'बदला',
                            onPressed: () => editVargani(item),
                            icon: const Icon(Icons.edit_outlined),
                          ),
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
