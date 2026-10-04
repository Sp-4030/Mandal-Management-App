import 'dart:async';
import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../services/auth_service.dart';
import '../services/remote_sync_service.dart';
import '../utils/record_delete.dart';

class PrasadDenganiScreen extends StatefulWidget {
  final bool initialLoading;
  const PrasadDenganiScreen({super.key, this.initialLoading = true});

  @override
  State<PrasadDenganiScreen> createState() => _PrasadDenganiScreenState();
}

class _PrasadDenganiScreenState extends State<PrasadDenganiScreen> {
  final DatabaseHelper db = DatabaseHelper.instance;
  final AuthService _authService = AuthService.instance;

  int selectedYear = DateTime.now().year;

  List<Map<String, dynamic>> prasadDengani = [];
  List<Map<String, dynamic>> prasadSahitya = [];
  List<Map<String, dynamic>> aartiVargani = [];

  double prasadDenganiTotal = 0;
  double aartiVarganiTotal = 0;

  late bool isLoading;
  StreamSubscription? _syncSub;

  @override
  void initState() {
    super.initState();
    isLoading = widget.initialLoading;
    if (widget.initialLoading) {
      loadData();
    }
    _syncSub = RemoteSyncService.instance.onFinancialChange.listen((change) {
      final table = change['tableName'] as String?;
      if (table == 'prasad_dengani' || table == 'prasad_sahitya' || table == 'aarti_vargani' || table == null) {
        if (mounted) {
          debugPrint(
              '[UI_REFRESHED] table=$table recordId=${change['recordId']} operation=${change['operation']}');
          loadData();
        }
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> loadData() async {
    setState(() {
      isLoading = true;
    });

    try {
      prasadDengani = await db.getPrasadDengani(selectedYear);
      prasadSahitya = await db.getPrasadSahitya(selectedYear);
      aartiVargani = await db.getAartiVargani(selectedYear);

      prasadDenganiTotal = await db.getPrasadDenganiTotal(selectedYear);
      aartiVarganiTotal = await db.getAartiVarganiTotal(selectedYear);
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
    if (id == null && !_authService.canAdd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'माजी खजानी किंवा विना-परवानगी वापरकर्त्यास देणगी जोडण्याची परवानगी नाही.',
          ),
        ),
      );
      return;
    }
    if (id != null && !_authService.canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'माजी खजानी किंवा विना-परवानगी वापरकर्त्यास देणगी बदलण्याची परवानगी नाही.',
          ),
        ),
      );
      return;
    }

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
                    labelText: 'जमा रक्कम',
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
    if (id == null && !_authService.canAdd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'माजी खजानी किंवा विना-परवानगी वापरकर्त्यास साहित्य जोडण्याची परवानगी नाही.',
          ),
        ),
      );
      return;
    }
    if (id != null && !_authService.canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'माजी खजानी किंवा विना-परवानगी वापरकर्त्यास साहित्य बदलण्याची परवानगी नाही.',
          ),
        ),
      );
      return;
    }

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
    if (id == null && !_authService.canAdd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'माजी खजानी किंवा विना-परवानगी वापरकर्त्यास वर्गणी जोडण्याची परवानगी नाही.',
          ),
        ),
      );
      return;
    }
    if (id != null && !_authService.canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'माजी खजानी किंवा विना-परवानगी वापरकर्त्यास वर्गणी बदलण्याची परवानगी नाही.',
          ),
        ),
      );
      return;
    }

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
                    labelText: 'जमा रक्कम',
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
  // DELETE
  // ============================================================

  Future<bool> confirmDelete() async {
    return confirmRecordDelete(context, message: 'ही नोंद हटवायची आहे का?');
  }

  // ============================================================
  // SECTION TITLE
  // ============================================================

  Widget sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFB94D00)),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RECORD ROW
  // ============================================================

  Widget _buildSwipeRecord({
    required String key,
    required int index,
    required String name,
    required String detail,
    required VoidCallback onEdit,
    required Future<void> Function() onDelete,
  }) {
    final canEdit = _authService.canEdit;
    final canDelete = _authService.canDelete;

    return Dismissible(
      key: ValueKey(key),
      direction:
          canDelete ? DismissDirection.endToStart : DismissDirection.none,
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
              trailing: (canEdit || canDelete)
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canEdit)
                          IconButton(
                            tooltip: 'बदला',
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: onEdit,
                          ),
                        if (canDelete)
                          IconButton(
                            tooltip: 'हटवा',
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
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
                    )
                  : null,
            ),
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget buildPrasadDenganiTable() {
    if (prasadDengani.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: Text(
            'कोणतीही देणगी नोंद उपलब्ध नाही.',
            style: TextStyle(color: Color(0xFF756A5D)),
          ),
        ),
      );
    }

    return Column(
      children: List.generate(prasadDengani.length, (index) {
        final row = prasadDengani[index];
        final amount = (row['amount'] as num).toDouble();
        return _buildSwipeRecord(
          key: 'dengani-${row['id']}',
          index: index,
          name: row['name'].toString(),
          detail: money(amount),
          onEdit: () => showPrasadDenganiDialog(
            id: row['id'],
            oldName: row['name'],
            oldAmount: amount,
          ),
          onDelete: () async => db.deletePrasadDengani(row['id']),
        );
      }),
    );
  }

  Widget buildPrasadSahityaTable() {
    if (prasadSahitya.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: Text(
            'कोणतीही साहित्य नोंद उपलब्ध नाही.',
            style: TextStyle(color: Color(0xFF756A5D)),
          ),
        ),
      );
    }

    return Column(
      children: List.generate(prasadSahitya.length, (index) {
        final row = prasadSahitya[index];
        return _buildSwipeRecord(
          key: 'sahitya-${row['id']}',
          index: index,
          name: row['name'].toString(),
          detail: row['item'].toString(),
          onEdit: () => showPrasadSahityaDialog(
            id: row['id'],
            oldName: row['name'],
            oldItem: row['item'],
          ),
          onDelete: () async => db.deletePrasadSahitya(row['id']),
        );
      }),
    );
  }

  Widget buildAartiVarganiTable() {
    if (aartiVargani.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Center(
          child: Text(
            'कोणतीही आरती वर्गणी नोंद उपलब्ध नाही.',
            style: TextStyle(color: Color(0xFF756A5D)),
          ),
        ),
      );
    }

    return Column(
      children: List.generate(aartiVargani.length, (index) {
        final row = aartiVargani[index];
        final amount = (row['amount'] as num).toDouble();
        return _buildSwipeRecord(
          key: 'aarti-${row['id']}',
          index: index,
          name: row['name'].toString(),
          detail: money(amount),
          onEdit: () => showAartiVarganiDialog(
            id: row['id'],
            oldName: row['name'],
            oldAmount: amount,
          ),
          onDelete: () async => db.deleteAartiVargani(row['id']),
        );
      }),
    );
  }

  Widget sectionCard({required Widget child, required VoidCallback onAdd}) {
    final canAdd = _authService.canAdd;

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            child,
            if (canAdd) ...[
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
    final isOldKhajani = _authService.isOldKhajani;
    final canModify = _authService.canModify;

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
                                'माजी खजानी (केवळ वाचन मोड) - नवीन देणगी नोंदवणे, बदलणे किंवा हटवणे बंद आहे.',
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
                              value: selectedYear,
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
                                    selectedYear = val;
                                  });
                                  loadData();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    Row(
                      children: [
                        _summaryTotal('प्रसाद देणगी एकूण', prasadDenganiTotal),
                        const SizedBox(width: 10),
                        _summaryTotal('आरती वर्गणी एकूण', aartiVarganiTotal),
                      ],
                    ),

                    const SizedBox(height: 16),

                    sectionTitle('प्रसाद देणगी', Icons.volunteer_activism),
                    sectionCard(
                      child: buildPrasadDenganiTable(),
                      onAdd: () => showPrasadDenganiDialog(),
                    ),

                    sectionTitle('प्रसाद साहित्य', Icons.inventory_2),
                    sectionCard(
                      child: buildPrasadSahityaTable(),
                      onAdd: () => showPrasadSahityaDialog(),
                    ),

                    sectionTitle('आरतीतील वर्गणी', Icons.currency_rupee),
                    sectionCard(
                      child: buildAartiVarganiTable(),
                      onAdd: () => showAartiVarganiDialog(),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
