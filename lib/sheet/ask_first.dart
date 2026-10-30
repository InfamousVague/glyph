/// A question asked before something is done that cannot be taken back quietly: a ticket moved to done while it still
/// waits on another, a button that posts to Slack or spends Claude's credits (Matt, 2026-10-30, of a list of
/// plain-Markdown features: "add all 12"). As a folder's move across an organization's edge is asked
/// (lib/notes/folder_drag.dart `askToMove`): a sheet over the app, a window in the middle on a Mac and a sheet from the
/// foot on a phone, its title, the line that says what happens, the yes and Cancel. The yes is the default, taken by
/// Return; Cancel, Escape, the back gesture and a tap outside do nothing.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'kit.dart';
import 'sheet.dart';

/// What is asked: the title, the line under it, the yes's words, and what the sheet is called for a screen reader.
@immutable
class FirstAsk {
  const FirstAsk({required this.title, required this.note, required this.yes, String? label}) : label = label ?? title;

  /// "Move GHO-12 to Done?"
  final String title;

  /// "It still waits on GHO-9, which isn't done."
  final String note;

  /// "Move it anyway", "Post", "Ask Claude".
  final String yes;
  final String label;

  @override
  String toString() => 'FirstAsk($title $note)';
}

/// A test's answer in place of the sheet's: whatever it is set to answers every ask at once, and is told of it.
@visibleForTesting
Future<bool> Function(FirstAsk ask)? debugAskFirst;

/// Asks [ask] over the app; true for the yes, false for anything else, or where there is no overlay to ask in.
Future<bool> askFirst(BuildContext context, FirstAsk ask) {
  final answering = debugAskFirst;
  if (answering != null) return answering(ask);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future.value(false);
  final answer = Completer<bool>();
  late final OverlayEntry entry;
  void done(bool yes) {
    if (answer.isCompleted) return;
    entry.remove();
    answer.complete(yes);
  }

  entry = OverlayEntry(builder: (_) => FirstAskSheet(ask: ask, onAnswer: done));
  overlay.insert(entry);
  return answer.future;
}

/// The question's sheet: the focus held while it is up, so Return is the yes.
class FirstAskSheet extends StatelessWidget {
  const FirstAskSheet({super.key, required this.ask, required this.onAnswer});

  final FirstAsk ask;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          onAnswer(true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Sheet(
        key: const ValueKey('first-ask'),
        label: ask.label,
        onClose: () => onAnswer(false),
        children: [
          SheetTitle.text(ask.title),
          SheetNote(ask.note),
          SheetGroup(
            children: [
              SheetRow(key: const ValueKey('first-ask-yes'), label: ask.yes, onPress: () => onAnswer(true)),
              SheetRow(key: const ValueKey('first-ask-no'), label: 'Cancel', onPress: () => onAnswer(false)),
            ],
          ),
        ],
      ),
    );
  }
}
