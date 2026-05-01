// lib/widgets/exit_dialog.dart

import 'package:flutter/material.dart';

Future<bool> showExitDialog(BuildContext context,
    {bool isRecording = false}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (ctx) => _ExitDialog(isRecording: isRecording),
  );
  return result ?? false;
}

class _ExitDialog extends StatelessWidget {
  final bool isRecording;
  const _ExitDialog({this.isRecording = false});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0D1627),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: const Color(0xFF00D4FF).withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF00D4FF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.exit_to_app_rounded,
              color: Color(0xFF00D4FF),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Exit Bantay Drive?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      content: Text(
        isRecording
            ? 'Monitoring will stop and all active alerts will be dismissed.'
            : 'Are you sure you want to exit Bantay Drive?',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 14,
          height: 1.5,
        ),
      ),
      actionsAlignment: MainAxisAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white54,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: const Text('Stay', style: TextStyle(fontSize: 15)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF00D4FF).withValues(alpha: 0.15),
            foregroundColor: const Color(0xFF00D4FF),
            side: const BorderSide(color: Color(0xFF00D4FF), width: 1),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text(
            'Exit',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}