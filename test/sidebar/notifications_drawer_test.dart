import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/preferences.dart' show NotificationPrefs;
import 'package:ghost_md/notes/notifications_drawer.dart';
import 'package:ghost_md/sheet/css.dart';
import 'package:glacier/glacier.dart';

import '../support/icons.dart';
import '../support/render.dart';
import 'support.dart';

/// The notifications' card under the bell (notes/notifications_drawer.dart): what it draws for a list of rows, what
/// each press tells its caller, the two things it says with nothing to show, where everything sits against the web
/// page, and the pictures.
void main() {
  setUpAll(loadAppFonts);
  final library = SidebarLibrary.load();

  final card = find.byKey(const ValueKey('floating-card'));
  Finder button(String label) => find.bySemanticsLabel(label);
  Finder rowOf(String id) => find.byKey(ValueKey('notification-$id'));

  /// The page with the drawer over it, and everything it tells its caller, in order.
  Future<List<String>> show(
    WidgetTester tester, {
    List<FeedNotification>? rows,
    NotificationPrefs prefs = const NotificationPrefs(),
    bool signedIn = true,
    bool localOnly = false,
    Set<String> memberOf = const {'o1'},
    NotificationDetails? Function(FeedNotification)? detailsOf,
    Future<String?> Function(String, bool)? onAnswerInvite,
    Widget? emptyArt,
    Size size = const Size(390, 844),
    String theme = 'light',
    bool bare = true,
  }) async {
    final said = <String>[];
    var open = true;
    await pumpPage(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PageUnder(
          onBell: () {
            said.add('bell');
            setState(() => open = !open);
          },
          children: [
            if (open)
              NotificationsDrawer(
                notifications: rows ?? library.notifications,
                prefs: prefs,
                signedIn: signedIn,
                localOnly: localOnly,
                memberOf: memberOf,
                detailsOf: detailsOf,
                now: library.now,
                emptyArt: emptyArt,
                onClose: () {
                  said.add('close');
                  setState(() => open = false);
                },
                onOpenNote: (id, at) => said.add('note $id${at == null ? '' : ' at $at'}'),
                onOpenOrganization: (id) => said.add('org $id'),
                onAccount: () => said.add('account'),
                onMarkRead: (id) => said.add('read $id'),
                onMarkAllRead: () => said.add('read all'),
                onHide: (id) => said.add('hide $id'),
                onHideAll: (ids) => said.add('hide ${ids.join(' ')}'),
                onAnswerInvite: onAnswerInvite,
                onOpened: () => said.add('opened'),
              ),
          ],
        ),
      ),
      size: size,
      theme: theme,
      bare: bare,
    );
    await settle(tester, 700);
    return said;
  }

  group('the notifications drawer', () {
    testWidgets('is the card at the right under the bell, a list of what happened, newest first', (tester) async {
      final handle = tester.ensureSemantics();
      final said = await show(tester);
      // Opened: the feed is taken again.
      expect(said, ['opened']);
      final node = tester.getSemantics(find.bySemanticsLabel('Notifications').first);
      expect(node.role, SemanticsRole.dialog);
      expect(tester.getRect(card).right, closeTo(390 - 13.39, 0.01));
      for (final sentence in [
        'sam invited you to Harbour Press',
        'ana joined Ghost',
        'Claude edited a note',
        'ali made you an admin of Ghost',
        'ali invited you to Ghost',
        'A note was kept twice',
        'Someone removed jo from A workshop with a name long enough to wrap onto the next line',
      ]) {
        expect(find.text(sentence), findsOneWidget, reason: sentence);
      }
      final tops = [for (final n in library.notifications) tester.getRect(rowOf(n.id)).top];
      expect(tops, [...tops]..sort());
      for (final when in ['4 min ago', '50 min ago', '3 hr ago', 'Yesterday', 'Friday', 'Thursday', 'September 26']) {
        expect(find.text(when), findsOneWidget, reason: when);
      }
      // How an invitation was answered, under its sentence.
      expect(find.descendant(of: rowOf('n5'), matching: find.text('Accepted')), findsOneWidget);
      // The count of unread, and the two words there is something for.
      expect(find.descendant(of: find.byKey(const ValueKey('notifications-count')), matching: find.text('2')), findsOneWidget);
      expect(find.text('Mark all read'), findsOneWidget);
      expect(find.text('Clear all'), findsOneWidget);
      handle.dispose();
      await away(tester);
    });

    testWidgets('marks an unread row with the ink and a dot, and each kind with its colour', (tester) async {
      await show(tester);
      final t = tester.element(card).tokens;
      Finder mark(String id) => find.descendant(of: rowOf(id), matching: find.byKey(const ValueKey('notification-mark')));
      AppIcon icon(String id) => tester.widget<AppIcon>(find.descendant(of: mark(id), matching: find.byType(AppIcon)));
      Color ground(String id) => (tester.widget<Container>(find.descendant(of: mark(id), matching: find.byType(Container)).first).decoration! as BoxDecoration).color!;
      Tokens hue(String name) => t.child(attrs: {'hue': name});
      // Unread: the ink, on a wash of its kind's colour, with the dot at the round's corner.
      expect([icon('n1').icon, icon('n1').color], [Lucide.mail, t.color('app-ink')]);
      expect(ground('n1'), hue('violet').colorOf('color-mix(in oklch, var(--app-space) 16%, transparent)'));
      expect(find.descendant(of: rowOf('n1'), matching: find.byKey(const ValueKey('notification-unread'))), findsOneWidget);
      expect(tester.widget<Text>(find.text('sam invited you to Harbour Press')).style!.fontWeight, FontWeight.w500);
      // Read: the kind's own colour, and no dot.
      expect([icon('n3').icon, icon('n3').color], [Lucide.penLine, hue('sea').color('app-space')]);
      expect([icon('n4').icon, icon('n4').color], [Lucide.crown, hue('amber').color('app-space')]);
      expect([icon('n6').icon, icon('n6').color], [Lucide.triangleAlert, hue('ember').color('app-space')]);
      expect([icon('n7').icon, icon('n7').color], [Lucide.userMinus, hue('rose').color('app-space')]);
      expect(find.descendant(of: rowOf('n3'), matching: find.byKey(const ValueKey('notification-unread'))), findsNothing);
      expect(tester.widget<Text>(find.text('Claude edited a note')).style!.color, t.color('app-ink-2'));
      await away(tester);
    });

    testWidgets('opens the organization a row is about, reading the row and closing behind it; a row about one the person is not in only reads', (tester) async {
      final said = await show(tester);
      said.clear();
      // n7's organization is not one the person is in.
      await tester.tap(find.textContaining('Someone removed jo'));
      await tester.pump();
      expect(said, isEmpty);
      // An invitation is answered on its own row, not opened.
      await tester.tap(find.text('sam invited you to Harbour Press'));
      await tester.pump();
      expect(said, ['read n1']);
      await tester.tap(find.text('ana joined Ghost'));
      await tester.pump();
      expect(said, ['read n1', 'read n2', 'close', 'org o1']);
      expect(card, findsNothing);
      await away(tester);
    });

    testWidgets('opens the note a sealed row is about once it has been opened: its words, the line Claude changed, and where', (tester) async {
      const edit = NotificationDetails(kind: 'note-edited', noteId: 'launch', title: 'Launch week', by: 'Claude', added: 2, removed: 1, first: '2. Book the venue for the tenth, not the ninth', at: 'l4');
      const kept = NotificationDetails(kind: 'sync-conflict', noteId: 'packing', title: 'Packing list');
      final said = await show(tester, detailsOf: (n) => n.id == 'n3' ? edit : (n.id == 'n6' ? kept : null));
      said.clear();
      expect(find.text('Claude edited Launch week · 3 lines changed'), findsOneWidget);
      final detail = find.text('2. Book the venue for the tenth, not the ninth');
      expect(tester.widget<Text>(detail).maxLines, 2);
      expect(find.text('Packing list was kept twice: both devices had changed it'), findsOneWidget);
      await tester.tap(find.text('Packing list was kept twice: both devices had changed it'));
      await tester.pump();
      // Read already, so not read again; a kept-twice note opens at its top.
      expect(said, ['close', 'note packing']);
      await tester.tap(find.byKey(const ValueKey('bell-icon')));
      await settle(tester, 700);
      said.clear();
      await tester.tap(find.text('Claude edited Launch week · 3 lines changed'));
      await tester.pump();
      expect(said, ['close', 'note launch at l4']);
      await away(tester);
    });

    testWidgets('marks all read, clears one row, and clears all but an invitation still waiting', (tester) async {
      final said = await show(tester);
      said.clear();
      await tester.tap(find.text('Mark all read'));
      expect(said, ['read all']);
      // An invitation waiting has no cross: its row is the one place to answer it.
      expect(button('Clear: sam invited you to Harbour Press'), findsNothing);
      await tester.tap(button('Clear: ana joined Ghost'));
      expect(said.last, 'hide n2');
      await tester.tap(find.text('Clear all'));
      expect(said.last, 'hide n2 n3 n4 n5 n6 n7');
      expect(card, findsOneWidget);
      await away(tester);
    });

    testWidgets('has no count and no Mark all read with nothing unread, and no Clear all with only an invitation waiting', (tester) async {
      await show(tester, rows: [for (final n in library.notifications) n.copyWith(readAt: () => 1)]);
      expect(find.byKey(const ValueKey('notifications-count')), findsNothing);
      expect(find.text('Mark all read'), findsNothing);
      expect(find.text('Clear all'), findsOneWidget);
      await show(tester, rows: [library.notifications[0]]);
      expect(find.text('Mark all read'), findsOneWidget);
      expect(find.text('Clear all'), findsNothing);
      await away(tester);
    });

    testWidgets('draws only what Settings left switched on, an invitation always', (tester) async {
      await show(tester, prefs: const NotificationPrefs(team: false, claude: false, conflicts: false));
      expect(find.text('sam invited you to Harbour Press'), findsOneWidget);
      expect(find.text('ali invited you to Ghost'), findsOneWidget);
      for (final gone in ['ana joined Ghost', 'Claude edited a note', 'ali made you an admin of Ghost', 'A note was kept twice']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      // The count is of what is drawn.
      expect(find.descendant(of: find.byKey(const ValueKey('notifications-count')), matching: find.text('1')), findsOneWidget);
      await show(tester, prefs: const NotificationPrefs(mutedOrgs: ['o1']));
      expect(find.text('ana joined Ghost'), findsNothing);
      expect(find.text('ali invited you to Ghost'), findsOneWidget);
      await away(tester);
    });

    testWidgets('carries Accept and Decline on an invitation: held dim while the answer is on its way, and the service’s words if it did not arrive', (tester) async {
      final answers = <(String, bool)>[];
      var arrives = Completer<String?>();
      final said = await show(
        tester,
        onAnswerInvite: (org, accept) {
          answers.add((org, accept));
          return arrives.future;
        },
      );
      said.clear();
      final t = tester.element(card).tokens;
      TextStyle word(String text) => tester.widget<Text>(find.text(text)).style!;
      // Accept in ink, Decline in the muted ink, at the page's own size.
      expect([word('Accept').color, word('Accept').fontWeight, word('Accept').fontSize], [t.color('app-ink'), FontWeight.w600, 16.0]);
      expect([word('Decline').color, word('Decline').fontWeight], [t.color('app-ink-2'), FontWeight.w500]);
      // Only the invitation still waiting has them.
      expect(find.text('Accept'), findsOneWidget);
      await tester.tap(find.text('Decline'));
      await tester.pump();
      expect(answers, [('o2', false)]);
      double dim() => tester.widget<Opacity>(find.ancestor(of: find.text('Accept'), matching: find.byType(Opacity)).first).opacity;
      expect(dim(), 0.5);
      // Not twice while the first is on its way.
      await tester.tap(find.text('Accept'));
      expect(answers, hasLength(1));
      arrives.complete('Not sent yet. It goes with the next sync.');
      await tester.pump();
      await tester.pump();
      expect(dim(), 1);
      expect(find.text('Not sent yet. It goes with the next sync.'), findsOneWidget);
      // Asked again, the words go until there is something to say.
      arrives = Completer<String?>();
      await tester.tap(find.text('Accept'));
      await tester.pump();
      expect(answers.last, ('o2', true));
      expect(find.text('Not sent yet. It goes with the next sync.'), findsNothing);
      arrives.complete(null);
      await tester.pump();
      await tester.pump();
      expect(find.text('Not sent yet. It goes with the next sync.'), findsNothing);
      // Answering is not opening: the drawer is still here, and nothing was read.
      expect(said, isEmpty);
      await away(tester);
    });

    testWidgets('closes on its cross, on a press outside, on Escape and the back gesture, and not on the bell, which is the bell’s', (tester) async {
      final said = await show(tester);
      said.clear();
      await tester.tap(button('Close notifications'));
      await tester.pump();
      expect(said, ['close']);
      await tester.tap(find.byKey(const ValueKey('bell-icon')));
      await settle(tester, 700);
      expect(said, ['close', 'bell', 'opened']);
      await tester.tap(find.byKey(const ValueKey('bell-icon')));
      await tester.pump();
      expect(said, ['close', 'bell', 'opened', 'bell']);
      expect(card, findsNothing);
      await tester.tap(find.byKey(const ValueKey('bell-icon')));
      await settle(tester, 700);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(said.last, 'close');
      await tester.tap(find.byKey(const ValueKey('bell-icon')));
      await settle(tester, 700);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(card, findsNothing);
      await tester.tap(find.byKey(const ValueKey('bell-icon')));
      await settle(tester, 700);
      await tester.tapAt(const Offset(195, 830));
      await tester.pump();
      expect(card, findsNothing);
      // The sidebar's icon is not this card's: a press there is a press outside.
      await tester.tap(find.byKey(const ValueKey('bell-icon')));
      await settle(tester, 700);
      await tester.tap(find.byKey(const ValueKey('sidebar-icon')), warnIfMissed: false);
      await tester.pump();
      expect(card, findsNothing);
      await away(tester);
    });

    testWidgets('lets each row rise in its turn, and none where less motion is asked for', (tester) async {
      await pumpPage(tester, PageUnder(children: [NotificationsDrawer(notifications: library.notifications, now: library.now, onClose: () {}, onOpenNote: (_, _) {}, onOpenOrganization: (_) {}, onAccount: () {})]));
      double shown(String id) => tester.widget<Opacity>(find.descendant(of: rowOf(id), matching: find.byType(Opacity)).first).opacity;
      // `animation: rowRise 260ms var(--glacier-ease-out) both; animation-delay: calc(var(--i, 0) * 24ms)`
      expect([shown('n1'), shown('n4')], [0, 0]);
      await tester.pump(const Duration(milliseconds: 60));
      expect(shown('n1'), greaterThan(shown('n2')));
      expect(shown('n4'), 0);
      await settle(tester, 500);
      expect([shown('n1'), shown('n7')], [1, 1]);
      await away(tester);

      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpPage(tester, PageUnder(children: [NotificationsDrawer(notifications: library.notifications, now: library.now, onClose: () {}, onOpenNote: (_, _) {}, onOpenOrganization: (_) {}, onAccount: () {})]));
      expect([shown('n1'), shown('n7')], [1, 1]);
      await away(tester);
    });

    testWidgets('hides a row’s cross until the row is pointed at, once there is a mouse to point with', (tester) async {
      await show(tester);
      double shown() => tester.widget<AnimatedOpacity>(find.descendant(of: rowOf('n2'), matching: find.byType(AnimatedOpacity))).opacity;
      expect(shown(), 1);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(100, 800));
      await tester.pump();
      expect(shown(), 0);
      await mouse.moveTo(tester.getCenter(find.text('ana joined Ghost')));
      await tester.pump();
      expect(shown(), 1);
      await mouse.removePointer();
      await away(tester);
    });
  });

  group('with nothing to show', () {
    testWidgets('signed out, says what notifications come with, and its word goes to Account', (tester) async {
      final said = await show(tester, signedIn: false);
      // Nothing holds a feed to take again.
      expect(said, isEmpty);
      expect(find.textContaining('Notifications come with an account: an invitation to a team, what Claude wrote, a meeting written up. Sign in under '), findsOneWidget);
      expect(find.text('Mark all read'), findsNothing);
      expect(find.text('sam invited you to Harbour Press'), findsNothing);
      final t = tester.element(card).tokens;
      final word = tester.widget<Text>(find.text('Account')).style!;
      expect([word.color, word.decoration, word.fontWeight], [t.color('app-ink'), TextDecoration.underline, FontWeight.w500]);
      await tester.tap(find.text('Account'));
      await tester.pump();
      expect(said, ['close', 'account']);
      await away(tester);
    });

    testWidgets('with Local only on, says so, and its word goes to Account too', (tester) async {
      final said = await show(tester, localOnly: true);
      expect(find.textContaining(' is on, so nothing arrives until it is off.'), findsOneWidget);
      await tester.tap(find.text('Local only'));
      await tester.pump();
      expect(said, ['close', 'account']);
      await away(tester);
    });

    testWidgets('with no rows, says nothing yet under whatever is drawn for it', (tester) async {
      await show(tester, rows: const [], emptyArt: const SizedBox(key: ValueKey('ghost'), width: 60, height: 80));
      final t = tester.element(card).tokens;
      final art = tester.getRect(find.byKey(const ValueKey('ghost')));
      final lead = tester.getRect(find.text('Nothing yet.'));
      final hint = tester.getRect(find.ancestor(of: find.textContaining('Invitations, what Claude wrote'), matching: find.byType(CssLines)));
      // Centred in the card; `.emptyArt`'s `margin-block-end` and the column's gap between the three.
      expect(art.center.dx, closeTo(tester.getRect(card).center.dx, 0.01));
      expect(lead.top, closeTo(art.bottom + t.space(2) + t.space(1), 0.01));
      expect(hint.top, closeTo(lead.bottom + t.space(1), 0.01));
      expect(find.byKey(const ValueKey('notifications-count')), findsNothing);
      expect(find.text('Clear all'), findsNothing);
      await away(tester);
    });
  });

  // What the web page measured at 390 x 844 (Chromium, getBoundingClientRect, 2026-10-07) with the same rows seeded
  // into its feed, a made-up session, and the network cut off. Left, top, width, height.
  group('where it sits', () {
    testWidgets('is the web page’s, to the half pixel', (tester) async {
      await show(tester);
      Rect lines(String text) => tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(CssLines)));
      Rect word(String text) => tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(GlacierPressable)).first);

      near(tester.getRect(card), [13.39, 55.34, 363.22, 649.22], what: 'the card');
      // The head: tall as its words' 53.55, over a hairline.
      near(tester.getRect(find.byKey(const ValueKey('notifications-head'))), [14.39, 56.34, 361.22, 81.33], what: 'the head');
      final title = tester.getRect(find.text('Notifications'));
      expect([title.left, title.top, title.height], [closeTo(32.23, 0.5), closeTo(86.5, 0.5), 20]);
      // On a phone the page's title has 96.97 of room and needs more: its count runs on under Mark all read.
      near(tester.getRect(find.byKey(const ValueKey('notifications-count'))), [134.86, 88.14, 16.69, 16.7], what: 'the count');
      near(word('Mark all read'), [138.13, 69.73, 102.67, 53.55], what: 'Mark all read');
      near(word('Clear all'), [249.72, 69.73, 71.58, 53.55], what: 'Clear all');
      near(tester.getRect(button('Close notifications')), [330.22, 80.5, 32, 32], what: 'the close');

      // An invitation: its mark, its sentence on one line, when, and Accept and Decline under the words.
      near(tester.getRect(rowOf('n1')), [23.31, 142.13, 343.38, 126.72], what: 'the invitation');
      near(tester.getRect(find.descendant(of: rowOf('n1'), matching: find.byKey(const ValueKey('notification-mark')))), [32.23, 155.52, 32, 32], what: 'its mark');
      near(lines('sam invited you to Harbour Press'), [77.63, 155.52, 214.78, 20.08], what: 'its sentence');
      // The page's box is 51.97 x 15.11 from 155.52 with 1.11 of padding over the words.
      near(tester.getRect(find.text('4 min ago')), [305.8, 155.52 + 1.11, 51.97, 14], what: 'when');
      near(word('Accept'), [77.63, 200.91, 54.81, 53.55], what: 'Accept');
      near(word('Decline'), [145.83, 200.91, 56.8, 53.55], what: 'Decline');

      // A row with a cross: the words give it room.
      near(tester.getRect(rowOf('n2')), [23.31, 268.84, 343.38, 59.78], what: 'a row');
      near(lines('ana joined Ghost'), [77.63, 282.23, 175.09, 20.08], what: 'its sentence');
      near(tester.getRect(find.text('50 min ago')), [266.11, 282.23 + 1.11, 59.19, 14], what: 'when');
      near(tester.getRect(button('Clear: ana joined Ghost')), [329.77, 277.77, 28, 28], what: 'its cross');
      near(tester.getRect(rowOf('n3')), [23.31, 328.63, 343.38, 59.78], what: 'the next');

      // A sentence on two lines, one with a line under it, and the last on four, with no rule under it.
      near(tester.getRect(rowOf('n4')), [23.31, 388.41, 343.38, 67.94], what: 'two lines');
      near(lines('ali made you an admin of Ghost'), [77.63, 401.8, 182.03, 40.16], what: 'its sentence');
      near(tester.getRect(rowOf('n5')), [23.31, 456.34, 343.38, 66.95], what: 'answered');
      near(lines('Accepted'), [77.63, 492.2, 201.88, 16.7], what: 'how');
      near(tester.getRect(rowOf('n6')), [23.31, 523.3, 343.38, 59.78], what: 'kept twice');
      near(tester.getRect(rowOf('n7')), [23.31, 583.08, 343.38, 107.09], what: 'the last');
      near(lines('Someone removed jo from A workshop with a name long enough to wrap onto the next line'), [77.63, 596.47, 159.14, 80.31], what: 'its sentence');
      near(tester.getRect(find.text('September 26')), [250.16, 596.47 + 1.11, 75.14, 14], what: 'when');
      await away(tester);
    });

    testWidgets('signed out, is the web page’s: a short card with three lines in it', (tester) async {
      await show(tester, signedIn: false);
      near(tester.getRect(card), [13.39, 55.34, 363.22, 166.64], what: 'the card');
      // No words in the head: it is as tall as the close.
      near(tester.getRect(find.byKey(const ValueKey('notifications-head'))), [14.39, 56.34, 361.22, 59.78], what: 'the head');
      near(tester.getRect(button('Close notifications')), [330.22, 69.73, 32, 32], what: 'the close');
      near(tester.getRect(find.byType(CssLines)), [32.23, 133.97, 325.53, 60.23], what: 'the words');
      final account = tester.getRect(find.text('Account'));
      expect([account.left, account.width], [closeTo(119.55, 0.5), closeTo(53.61, 0.5)]);
      expect(account.center.dy, closeTo(174.13 + 20.08 / 2, 1));
      await away(tester);
    });

    // At 1280 x 800 on a desktop the page's card is 416 wide, its far edge 15.8 from the window's; inside it (from the
    // card's own corner): the head 95.81 tall, the count 134.21, 39.83, Mark all read from 163.61, the close at
    // 367.21, 32.41, the invitation's row 11.53, 102.08, 392.94 x 143.61 with its sentence on one line.
    testWidgets('on a desktop is the web page’s, from the card’s own corner', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await show(tester, size: const Size(1280, 800));
      final at = tester.getRect(card);
      Rect inCard(Finder f) => tester.getRect(f).shift(-at.topLeft);
      expect([at.width, at.right], [416, closeTo(1280 - 15.8, 0.05)]);
      near(inCard(find.byKey(const ValueKey('notifications-head'))), [1, 1, 414, 95.81], what: 'the head');
      near(inCard(find.byKey(const ValueKey('notifications-count'))), [134.21, 39.83, 17.25, 17.16], what: 'the count');
      near(inCard(find.ancestor(of: find.text('Mark all read'), matching: find.byType(GlacierPressable)).first), [163.61, 16.8, 107.7, 63.22], what: 'Mark all read');
      near(inCard(button('Close notifications')), [367.21, 32.41, 32, 32], what: 'the close');
      near(inCard(rowOf('n1')), [11.53, 102.08, 392.94, 143.61], what: 'the invitation');
      near(inCard(find.ancestor(of: find.text('sam invited you to Harbour Press'), matching: find.byType(CssLines))), [69.86, 117.87, 254.91, 21.25], what: 'its sentence');
      near(inCard(find.ancestor(of: find.text('Accept'), matching: find.byType(GlacierPressable)).first), [69.86, 165.67, 54.81, 63.22], what: 'Accept');
      near(inCard(rowOf('n7')), [11.53, 577.45, 392.94, 116.59], what: 'the last');
      await away(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('the pictures', () {
    for (final theme in ['light', 'dark']) {
      for (final (name, size, desktop) in [('phone', const Size(390, 844), false), ('wide', const Size(1280, 800), true)]) {
        testWidgets('the rows, $name, $theme', (tester) async {
          if (desktop) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          TestGesture? mouse;
          if (desktop) {
            mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
            await mouse.addPointer(location: const Offset(200, 700));
          }
          await show(tester, size: size, theme: theme);
          await shot(tester, 'notifications-rows-$name-$theme');
          await mouse?.removePointer();
          debugDefaultTargetPlatformOverride = null;
        });

        testWidgets('signed out, $name, $theme', (tester) async {
          if (desktop) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          await show(tester, signedIn: false, size: size, theme: theme);
          await shot(tester, 'notifications-signed-out-$name-$theme');
          debugDefaultTargetPlatformOverride = null;
        });
      }

      testWidgets('nothing yet, phone, $theme', (tester) async {
        await show(tester, rows: const [], theme: theme);
        await shot(tester, 'notifications-empty-phone-$theme');
      });
    }
  });
}
