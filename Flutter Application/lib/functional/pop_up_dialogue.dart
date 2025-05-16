import 'package:flutter/material.dart';

Future<T?> showPopUpDialogue<T>(
    BuildContext context, String title, String text, Map<String, T> options) {
  return showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          ...options.entries.map(
            (entry) => TextButton(
              onPressed: () => Navigator.pop(context, entry.value),
              child: Text(entry.key),
            ),
          ),
        ],
      );
    },
  );
}
