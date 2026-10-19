/// The right pane of simple mode's wide window while no note is open (GHST-105): the ghost and one line, where the
/// advanced app draws nothing (its home page takes the whole window until a note opens, and its notes sit in a
/// docked tree beside the note). Apple Notes on an iPad and Simplenote on a Mac leave the note pane quiet with a
/// word or two; so does this.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

class SimpleEmptyPane extends StatelessWidget {
  const SimpleEmptyPane({super.key, this.ghost});

  /// The ghost over the words (lib/art/ghost.dart), where the app hands one in.
  final Widget? ghost;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ghost = this.ghost;
    return ColoredBox(
      color: t.color('glacier-bg'),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: t.lenOf('20rem')),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ghost != null) ...[ghost, SizedBox(height: t.space(4))],
              Text('Pick a note, or make one.', textAlign: TextAlign.center, style: t.textAt(t.fontSize('md'), color: t.color('app-ink-3'))),
            ],
          ),
        ),
      ),
    );
  }
}
