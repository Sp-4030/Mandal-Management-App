import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/mahaprasad_kharch_model.dart';
import '../services/auth_service.dart';
import '../utils/record_delete.dart';

class MahaprasadKharchScreen extends StatefulWidget {
  final bool initialLoading;
  const MahaprasadKharchScreen({super.key, this.initialLoading = true});

  @override
  State<MahaprasadKharchScreen> createState() =>
      _MahaprasadKharchScreenState();
}

class _MahaprasadKharchScreenState
    extends State<MahaprasadKharchScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final AuthService _authService = AuthService.instance;

  List<MahaprasadKharch> _items = [];

  late int selectedYear;

  double total = 0.0;

  late bool isLoading;

  @override
  void initState() {
    super.initState();

    selectedYear = DateTime.now().year;
    isLoading = widget.initialLoading;
    if (widget.initialLoading) {
      _loadData();
    }
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadData() async {
    setState(() {
      isLoading = true;
    });

    try {
      final data = await _db.getMahaprasadKharch(selectedYear);
      final totalAmount = await _db.getMahaprasadKharchTotal(selectedYear);

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
      return;
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });
  }

  // ============================================================
  // ADD / EDIT DIALOG
  // ============================================================

  Future<void> _showAddEditDialog({
    MahaprasadKharch? item,
  }) async {
    if (item == null && !_authService.canAdd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'माजी खजानी किंवा विना-परवानगी वापरकर्त्यास खर्च जोडण्याची परवानगी नाही.',
          ),
        ),
      );
      return;
    }
    if (item != null && !_authService.canEdit) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'माजी खजानी किंवा विना-परवानगी वापरकर्त्यास खर्च बदलण्याची परवानगी नाही.',
          ),
        ),
      );
      return;
    }

    final itemController =
        TextEditingController(
      text: item?.item ?? '',
    );

    final buyerController =
        TextEditingController(
      text: item?.buyerName ?? '',
    );

    final amountController =
        TextEditingController(
      text: item == null
          ? ''
          : item.amount.toString(),
    );

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            item == null
                ? 'नवीन खरेदी नोंद'
                : 'नोंद बदला',
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: itemController,
                  decoration: const InputDecoration(
                    labelText: 'वस्तूचे नाव',
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'कृपया वस्तूचे नाव टाका';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: buyerController,
                  decoration: const InputDecoration(
                    labelText: 'खरेदीदाराचे नाव',
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'कृपया खरेदीदाराचे नाव टाका';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'रक्कम',
                    prefixText: '₹ ',
                  ),
                  validator: (value) {
                    if (value == null ||
                        value.trim().isEmpty) {
                      return 'कृपया रक्कम टाका';
                    }

                    final parsed =
                        double.tryParse(
                      value.trim(),
                    );

                    if (parsed == null ||
                        parsed <= 0) {
                      return 'कृपया योग्य रक्कम टाका';
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
              child: const Text('रद्द'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) {
                  return;
                }

                final newItem =
                    MahaprasadKharch(
                  id: item?.id,
                  item: itemController.text.trim(),
                  buyerName:
                      buyerController.text.trim(),
                  amount: double.parse(
                    amountController.text.trim(),
                  ),
                  year: selectedYear,
                );

                if (item == null) {
                  await _db
                      .insertMahaprasadKharch(
                    newItem.toMap(),
                  );
                } else {
                  await _db
                      .updateMahaprasadKharch(
                    item.id!,
                    newItem.toMap(),
                  );
                }

                if (!context.mounted) return;

                Navigator.pop(context);

                _loadData();
              },
              child: const Text('जतन करा'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // TOTAL CARD
  // ============================================================

  Widget _buildTotalCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFF0E1),
            Color(0xFFFFDFBD),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFF2D1AE),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'महाप्रसाद एकूण खर्च',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFFB94D00),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          TweenAnimationBuilder<double>(
            tween: Tween(
              begin: 0,
              end: total,
            ),
            duration: const Duration(
              milliseconds: 400,
            ),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Text(
                '₹${value.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF25231F),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // YEAR DROPDOWN
  // ============================================================

  Widget _buildYearDropdown() {
    return DropdownButton<int>(
      value: selectedYear,
      items: List.generate(
        11,
        (index) {
          final year =
              DateTime.now().year - 5 + index;

          return DropdownMenuItem<int>(
            value: year,
            child: Text('$year'),
          );
        },
      ),
      onChanged: (year) {
        if (year == null) return;

        setState(() {
          selectedYear = year;
        });

        _loadData();
      },
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        4,
        2,
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
    final canEdit = _authService.canEdit;
    final canDelete = _authService.canDelete;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(
        milliseconds: 180 + (index * 20),
      ),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
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
          onTap: canEdit
              ? () => _showAddEditDialog(
                    item: item,
                  )
              : null,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 12,
            ),
            child: Row(
              children: [
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
                    if (canEdit || canDelete)
                      Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          if (canEdit)
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
                          if (canDelete)
                            IconButton(
                              tooltip: 'हटवा',
                              visualDensity:
                                  VisualDensity.compact,
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () async {
                                final confirmed =
                                    await confirmRecordDelete(
                                  context,
                                  message:
                                      'ही नोंद हटवायची आहे का?',
                                );
                                if (!confirmed) return;
                                if (!mounted) return;

                                await deleteRecordAndRefresh(
                                  context,
                                  delete: () async {
                                    await _db
                                        .deleteMahaprasadKharch(
                                      item.id!,
                                    );
                                  },
                                  refresh:
                                      _loadData,
                                );
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
  // EMPTY VIEW
  // ============================================================

  Widget _buildEmpty() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 36,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFF0E6D9),
        ),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 34,
            color: Color(0xFFB94D00),
          ),
          SizedBox(height: 10),
          Text(
            'या वर्षासाठी कोणतीही खरेदी नोंद उपलब्ध नाही.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF756A5D),
            ),
          ),
        ],
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
    final canAdd = _authService.canAdd;
    final canDelete = _authService.canDelete;
    final canModify = _authService.canModify;
    final isOldKhajani = _authService.isOldKhajani;

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

      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: () {
                _showAddEditDialog();
              },
              icon: const Icon(Icons.add),
              label: const Text(
                'नवीन खर्च',
              ),
            )
          : null,

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
                    const EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  90,
                ),
                child: Column(
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

                    Card(
                      child: Padding(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons
                                  .calendar_month,
                              color: Color(
                                  0xFFB94D00),
                            ),
                            const SizedBox(
                              width: 12,
                            ),
                            const Text(
                              'वर्ष निवडा: ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight
                                        .w600,
                              ),
                            ),
                            const Spacer(),
                            _buildYearDropdown(),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    _buildTotalCard(),

                    const SizedBox(height: 16),

                    _buildHeader(),

                    if (_items.isEmpty)
                      _buildEmpty()
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
                            direction: canDelete
                                ? DismissDirection.endToStart
                                : DismissDirection.none,
                            background:
                                recordDeleteBackground(),
                            confirmDismiss:
                                (_) =>
                                    confirmRecordDelete(
                                context,
                                message:
                                    'ही नोंद हटवायची आहे का?',
                              ),
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