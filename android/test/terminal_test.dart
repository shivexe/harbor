import 'package:flutter_test/flutter_test.dart';
import 'package:harbor/interactive_terminal.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('remote terminal replies cannot renew idle timeout or consume Ctrl', () {
    var activity = 0;
    final outputs = <String>[];
    final terminal = InteractiveTerminal(onActivity: () => activity++)
      ..onOutput = outputs.add;
    terminal.controlNext = true;
    terminal.write('\x1b[6n');
    expect(outputs, isNotEmpty);
    expect(activity, 0);
    expect(terminal.controlNext, isTrue);
    terminal.textInput('c');
    expect(outputs.last, '\x03');
    expect(activity, 1);
    expect(terminal.controlNext, isFalse);
    terminal.write('\x1b[?2004h');
    terminal.paste('hello');
    expect(activity, 2);
    terminal.keyInput(TerminalKey.enter);
    expect(activity, 3);
  });
}
