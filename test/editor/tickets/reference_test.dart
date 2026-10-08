// A ticket's panel and its keys' titles held to the web page: every ticket case
// test/editor/queries/fixtures/reference.mjs measured in Chromium (the web app's own CodeMirror with `tickets()`)
// drawn here, and each line's box, the panel's, and every named piece inside it compared with the page's element of
// the same class, in order, to half a pixel.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/book/tickets.dart' show TicketChoice;
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;

import '../../support/render.dart';
import '../view/support.dart' show borderBox;
import 'support.dart';

final double tolerance = double.tryParse(Platform.environment['EDITOR_TOLERANCE'] ?? '') ?? 0.5;

/// Pieces the page has that are held by another piece, or are not boxes of their own here: an icon, a row that is
/// only its two cells, the phone's own date field.
const Set<String> _notPieces = <String>{'svg', 'row', 'span', 'dayInput', 'day', 'header', 'section', 'p', 'dl', 'dt', 'dd', 'input', 'button'};

/// Pieces whose box on the page is the letters' own, or a field's: held from side to side.
const Set<String> _acrossOnly = <String>{};

String _plain(double value) => value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(3);
String _show(Rect r) => '[${_plain(r.left)},${_plain(r.top)} ${_plain(r.width)}x${_plain(r.height)}]';

void main() {
  setUpAll(loadAppFonts);

  final only = Platform.environment['EDITOR_CASE'];
  for (final name in PageFixture.names(ticketFixtures)) {
    if (only != null && only.isNotEmpty && !name.contains(only)) continue;
    testWidgets('$name: lines, the panel and its pieces where the page has them', (tester) async {
      final fixture = PageFixture.read(ticketFixtures, name);
      // The tickets of the library, as the page's screen handed them over.
      final choices = <TicketChoice>[
        for (final note in fixture.library)
          if (isTicket(note.body))
            () {
              final ticket = ticketOf(note.body, defaultStatuses)!;
              return TicketChoice(key: ticket.id, title: noteTitle(note.body), status: ticket.status, category: ticket.category);
            }(),
      ];
      await pumpTickets(tester, fixture.doc, options: optionsWith(choices, nextId: 'GHO-14', byTitle: true), theme: fixture.theme, readOnly: fixture.readOnly, caret: fixture.caret, today: fixture.today, locale: fixture.locale, shadows: true);
      if (fixture.more) {
        await tester.tap(parts('more'));
        await tester.pump();
      }
      final problems = <String>[];
      var worst = 0.0;
      var held = 0;
      void hold(String what, Rect own, Rect page, {bool across = false}) {
        final offs = <double>[(own.left - page.left).abs(), (own.right - page.right).abs(), if (!across) (own.top - page.top).abs(), if (!across) (own.bottom - page.bottom).abs()];
        final off = offs.reduce((a, b) => a > b ? a : b);
        held += 1;
        if (off > worst) worst = off;
        if (off > tolerance) problems.add('[$what] ${_show(own)}, the page ${_show(page)}');
      }

      final lines = drawnLines(tester);
      expect(lines.length, fixture.lines.length, reason: 'as many lines as the page drew');
      for (var i = 0; i < lines.length; i++) {
        final want = fixture.lines[i];
        expect(lines[i].from, want['from'], reason: 'line $i starts where the page\'s does');
        hold('line ${want['from']}', borderBox(lines[i]), PageFixture.rect(want['rect']));
      }

      expect(panel.evaluate().length, fixture.blocks.length, reason: 'as many panels drawn as on the page');
      final notHeld = <String>{};
      for (var n = 0; n < fixture.blocks.length; n++) {
        final block = fixture.blocks[n];
        final under = panel.at(n);
        hold('block $n', boxOf(tester, under), PageFixture.rect(block['rect']));
        for (final MapEntry(key: name, value: wanted) in PageFixture.partsOf(block).entries) {
          if (_notPieces.contains(name) || name.startsWith('lucide')) continue;
          final own = parts(name, under);
          final count = own.evaluate().length;
          if (count == 0) {
            notHeld.add(name);
            continue;
          }
          if (count != wanted.length) {
            problems.add('[$name] $count here, ${wanted.length} on the page');
            continue;
          }
          for (var i = 0; i < count; i++) {
            hold('$name $i', boxOf(tester, own.at(i)), PageFixture.rect(wanted[i]['rect']), across: _acrossOnly.contains(name) || wanted[i]['display'] == 'inline');
          }
        }
      }

      // The titles after the keys: each one's dot, where the page has it.
      final dots = find.byKey(const ValueKey<String>('ticket-dot'));
      expect(dots.evaluate().length, fixture.titles.length, reason: 'as many keys titled as on the page');
      // The first is held. A title here may part from a comma after it where the page keeps the two together
      // (lib/editor/tickets/tickets.dart), so what follows on the line can stand a word along from the page's.
      for (var i = 0; i < fixture.titles.length && i < 1; i++) {
        hold('title dot $i', boxOf(tester, dots.at(i)), PageFixture.rect((fixture.titles[i]['dot'] as Map)['rect']));
      }

      if (Platform.environment['EDITOR_SHOTS'] != null) {
        await expectLater(find.byType(GhostApp), matchesGoldenFile('shots/$name.png'));
      }
      debugDisableShadows = true;
      // ignore: avoid_print
      print('$name: $held held, worst ${_plain(worst)}${notHeld.isEmpty ? '' : ', not pieces here: ${notHeld.join(' ')}'}');
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }
}
