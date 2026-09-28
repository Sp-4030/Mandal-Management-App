import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/mahaprasad_kharch_model.dart';
import '../utils/record_delete.dart';

class MahaprasadKharchScreen extends StatefulWidget {
  const MahaprasadKharchScreen({super.key});

  @override
  State<MahaprasadKharchScreen> createState() =>
      _MahaprasadKharchScreenState();
}

class _MahaprasadKharchScreenState
    extends State<MahaprasadKharchScreen> {
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

    final data =
        await _db.getMahaprasadKharch(selectedYear);

    final totalAmount =
        await _db.getMahaprasadKharchTotal(
      selectedYear,
    );

    if (!mounted) return;

    setState(() {
      _items = data
          .map(
            (map) => MahaprasadKharch.fromMap(map),
          )
          .toList();

      total = totalAmount;

      isLoading = false;
    });
  }

  // ============================================================
  // ADD / EDIT DIALOG
  // ============================================================

  Future<void> _showAddEditDialog({
    MahaprasadKharch? item,
  }) async {
    final itemController = TextEditingController(
      text: item?.item ?? '',
    );

    final buyerController = TextEditingController(
      text: item?.buyerName ?? '',
    );

    final amountController = TextEditingController(
      text: item != null
          ? item.amount.toStringAsFixed(0)
          : '',
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
                  // ==================================================
                  // साहित्य
                  // ==================================================

                  TextFormField(
                    controller: itemController,
                    decoration: const InputDecoration(
                      labelText: 'साहित्य',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return 'साहित्य भरा';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 12),

                  // ==================================================
                  // खरेदीदाराचे नाव
                  // ==================================================

                  TextFormField(
                    controller: buyerController,
                    decoration: const InputDecoration(
                      labelText: 'वस्तू खरेदीदारचे नावे',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return 'नाव भरा';
                      }

                      return null;
                    },
                  ),

                  const SizedBox(height: 12),

                  // ==================================================
                  // खर्च
                  // ==================================================

                  TextFormField(
                    controller: amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'खर्च',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null ||
                          value.trim().isEmpty) {
                        return 'खर्चाची रक्कम भरा';
                      }

                      final amount =
                          double.tryParse(
                        value.trim(),
                      );

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
            // ======================================================
            // CANCEL
            // ======================================================

            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('रद्द करा'),
            ),

            // ======================================================
            // SAVE
            // ======================================================

            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }

                final amount =
                    double.parse(
                  amountController.text.trim(),
                );

                final data = MahaprasadKharch(
                  id: item?.id,
                  item: itemController.text.trim(),
                  buyerName:
                      buyerController.text.trim(),
                  amount: amount,
                  year: selectedYear,
                );

                if (item == null) {
                  await _db.insertMahaprasadKharch(
                    data.toMap(),
                  );
                } else {
                  await _db.updateMahaprasadKharch(
                    data.id!,
                    data.toMap(),
                  );
                }

                if (!context.mounted) return;

                Navigator.pop(context);

                await _loadData();
              },
              child: Text(
                item == null
                    ? 'जतन करा'
                    : 'बदल जतन करा',
              ),
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
  // YEAR DROPDOWN
  // ============================================================

  Widget _buildYearDropdown() {
    final currentYear = DateTime.now().year;

    final years = List.generate(
      6,
      (index) => currentYear - index,
    );

    return DropdownButton<int>(
      value: selectedYear,
      items: years.map((year) {
        return DropdownMenuItem<int>(
          value: year,
          child: Text('$year'),
        );
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        4,
        8,
        4,
        10,
      ),
      child: Row(
        children: [
          Icon(
            Icons.shopping_basket_outlined,
            color: Color(0xFFB94D00),
          ),
          SizedBox(width: 9),
          Text(
            'खरेदी नोंदी',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TABLE ROW
  // ============================================================

  Widget _buildRow(
    MahaprasadKharch item,
    int index,
  ) {
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: 0.95,
        end: 1,
      ),
      duration: const Duration(
        milliseconds: 280,
      ),
      curve: Curves.easeOutCubic,
      builder: (
        context,
        value,
        child,
      ) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(
              0,
              7 * (1 - value),
            ),
            child: child,
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.only(
          bottom: 9,
        ),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(18),
          onTap: () =>
              _showAddEditDialog(
            item: item,
          ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 12,
            ),
            child: Row(
              children: [
                // ==================================================
                // NUMBER
                // ==================================================

                CircleAvatar(
                  radius: 19,
                  backgroundColor:
                      const Color(0xFFFFF0E1),
                  foregroundColor:
                      const Color(0xFFB94D00),
                  child: Text(
                    '${index + 1}',
                  ),
                ),

                const SizedBox(width: 12),

                // ==================================================
                // ITEM DETAILS
                // ==================================================

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.item,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style:
                            const TextStyle(
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                      const SizedBox(
                        height: 3,
                      ),
                      Text(
                        item.buyerName,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style:
                            const TextStyle(
                          color:
                              Color(0xFF756A5D),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // ==================================================
                // AMOUNT + EDIT + DELETE
                // ==================================================

                Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${item.amount.toStringAsFixed(0)}',
                      textAlign:
                          TextAlign.right,
                      style:
                          const TextStyle(
                        color:
                            Color(0xFFB94D00),
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),

                    Row(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        // ==================================================
                        // EDIT BUTTON
                        // ==================================================

                        IconButton(
                          tooltip: 'बदला',
                          visualDensity:
                              VisualDensity.compact,
                          icon: const Icon(
                            Icons.edit_outlined,
                          ),
                          onPressed: () =>
                              _showAddEditDialog(
                            item: item,
                          ),
                        ),

                        // ==================================================
                        // DELETE BUTTON
                        // ==================================================

                        IconButton(
                          tooltip: 'हटवा',
                          visualDensity:
                              VisualDensity.compact,
                          icon: const Icon(
                            Icons.delete_outline,
                            color:
                                Color(0xFFD32F2F),
                          ),
                          onPressed: () async {
                            final confirmed =
                                await confirmRecordDelete(
                              context,
                              message:
                                  'ही नोंद हटवायची आहे का?',
                            );

                            if (!confirmed) {
                              return;
                            }

                            await _db
                                .deleteMahaprasadKharch(
                              item.id!,
                            );

                            await _loadData();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'महाप्रसाद बाजार ($selectedYear)',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),

      // ==========================================================
      // ADD BUTTON
      // ==========================================================

      floatingActionButton:
          FloatingActionButton.extended(
        onPressed: () {
          _showAddEditDialog();
        },
        icon: const Icon(Icons.add),
        label: const Text(
          'नवीन खर्च',
        ),
      ),

      // ==========================================================
      // BODY
      // ==========================================================

      body: RefreshIndicator(
        onRefresh: _loadData,
        child: isLoading
            ? const Center(
                child:
                    CircularProgressIndicator(),
              )
            : SingleChildScrollView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    // ==================================================
                    // YEAR
                    // ==================================================

                    Row(
                      children: [
                        const Text(
                          'वर्ष : ',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                        _buildYearDropdown(),
                      ],
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    // ==================================================
                    // TOTAL
                    // ==================================================

                    Card(
                      elevation: 2,
                      child: Padding(
                        padding:
                            const EdgeInsets.all(
                          15,
                        ),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .spaceBetween,
                          children: [
                            const Text(
                              'एकूण खर्च',
                              style:
                                  TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.w700,
                                color:
                                    Color(0xFFB94D00),
                              ),
                            ),
                            TweenAnimationBuilder<
                                double>(
                              tween: Tween(
                                begin: 0,
                                end: total,
                              ),
                              duration:
                                  const Duration(
                                milliseconds: 420,
                              ),
                              curve:
                                  Curves.easeOutCubic,
                              builder: (
                                context,
                                amount,
                                child,
                              ) {
                                return Text(
                                  '₹${amount.toStringAsFixed(0)}',
                                  textAlign:
                                      TextAlign.right,
                                  style:
                                      const TextStyle(
                                    fontSize: 22,
                                    fontWeight:
                                        FontWeight.w800,
                                    color:
                                        Color(0xFF25231F),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(
                      height: 15,
                    ),

                    // ==================================================
                    // TABLE HEADER
                    // ==================================================

                    _buildHeader(),

                    // ==================================================
                    // DATA
                    // ==================================================

                    if (_items.isEmpty)
                      Container(
                        width:
                            double.infinity,
                        padding:
                            const EdgeInsets
                                .all(30),
                        decoration:
                            const BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.all(
                            Radius.circular(18),
                          ),
                        ),
                        child:
                            const Column(
                          children: [
                            Icon(
                              Icons
                                  .shopping_basket_outlined,
                              color:
                                  Color(0xFFB94D00),
                              size: 32,
                            ),
                            SizedBox(
                              height: 10,
                            ),
                            Text(
                              'या वर्षासाठी कोणताही खर्च उपलब्ध नाही.',
                              textAlign:
                                  TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      ..._items
                          .asMap()
                          .entries
                          .map(
                        (entry) {
                          return Dismissible(
                            key: ValueKey(
                              entry.value.id,
                            ),

                            // Swipe left only.
                            direction:
                                DismissDirection
                                    .endToStart,

                            // Swipe background.
                            background:
                                recordDeleteBackground(),

                            // Confirmation before
                            // swipe delete.
                            confirmDismiss:
                                (_) =>
                                    confirmRecordDelete(
                              context,
                              message:
                                  'ही नोंद हटवायची आहे का?',
                            ),

                            // Delete from database.
                            onDismissed: (_) {
                              deleteRecordAndRefresh(
                                context,
                                delete: () async {
                                  await _db
                                      .deleteMahaprasadKharch(
                                    entry.value.id!,
                                  );
                                },
                                refresh:
                                    _loadData,
                              );
                            },

                            // Actual row.
                            child: _buildRow(
                              entry.value,
                              entry.key,
                            ),
                          );
                        },
                      ),

                    const SizedBox(
                      height: 80,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}