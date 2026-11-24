import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/inbox/inbox.dart';
import 'package:ghost_messaging/sms.dart';
import 'package:ghost_messaging/ui/conversations.dart';

// Matt, 2026-11-24: "also sort unread messages at the top in the app, new messages should come first (before
// unreads)".
void main() {
  final noon = DateTime(2026, 11, 24, 12);
  Conversation text(int id, int minutesAgo, {bool unread = false, bool muted = false}) =>
      Conversation(id: id, date: noon.subtract(Duration(minutes: minutesAgo)), people: const [], snippet: 'text $id', unread: unread, error: false, archived: false, muted: muted);
  InboxChat chat(String id, int minutesAgo, {int unread = 0, bool muted = false}) =>
      InboxChat(network: 'telegram', id: id, title: id, date: noon.subtract(Duration(minutes: minutesAgo)), unread: unread, muted: muted);
  List<Object> ids(List<Object> rows) => [for (final r in rows) r is Conversation ? r.id : (r as InboxChat).id];

  test('unread conversations come first, the newest of them at the very top, and everything read after', () {
    // As the list is made: the newest first.
    final rows = <Object>[text(1, 1), text(2, 5, unread: true), chat('a', 9), chat('b', 20, unread: 3), text(3, 40), text(4, 90, unread: true)];
    expect(ids(unreadRowsFirst(rows)), [2, 'b', 4, 1, 'a', 3]);
    // A message that has just come is unread and the newest: it is first of all.
    final fresh = <Object>[text(9, 0, unread: true), ...rows];
    expect(ids(unreadRowsFirst(fresh)).first, 9);
  });

  test('nothing unread, or everything unread, leaves the order as it was', () {
    final read = <Object>[text(1, 1), chat('a', 9), text(3, 40)];
    expect(ids(unreadRowsFirst(read)), [1, 'a', 3]);
    final all = <Object>[text(1, 1, unread: true), chat('a', 9, unread: 1), text(3, 40, unread: true)];
    expect(ids(unreadRowsFirst(all)), [1, 'a', 3]);
    expect(unreadRowsFirst(const []), isEmpty);
  });

  test('a muted conversation is not brought up for what is said in it', () {
    expect(isUnreadRow(text(1, 1, unread: true)), isTrue);
    expect(isUnreadRow(text(1, 1, unread: true, muted: true)), isFalse);
    expect(isUnreadRow(chat('a', 1, unread: 2, muted: true)), isFalse);
    final rows = <Object>[text(1, 1), text(2, 5, unread: true, muted: true), text(3, 9, unread: true)];
    expect(ids(unreadRowsFirst(rows)), [3, 1, 2]);
  });
}
