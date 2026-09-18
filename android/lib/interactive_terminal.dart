import 'package:xterm/xterm.dart';

class InteractiveTerminal extends Terminal {
  InteractiveTerminal({required this.onActivity}) : super(maxLines: 10000);
  final void Function() onActivity;
  void Function()? onControlChanged;
  bool controlNext = false;
  void consumeControl() {
    if (controlNext) {
      controlNext = false;
      onControlChanged?.call();
    }
  }

  @override
  bool keyInput(
    TerminalKey key, {
    bool shift = false,
    bool alt = false,
    bool ctrl = false,
  }) {
    final handled = super.keyInput(
      key,
      shift: shift,
      alt: alt,
      ctrl: ctrl || controlNext,
    );
    if (handled) {
      onActivity();
      consumeControl();
    }
    return handled;
  }

  @override
  bool charInput(int charCode, {bool alt = false, bool ctrl = false}) {
    final handled = super.charInput(
      charCode,
      alt: alt,
      ctrl: ctrl || controlNext,
    );
    if (handled) {
      onActivity();
      consumeControl();
    }
    return handled;
  }

  @override
  void textInput(String text) {
    if (text.isEmpty) return;
    onActivity();
    if (controlNext) {
      final code = text.toLowerCase().codeUnitAt(0);
      if (code >= 97 && code <= 122) {
        text = String.fromCharCode(code - 96) + text.substring(1);
      }
      consumeControl();
    }
    super.textInput(text);
  }

  @override
  void paste(String text) {
    if (bracketedPasteMode && text.isNotEmpty) onActivity();
    super.paste(text);
  }
}
