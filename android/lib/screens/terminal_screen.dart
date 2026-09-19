import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../ssh_session.dart';
import '../ui.dart';

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

  Widget keyButton(
    String label,
    VoidCallback action, {
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: TextButton(
      onPressed: action,
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        foregroundColor: selected ? canvas : ink,
        backgroundColor: selected ? actionColor : raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
  );

  Color get actionColor => action;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xff101217),
    appBar: AppBar(
      title: Text(
        widget.connection.host.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
          icon: const Icon(Icons.copy_outlined, size: 21),
        ),
        IconButton(
          tooltip: 'Back to sessions',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.view_list_outlined, size: 23),
        ),
        IconButton(
          tooltip: 'Close session',
          onPressed: () {
            widget.onClose();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.close, size: 22),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            color: panel,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Icon(
                    widget.connection.status == 'Connected'
                        ? Icons.circle
                        : Icons.circle_outlined,
                    size: 10,
                    color: widget.connection.status == 'Connected'
                        ? const Color(0xff8fd7b6)
                        : muted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${widget.connection.host.username}@${widget.connection.host.address}:${widget.connection.host.port}  ·  ${widget.connection.status}',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 14,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
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
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: const BoxDecoration(
              color: panel,
              border: Border(top: BorderSide(color: hairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        keyButton('Esc', () => widget.connection.send('\x1b')),
                        keyButton(
                          'Ctrl',
                          () => setState(
                            () => widget.connection.controlNext =
                                !widget.connection.controlNext,
                          ),
                          selected: widget.connection.controlNext,
                        ),
                        keyButton('Tab', () => widget.connection.send('\t')),
                        for (final entry in {
                          '↑': '\x1b[A',
                          '↓': '\x1b[B',
                          '←': '\x1b[D',
                          '→': '\x1b[C',
                        }.entries)
                          keyButton(
                            entry.key,
                            () => widget.connection.send(entry.value),
                          ),
                      ],
                    ),
                  ),
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
