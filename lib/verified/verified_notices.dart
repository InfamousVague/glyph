/// A verified page whose time ran out tells its owner, through the bell (Matt, 2026-10-30: "add all 12"): one row,
/// "Launch plan needs review: its verification ran out", which opens the page.
///
/// Every device of the owner's account looks, at each pass of the notifications (lib/root/account_wiring.dart), over
/// the notes it holds; the row is the account's own, sealed under the account key as the app's other rows are
/// (lib/sync/record.dart), with an id made from the page and its last day ([expiredNotices]), so whichever device
/// posts first makes the one row and the others' posts land on it. Each device keeps the ids it has told, so it
/// does not post again on every pass. A page verified again has another last day, and runs out again in its time.
library;

import '../core/stored.dart';
import '../sync/record.dart';
import 'verified.dart';

String _key(int accountId) => 'glyph-verified-told-$accountId';

/// The pages [me] vouches for that have run out, told once each. Answers how many were told. Never throws.
Future<int> tellExpiredPages({
  required SelfNotifications record,
  required int accountId,
  required String me,
  required Iterable<({String id, String body, String title})> notes,
  DateTime? today,
  Stored? kept,
}) async {
  final device = kept ?? stored;
  final told = <String>{...device.read<List<String>>(_key(accountId), const [], (raw) => raw is List ? [for (final id in raw) if (id is String) id] : null)};
  final due = expiredNotices(notes, me: me, today: today ?? DateTime.now(), told: told.contains);
  if (due.isEmpty) return 0;
  for (final page in due) {
    try {
      await record.recordAs(page.id, 'page-expired', {'noteId': page.noteId, 'title': page.title});
    } catch (_) {
      // Recorded rows never throw; anything else is tried again next pass.
      continue;
    }
    told.add(page.id);
  }
  final list = told.toList();
  device.write(_key(accountId), list.length > 500 ? list.sublist(list.length - 500) : list);
  return due.length;
}
