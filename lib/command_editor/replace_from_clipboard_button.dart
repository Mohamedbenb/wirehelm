import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ReplaceFromClipboardButton
    extends StatelessWidget {
  final TextEditingController controller;

  const ReplaceFromClipboardButton({
    super.key,
    required this.controller,
  });

  Future<void> _replace(
    BuildContext context,
  ) async {
    final data =
        await Clipboard.getData(
      Clipboard.kTextPlain,
    );

    final text =
        data?.text;

    if (text == null) {
      return;
    }

    controller.value =
        TextEditingValue(
      text: text,
      selection:
          TextSelection.collapsed(
        offset: text.length,
      ),
    );

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      const SnackBar(
        content: Text(
          'Replaced from clipboard',
        ),
        duration: Duration(
          milliseconds: 800,
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return IconButton(
      tooltip:
          'Replace with clipboard',
      visualDensity:
          VisualDensity.compact,
      icon:
          const Icon(
        Icons.content_paste_outlined,
        size: 19,
      ),
      onPressed:
          () => _replace(
        context,
      ),
    );
  }
}