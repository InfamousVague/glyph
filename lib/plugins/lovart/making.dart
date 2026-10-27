/// What Lovart is making on this device now, besides the run over the recent notes (banner_run.dart keeps its own
/// queue): the `{image: …}` cues and the inspiration moodboards. The cue's chip draws its spinner by [lovartMaking],
/// and Settings › Lovart's Queue lists both (lovart_queue.dart).
library;

import 'package:flutter/foundation.dart';

/// The cues being made now, by note and cue (`noteId\ncue`): the chip by each draws a spinner while it is here.
final ValueNotifier<Set<String>> lovartMaking = ValueNotifier<Set<String>>(const {});

/// The key a cue is kept under in [lovartMaking].
String makingKey(String noteId, String cueText) => '$noteId\n$cueText';

/// Whether the cue [cueText] of [noteId] is being made.
bool lovartIsMaking(String noteId, String cueText) => lovartMaking.value.contains(makingKey(noteId, cueText));

/// Marks the cue [key] made now, or done.
void markMaking(String key, bool on) {
  final next = {...lovartMaking.value};
  if (on ? next.add(key) : next.remove(key)) lovartMaking.value = Set.unmodifiable(next);
}

/// The notes an inspiration moodboard is being made for now: asked on the note's cog, or a design meeting's.
final ValueNotifier<Set<String>> lovartInspiring = ValueNotifier<Set<String>>(const {});

/// Marks [noteId]'s moodboard made now, or done.
void markInspiring(String noteId, bool on) {
  final next = {...lovartInspiring.value};
  if (on ? next.add(noteId) : next.remove(noteId)) lovartInspiring.value = Set.unmodifiable(next);
}
