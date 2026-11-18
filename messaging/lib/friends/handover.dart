import 'dart:convert';

import '../desktop/own_calls.dart' show DeskOwnCalls;
import '../me/me.dart';
import '../net/crypto.dart';
import '../sms.dart';
import '../standalone/overlay.dart';
import 'buddies.dart';

/// On the phone: what a paired computer is handed to have friends and circles of its own (Matt, 2026-11-18: "I want
/// desktop to be able to run standalone for internal friends and circles please fix that even if the desktop is
/// linked"; lib/desktop/own_calls.dart). Asked across the pairing's own link, which only that computer and this phone
/// can read (it was confirmed by the six digits both showed): the identity's key, the friends by username, the
/// conversations with them, and who this is (username, name, line).
///
/// `{"buddies": "<json>"}` in what is asked is the computer's own list: taken in first, so a friend made there is
/// this phone's too. `{"only": "buddies"}` hands over the list alone (asked each time the two connect).
Future<Object?> answerHandover(Map<String, Object?> what) async {
  final theirs = what['buddies'];
  final b = Buddies.instance;
  if (theirs is String && theirs.isNotEmpty) {
    final merged = DeskOwnCalls.mergeBuddies(jsonEncode([for (final x in b.all) x.toJson()]), theirs);
    await b.takeAll(merged);
  }
  final list = jsonEncode([for (final x in b.all) x.toJson()]);
  if (what['only'] == 'buddies') return {'buddies': list};
  final scalar = await Sms.instance.identityExport();
  final calls = Sms.calls;
  final me = Me.instance;
  return {
    'scalar': NetCrypto.hex(scalar),
    'buddies': list,
    if (calls is OverlayCalls) 'chats': calls.chats.toJson(),
    'me': {'u': me.username ?? '', 'n': me.displayName, 'b': me.bio},
  };
}
