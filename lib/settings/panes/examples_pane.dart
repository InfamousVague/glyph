import 'package:flutter/widgets.dart';

import '../../art/art.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'settings_host.dart';
import '../../core/iphone_app.dart' show recordsVoice;

/// What Settings' search finds on Examples (`findable`, src/app/settings/ExamplesPane.findable.ts).
const List<SettingsFindable> examplesFindable = [
  SettingsFindable('Add the sample note', 'example sample'),
  SettingsFindable('Add the example board', 'example kanban'),
  SettingsFindable('Add the example canvas', 'example obsidian'),
  SettingsFindable('Add the “How Ghost.md works” canvas', 'example canvas how it works'),
];

/// Port of `ExamplesPane` (src/app/settings/ExamplesPane.tsx), a page behind About's Help: the notes Ghost.md can add
/// to show what a note can be. Each is made and opened by the app, and each row says what is in it.
///
/// What differs from the web original: a callback may be null (the board and the canvases wait for stages 5 and 6),
/// and its row is then drawn and cannot be pressed, where the page's were always given.
class ExamplesPane extends StatelessWidget {
  const ExamplesPane({super.key, this.onSample, this.onBoard, this.onCanvas, this.onHowCanvas});

  /// Makes the sample note, the one with every mark in it, and opens it.
  final VoidCallback? onSample;
  final VoidCallback? onBoard;
  final VoidCallback? onCanvas;
  final VoidCallback? onHowCanvas;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return ExamplesPane(onSample: host?.onSample, onBoard: host?.onBoard, onCanvas: host?.onCanvas, onHowCanvas: host?.onHowCanvas);
  }

  @override
  Widget build(BuildContext context) {
    // A row with nothing to run keeps its chevron and its place, dimmed.
    SettingRow row(LucideIcon icon, String label, String hint, VoidCallback? onPress) =>
        SettingRow(icon: AppIcon(icon, size: 20), label: label, hint: Text(hint), onPress: onPress ?? () {}, disabled: onPress == null);
    return PaneBody(
      children: [
        PaneSection(
          children: [
            row(Lucide.fileText, 'Add the sample note', 'Every mark in one note: headings, lists, a table, a picture, a secret in smoke.', onSample),
            row(Lucide.layoutGrid, 'Add the example board', 'Columns, cards and the items they point at, written in markdown.', onBoard),
            row(Lucide.workflow, 'Add the example canvas', "Cards on a page with lines between them, in Obsidian's canvas file.", onCanvas),
            row(Lucide.compass, 'Add the “How Ghost.md works” canvas', 'Eight plain cards, in order: ${recordsVoice ? 'say' : 'write'} it, it lands as a note, and where a note can go.', onHowCanvas),
          ],
        ),
      ],
    );
  }
}
