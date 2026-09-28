import 'package:flutter/material.dart';

Future<bool> confirmRecordDelete(
  BuildContext context, {
  required String message,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('नोंद हटवायची?'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('रद्द करा'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('हटवा'),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}

Future<void> deleteRecordAndRefresh(
  BuildContext context, {
  required Future<void> Function() delete,
  required Future<void> Function() refresh,
}) async {
  try {
    await delete();
    if (!context.mounted) return;
    await refresh();
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('नोंद हटवता आली नाही. पुन्हा प्रयत्न करा.')),
    );
  }
}

Widget recordDeleteBackground() {
  return Container(
    color: Colors.red,
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 20),
    child: const Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('हटवा', style: TextStyle(color: Colors.white)),
        SizedBox(width: 8),
        Icon(Icons.delete, color: Colors.white),
      ],
    ),
  );
}
