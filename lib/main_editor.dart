import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'app/ghost_app.dart';
import 'editor/editor_widget.dart';
import 'editor/input/ime.dart';
import 'editor/state/state.dart';
import 'editor/view/base.dart';
import 'editor/view/editor_view.dart';
import 'editor/view/plugin.dart';
import 'main.dart' show appStyleSheets;

/// The editor alone on a phone, with a long seeded note to type in: `flutter run -t lib/main_editor.dart`. A line
/// over the note says what the input layer holds (the selection, the keyboard's window, how many values were
/// pushed, the last press held), and everything the keyboard's client does goes to the log
/// (`adb logcat -s flutter`, lines that start `IME`).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final sheet = await loadTokenSheet(more: appStyleSheets);
  EditorIme.log = (line) => debugPrint('IME $line');
  runApp(GhostApp(sheet: sheet, home: const EditorDemo()));
}

/// The note the demo opens on: one of everything the input layer has to get right, then enough paragraphs to
/// scroll through (about 60 kB).
String demoNote() {
  final out = StringBuffer()
    ..writeln('# A note to type in')
    ..writeln()
    ..writeln('Plain words first, with **bold**, _italics_ and `code` among them so marks open and close under the caret.')
    ..writeln()
    ..writeln('- a list')
    ..writeln('- of three')
    ..writeln('- things')
    ..writeln()
    ..writeln('- [ ] a to-do to tick')
    ..writeln('- [x] and one that is done')
    ..writeln()
    ..writeln('1. first')
    ..writeln('2. second')
    ..writeln()
    ..writeln('> quoted words that go on long enough to wrap onto a second line of the screen, so a caret can go up and down inside them')
    ..writeln()
    ..writeln('## And a heading')
    ..writeln();
  for (var n = 1; out.length < 60000; n++) {
    out
      ..writeln('Paragraph $n. The quick brown fox jumps over the lazy dog, then turns round and does it again for the sign-in page, $n times over.')
      ..writeln();
  }
  return out.toString();
}

class EditorDemo extends StatefulWidget {
  const EditorDemo({super.key});

  @override
  State<EditorDemo> createState() => _EditorDemoState();
}

class _EditorDemoState extends State<EditorDemo> {
  final EditorController _controller = EditorController();
  final ValueNotifier<String> _status = ValueNotifier<String>('');
  String _held = '';
  late final EditorView _view = EditorView(
    state: EditorState.create(
      doc: demoNote(),
      extensions: noteExtensions(
        more: <Extension>[
          editorInput(),
          EditorViewLike.updateListener.of((update) => _say()),
        ],
      ),
    ),
  );

  void _say() {
    final sel = _view.state.selection.main;
    final ime = _controller.ime;
    _status.value =
        'sel ${sel.anchor}${sel.empty ? '' : '..${sel.head}'} · window ${ime?.windowFrom}-${ime?.windowTo} · pushed ${ime?.pushes} · attached ${ime?.attaches}${ime?.composing ?? false ? ' · composing' : ''}$_held';
  }

  @override
  void dispose() {
    _view.destroy();
    _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = MediaQuery.of(context);
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Padding(
        // The page shortens for the keyboard, as the web app's activity does for its page.
        padding: EdgeInsets.only(top: media.viewPadding.top, bottom: media.viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
              child: ValueListenableBuilder<String>(
                valueListenable: _status,
                builder: (context, status, _) => Text(status.isEmpty ? 'tap the note' : status, maxLines: 2, style: t.text('xs').copyWith(color: t.color('glacier-text-subtle'))),
              ),
            ),
            Expanded(
              child: CustomScrollView(
                slivers: <Widget>[
                  Editor(
                    view: _view,
                    controller: _controller,
                    footClear: 96,
                    onHold: (held) {
                      _held = ' · held ${held.from}-${held.to} at ${held.x.round()},${held.y.round()}';
                      if (kDebugMode) debugPrint('IME $held');
                      _say();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
