/// The question before a big job (docs/ACTIVITY.md, Cost; Matt, 2026-10-29): "Jobs over about 20 credits or 2 minutes
/// ask first ("12 banners · ~72 Lovart credits · ~4 min", Start / Cancel); smaller ones just run, with the estimate in
/// the tray and a live credit count."
///
/// [askJobCost] answers at once, true, for a job its estimate says is small ([JobEstimate.asks]); otherwise it asks in
/// the app's own sheet, as its other questions are asked (lib/notes/folder_drag.dart `askToMove`): a window in the
/// middle on a Mac and a sheet from the foot on a phone, with the estimate's words, Start and Cancel. Start is the
/// default, taken by Return; Cancel, Escape, the back gesture and a tap outside start nothing.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/background_jobs.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';

/// Whether to start a job of [estimate], asked where it is a big one: [title] is what it is ("Make header images?").
/// Answers false where there is no overlay to ask in.
Future<bool> askJobCost(BuildContext context, JobEstimate estimate, {required String title}) {
  if (!estimate.asks) return Future.value(true);
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future.value(false);
  final answer = Completer<bool>();
  late final OverlayEntry entry;
  void done(bool start) {
    if (answer.isCompleted) return;
    entry.remove();
    answer.complete(start);
  }

  entry = OverlayEntry(builder: (_) => _CostAsk(title: title, estimate: estimate, onAnswer: done));
  overlay.insert(entry);
  return answer.future;
}

class _CostAsk extends StatelessWidget {
  const _CostAsk({required this.title, required this.estimate, required this.onAnswer});

  final String title;
  final JobEstimate estimate;
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
        key: const ValueKey('cost-ask'),
        label: title,
        onClose: () => onAnswer(false),
        children: [
          SheetTitle.text(title),
          SheetNote(estimate.words),
          SheetGroup(
            children: [
              SheetRow(key: const ValueKey('cost-ask-start'), label: 'Start', onPress: () => onAnswer(true)),
              SheetRow(key: const ValueKey('cost-ask-cancel'), label: 'Cancel', onPress: () => onAnswer(false)),
            ],
          ),
        ],
      ),
    );
  }
}
