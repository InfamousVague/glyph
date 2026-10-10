import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'app/ghost_app.dart';
import 'app/style_sheets.dart';
import 'editor/diagrams/diagrams.dart';
import 'editor/editor_widget.dart';
import 'editor/state/state.dart';
import 'editor/view/base.dart';
import 'editor/view/editor_view.dart';
import 'shell/desktop/mac_tour.dart';
import 'shell/desktop/mac_window.dart';
import 'shell/phone_tour.dart';

/// A note of diagrams alone, with no library under it: `flutter run -t lib/main_diagrams.dart`, on a phone, a Mac
/// or an iPhone. One of each kind a note is likeliest to hold, one written wrong, and words between them, drawn by
/// the platform's own web view (lib/editor/diagrams/bridge.dart), so each platform's half of `ghost_md/diagrams`
/// can be looked at without a note of anyone's being opened or written. A line over the note says how many
/// pictures the web view was asked for and how many came from the folder.
///
/// A debug build walks itself here as the app does (`GHOST_TOUR` on a Mac, tool/ios-tour.sh on an iPhone), so the
/// Mac's and the iPhone's can be photographed with no hand on them:
///
/// ```sh
/// flutter build macos --debug -t lib/main_diagrams.dart
/// GHOST_TOUR='wait:5000;shot:diagrams;quit' "build/macos/Build/Products/Debug/Ghost Flutter.app/Contents/MacOS/Ghost Flutter"
/// ```
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final sheet = await loadTokenSheet(more: appStyleSheets);
  // The Mac's window, for a walk's pictures and its end (a no-op anywhere else).
  MacWindow.instance.attach();
  runApp(GhostApp(sheet: sheet, home: const DiagramsDemo()));
  if (kDebugMode) {
    unawaited(runMacTour());
    unawaited(runPhoneTour());
  }
}

/// The note the demo opens on.
const String diagramsNote = '''
# Diagrams

A chart, as a canvas's card starts.

```mermaid
flowchart LR
  A[Start] --> B[Then]
  B --> C[Done]
```

Labels long enough to wrap.

```mermaid
flowchart LR
  F[Friday: drive up] --> S[Saturday: the lake]
  S --> U[Sunday: the long walk]
  U --> H[Home by dark]
```

One written wrong, which stays its words.

```mermaid
flowchart TD
  A -->
```

A sequence.

```mermaid
sequenceDiagram
  participant P as Phone
  participant B as The box
  P->>B: The note, sealed
  B-->>P: Kept
  Note over P,B: Nothing read on the way
```

A gantt.

```mermaid
gantt
  title A plan
  dateFormat YYYY-MM-DD
  section One
  Write it :done, a1, 2026-10-01, 3d
  Ship it :active, a2, after a1, 4d
  Late :crit, a3, 2026-10-02, 2d
```

A pie, and the end.

```mermaid
pie title Notes
  "Typed" : 42
  "Spoken" : 58
```
''';

class DiagramsDemo extends StatefulWidget {
  const DiagramsDemo({super.key});

  @override
  State<DiagramsDemo> createState() => _DiagramsDemoState();
}

class _DiagramsDemoState extends State<DiagramsDemo> {
  final EditorController _controller = EditorController();
  Timer? _looking;
  late final EditorView _view = EditorView(
    state: EditorState.create(
      doc: diagramsNote,
      extensions: noteExtensions(more: <Extension>[editorInput(), drawnMermaid()]),
    ),
  );

  @override
  void initState() {
    super.initState();
    // The store says nothing as it works: looked at twice a second, for the line over the note.
    _looking = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _looking?.cancel();
    _view.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = MediaQuery.of(context);
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Padding(
        padding: EdgeInsets.only(top: media.viewPadding.top, bottom: media.viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
              child: Text(
                'the web view was asked ${diagramStore.renders} times · ${diagramStore.reads} pictures from the folder',
                maxLines: 2,
                style: t.text('xs').copyWith(color: t.color('glacier-text-subtle')),
              ),
            ),
            Expanded(
              child: CustomScrollView(slivers: <Widget>[Editor(view: _view, controller: _controller, footClear: 96)]),
            ),
          ],
        ),
      ),
    );
  }
}
