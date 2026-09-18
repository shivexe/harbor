import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../ssh_session.dart';
import '../main.dart' show surface;

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({
    required this.connection,
    required this.onClose,
    super.key,
  });
  final Connection connection;
  final VoidCallback onClose;
  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final focus = FocusNode();
  final controller = TerminalController();
  @override
  void initState() {
    super.initState();
    widget.connection.addListener(changed);
    if (widget.connection.client == null) {
      unawaited(widget.connection.connect());
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.connection.removeListener(changed);
    focus.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff090f1b),
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.connection.host.name,
            style: const TextStyle(fontSize: 17),
          ),
          Text(
            widget.connection.status,
            maxLines: 2,
            style: const TextStyle(fontSize: 11, color: Color(0xffa1b1cb)),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Copy selection',
          onPressed: () {
            final selection = controller.selection;
            if (selection != null) {
              Clipboard.setData(
                ClipboardData(
                  text: widget.connection.terminal.buffer.getText(selection),
                ),
              );
            }
          },
          icon: const Icon(Icons.copy, size: 20),
        ),
        IconButton(
          tooltip: 'Close session',
          onPressed: () {
            widget.onClose();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.close),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: TerminalView(
              widget.connection.terminal,
              controller: controller,
              focusNode: focus,
              autofocus: true,
              padding: const EdgeInsets.all(8),
              textStyle: const TerminalStyle(fontSize: 13),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                TextButton(
                  onPressed: () => widget.connection.send('\x1b'),
                  child: const Text('Esc'),
                ),
                TextButton(
                  onPressed: () => setState(
                    () => widget.connection.controlNext =
                        !widget.connection.controlNext,
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: widget.connection.controlNext
                        ? surface
                        : null,
                  ),
                  child: const Text('Ctrl'),
                ),
                TextButton(
                  onPressed: () => widget.connection.send('\t'),
                  child: const Text('Tab'),
                ),
                for (final entry in {
                  '↑': '\x1b[A',
                  '↓': '\x1b[B',
                  '←': '\x1b[D',
                  '→': '\x1b[C',
                }.entries)
                  TextButton(
                    onPressed: () => widget.connection.send(entry.value),
                    child: Text(entry.key),
                  ),
                IconButton(
                  tooltip: 'Show keyboard',
                  onPressed: () => focus.requestFocus(),
                  icon: const Icon(Icons.keyboard_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
