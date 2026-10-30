/// A day mentioned is a reminder (Matt, 2026-10-30: "add all 12", @mentions of dates): `@2026-11-06` in a note
/// reminds on that day at the time Settings › Notifications › Reminders sets for a due day (nine, unless set), as a
/// to-do due that day is (lib/reminders/reminder_plan.dart).
///
/// Whose reminder it is:
/// - **In a note of the person's own**, theirs: nobody else has it, whoever it names.
/// - **In a team's note, beside a person**, `@sam @2026-11-06`, it is that person's: the phone of whoever is signed
///   in as `sam` reminds, and nobody else's.
/// - **In a team's note, on its own**, it is the writer's: the device that wrote the day reminds
///   (lib/mentions/mention_notices.dart [MentionLedger.wroteDay]), and the other members' phones, which have the note
///   too, stay quiet.
///
/// Not a day in the past, nor one in code, a fence or the front matter (mention_syntax.dart). A to-do's line that
/// already has a due day is reminded by it, and its `@day` is not a second reminder.
library;

import 'package:flutter/foundation.dart';

import '../core/days.dart' show isIsoDay;
import 'mention_syntax.dart';

/// Who is asking: the handle signed in on this device, whether a note is a team's, and whether this device wrote a
/// day in one. Handed to the reminders' plan; none, and every day on its own in any note is the person's.
@immutable
class MentionWho {
  const MentionWho({this.me, this.team, this.wrote, this.key = ''});

  final String? me;
  final bool Function(String noteId)? team;
  final bool Function(String noteId, String day)? wrote;

  /// Changes whenever an answer above may have: the plan reads every note again when it does.
  final String key;
}

/// This device's [MentionWho], set where the account is made (lib/root/account_wiring.dart).
final ValueNotifier<MentionWho?> mentionWho = ValueNotifier<MentionWho?>(null);

/// The days mentioned in [body] that remind on this device, by line, each once: `(line, day, words)`, the words the
/// line's own, its mentions as written.
List<({int line, String day, String words})> mentionedDays(String noteId, String body, MentionWho? who) {
  if (!body.contains('@')) return const [];
  final out = <({int line, String day, String words})>[];
  final me = who?.me == null ? null : handleKey(who!.me!);
  final team = who?.team?.call(noteId) ?? false;
  final seen = <String>{};
  final byLine = <int, List<NoteMention>>{};
  for (final found in mentionsInBody(body)) {
    byLine.putIfAbsent(found.line, () => []).add(found);
  }
  for (final MapEntry(key: line, value: found) in byLine.entries) {
    final text = found.first.text;
    // A due day on the line is its reminder already.
    if (text.contains('📅') || text.contains('due::')) continue;
    final mentions = [for (final each in found) each.mention];
    for (final mention in mentions) {
      if (mention.person || !isIsoDay(mention.value)) continue;
      // A note of the person's own: theirs, whoever it names, since nobody else has it.
      final beside = team ? personBeside(text, mentions, mention) : null;
      final bool mine;
      if (!team) {
        mine = true;
      } else if (beside != null) {
        mine = me != null && handleKey(beside.value) == me;
      } else {
        mine = who?.wrote?.call(noteId, mention.value) ?? false;
      }
      if (!mine || !seen.add('$line:${mention.value}')) continue;
      out.add((line: line, day: mention.value, words: text.trim()));
    }
  }
  return out;
}
