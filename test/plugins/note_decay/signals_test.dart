// Note decay alerts' cheap layer (lib/plugins/note_decay/signals.dart, dates.dart, dismissals.dart; docs/NOTE_DECAY.md
// §1.1; Matt, 2026-11-02: "docs and pages that reference things that have since changed (a renamed ticket, a merged
// PR on GitHub, an old date) get a quiet 'may be out of date' mark with the reason"): each signal and its reason, the
// words that look ahead and back, and Still right kept until the source changes again. No network: GitHub and
// Figma's answers are a fake's.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/note_decay/dates.dart';
import 'package:ghost_md/plugins/note_decay/dismissals.dart';
import 'package:ghost_md/plugins/note_decay/lookups.dart';
import 'package:ghost_md/plugins/note_decay/signals.dart';

final DateTime now = DateTime(2026, 11, 2, 10);

DecayNote page(String body, {String id = 'page', String? title, DateTime? edited, bool docPage = false, bool trashed = false, bool archived = false}) =>
    DecayNote(id: id, title: title ?? body.split('\n').firstWhere((l) => l.startsWith('# '), orElse: () => '# $id').substring(2), body: body, edited: edited ?? DateTime(2026, 10, 20), docPage: docPage, trashed: trashed, archived: archived);

String ticket(String key, String status, {String? done}) => '---\ntype: ticket\nid: $key\nstatus: $status${done == null ? '' : '\ndone: $done'}\n---\n# The $key ticket\n';

/// GitHub and Figma as a test says they answer.
class FakeLookups implements DecayLookups {
  FakeLookups({this.githubOn = true, this.figmaOn = true, this.states = const {}, this.gone = const {}});
  @override
  final bool githubOn;
  @override
  final bool figmaOn;
  final Map<String, GithubState> states;
  final Set<String> gone;
  final List<String> asked = [];

  @override
  Future<GithubState?> github(GithubRef ref) async {
    asked.add(ref.key);
    return states[ref.key];
  }

  @override
  Future<bool?> figmaGone(String url) async {
    asked.add(url);
    return gone.contains(url);
  }
}

void main() {
  group('dates', () {
    test('are read in their usual shapes, the year from the edit where none is written', () {
      final edited = DateTime(2026, 10, 20);
      final found = datesIn('Ships Nov 1, then 2026-12-03, then 4th January, and Sept 9 2025.', edited: edited);
      expect([for (final f in found) (f.text, f.day)], [
        ('Nov 1', DateTime(2026, 11, 1)),
        ('2026-12-03', DateTime(2026, 12, 3)),
        ('4th January', DateTime(2027, 1, 4)),
        ('Sept 9 2025', DateTime(2025, 9, 9)),
      ]);
      // A day that is no day is no date.
      expect(datesIn('Feb 30 and 2026-13-01', edited: edited), isEmpty);
    });

    test('a sentence looks ahead by its words, and never with a word that looks back', () {
      for (final ahead in ['Billing ships on Nov 1.', 'We will launch Nov 1', 'It is due Nov 1', 'Planned for Nov 1', 'We\'ll have it by Nov 1', 'Beta goes live Nov 1', 'Scheduled for Nov 1']) {
        expect(looksAhead(ahead), isTrue, reason: ahead);
      }
      for (final behind in ['Billing shipped on Nov 1.', 'It was due Nov 1', 'We launched Nov 1', 'Done on Nov 1', 'Nov 1: the meeting happened', 'Nov 1, a Sunday']) {
        expect(looksAhead(behind), isFalse, reason: behind);
      }
    });

    test('the sentence round a date is its own, not the line’s', () {
      const line = 'Billing shipped last week. The import will land Nov. 1.';
      expect(sentenceAt(line, line.indexOf('Nov')), 'The import will land Nov. 1.');
      expect(sentenceAt(line, line.indexOf('week')), 'Billing shipped last week.');
      expect(looksAhead(sentenceAt(line, line.indexOf('Nov'))), isTrue);
    });
  });

  group('the signals', () {
    test('a link to a note renamed says what it is called now', () {
      final library = DecayLibrary([page('# Plan\nSee [[Spec]] for the shape.'), page('# Spec v2\nThe spec.', id: 'spec')], renamed: {'Spec': 'Spec v2'});
      final signals = signalsOf(library.notes.first, library, now: now);
      expect(signals, hasLength(1));
      expect((signals.single.kind, signals.single.reason, signals.single.line, signals.single.source), (DecayKind.link, '[[Spec]] was renamed to [[Spec v2]]', 1, 'spec'));
      // Renamed twice, the newest name.
      final twice = DecayLibrary([page('# Plan\nSee [[Spec]].'), page('# Spec v3', id: 'spec')], renamed: {'Spec': 'Spec v2', 'spec v2': 'Spec v3'});
      expect(signalsOf(twice.notes.first, twice, now: now).single.reason, '[[Spec]] was renamed to [[Spec v3]]');
      // A link to no note, and one never renamed, is a page still to write, not decay.
      final none = DecayLibrary([page('# Plan\nSee [[Someday]].')]);
      expect(signalsOf(none.notes.first, none, now: now), isEmpty);
    });

    test('a link to a note in the trash or archived says so', () {
      final library = DecayLibrary([
        page('# Plan\nSee [[Old]] and [[Kept]].'),
        page('# Old', id: 'old', trashed: true),
        page('# Kept', id: 'kept', archived: true),
      ]);
      expect([for (final s in signalsOf(library.notes.first, library, now: now)) s.reason], ['[[Old]] is in the trash', '[[Kept]] was archived']);
    });

    test('a ticket closed since the page was edited says when, in its own word', () {
      final library = DecayLibrary([
        page('# Plan\n- Billing waits on [[GHO-12]]\n- Import after GHO-13\n- Search, [[GHO-14]]\n- Old [[GHO-15]]'),
        page(ticket('GHO-12', 'Done', done: '2026-10-30'), id: 't12'),
        page(ticket('GHO-13', 'Shipped', done: '2026-10-25'), id: 't13'),
        page(ticket('GHO-14', 'In progress'), id: 't14'),
        // Closed before the page was last edited: the page was written knowing it.
        page(ticket('GHO-15', 'Done', done: '2026-10-01'), id: 't15'),
      ]);
      final signals = signalsOf(library.notes.first, library, now: now);
      expect([for (final s in signals) (s.kind, s.key, s.line, s.reason)], [
        (DecayKind.ticket, 'GHO-12', 1, 'GHO-12 was closed on Oct 30'),
        (DecayKind.ticket, 'GHO-13', 2, 'GHO-13 was marked Shipped on Oct 25'),
      ]);
      expect(signals.first.stamp, 'Done 2026-10-30');
    });

    test('a date the page speaks of as ahead, now past, is marked; one ahead still, or spoken of as past, is not', () {
      final library = DecayLibrary([page('# Launch\nBilling ships on Nov 1.\nSearch ships on Nov 20.\nImport shipped on Oct 28.\n```\nships Oct 1\n```')]);
      final signals = signalsOf(library.notes.first, library, now: now);
      expect([for (final s in signals) (s.kind, s.line, s.reason)], [(DecayKind.date, 1, 'Nov 1 has passed; this still speaks of it as ahead')]);
    });

    test('a docs page unedited for months, while pages it links changed, is marked at its head', () {
      final library = DecayLibrary([
        page('# Billing\nSee [[Pricing]] and [[Plans]] and [[Quiet]].', edited: DateTime(2026, 6, 2), docPage: true),
        page('# Pricing', id: 'pricing', edited: DateTime(2026, 10, 1)),
        page('# Plans', id: 'plans', edited: DateTime(2026, 9, 1)),
        page('# Quiet', id: 'quiet', edited: DateTime(2026, 5, 1)),
      ]);
      final signals = signalsOf(library.notes.first, library, now: now);
      expect([for (final s in signals) (s.kind, s.line, s.reason, s.stamp)], [(DecayKind.stale, null, 'Not edited since Jun 2, and [[Pricing]] and [[Plans]] changed since', '2026-10-01')]);
      // Not a docs page, or not old enough for the months chosen, is not asked.
      expect(signalsOf(page(library.notes.first.body, edited: DateTime(2026, 6, 2)), library, now: now), isEmpty);
      expect(signalsOf(library.notes.first, library, now: now, staleMonths: 6), isEmpty);
    });

    test('a pull request merged, an issue closed and a Figma frame gone come from the lookups', () async {
      final note = page('# Release\n- https://github.com/acme/app/pull/12\n- https://github.com/acme/app/issues/40\n- https://github.com/acme/app/pull/13\n- https://www.figma.com/design/AbC123/Home?node-id=1-2');
      final lookups = FakeLookups(states: {
        'acme/app#12': GithubState(GithubStateKind.merged, at: DateTime(2026, 10, 30, 12)),
        'acme/app#40': GithubState(GithubStateKind.closed, at: DateTime(2026, 10, 31, 9)),
        'acme/app#13': const GithubState(GithubStateKind.open),
      }, gone: {'https://www.figma.com/design/AbC123/Home?node-id=1-2'});
      final signals = await remoteSignalsOf(note, lookups, now: now);
      expect([for (final s in signals) (s.kind, s.line, s.reason)], [
        (DecayKind.github, 1, 'PR #12 in acme/app was merged on Oct 30'),
        (DecayKind.github, 2, 'Issue #40 in acme/app was closed on Oct 31'),
        (DecayKind.figma, 4, 'The Figma frame this links to is gone'),
      ]);
    });

    test('with the lookups off (Local only) nothing outside the phone is asked', () async {
      final note = page('# Release\nhttps://github.com/acme/app/pull/12\nhttps://www.figma.com/design/AbC123/Home');
      final lookups = FakeLookups(githubOn: false, figmaOn: false, states: {'acme/app#12': const GithubState(GithubStateKind.merged)});
      expect(await remoteSignalsOf(note, lookups, now: now), isEmpty);
      expect(lookups.asked, isEmpty);
      expect(await remoteSignalsOf(note, const NoDecayLookups(), now: now), isEmpty);
    });

    test('the app’s lookups keep an answer an hour and ask nothing while off', () async {
      var on = true;
      var clock = now;
      final asked = <String>[];
      final lookups = AppDecayLookups(
        githubOn: () => on,
        figmaOn: () => on,
        askGithub: (ref) async {
          asked.add(ref.key);
          return const GithubState(GithubStateKind.open);
        },
        askFigma: (url) async => false,
        clock: () => clock,
      );
      const ref = GithubRef(owner: 'acme', repo: 'app', pull: true, number: 12);
      await lookups.github(ref);
      await lookups.github(ref);
      expect(asked, ['acme/app#12']);
      clock = clock.add(const Duration(minutes: 61));
      await lookups.github(ref);
      expect(asked, hasLength(2));
      on = false;
      expect(await lookups.github(ref), isNull);
      expect(asked, hasLength(2));
    });
  });

  group('Still right', () {
    test('is kept in the page’s front matter and holds until the source changes again', () {
      final first = DecayLibrary([page('# Plan\nWaits on [[GHO-12]]'), page(ticket('GHO-12', 'Done', done: '2026-10-30'), id: 't')]);
      final signal = signalsOf(first.notes.first, first, now: now).single;
      final body = withStillRight(first.notes.first.body, signal);
      expect(body, startsWith('---\ndecay-ok: [ticket:GHO-12@Done 2026-10-30]\n---\n'));
      expect(withoutStillRight(body, [signal]), isEmpty);
      // The ticket reopened and closed again on another day: its stamp differs, and the mark is back.
      final again = DecayLibrary([page(body), page(ticket('GHO-12', 'Done', done: '2026-11-01'), id: 't')]);
      final back = signalsOf(again.notes.first, again, now: now);
      expect(withoutStillRight(body, back), hasLength(1));
      // Kept again, the older token goes: one a signal.
      final twice = withStillRight(body, back.single);
      expect(stillRightIn(twice), {'ticket:GHO-12@Done 2026-11-01'});
    });

    test('keeps the page’s own front matter as it was', () {
      const body = '---\ntype: docs page\nicon: book\n---\n# Plan\nShips Nov 1.';
      final note = page(body);
      final signal = signalsOf(note, DecayLibrary([note]), now: now).single;
      final kept = withStillRight(body, signal);
      expect(kept, contains('type: docs page\nicon: book\n'));
      expect(kept, endsWith('---\n# Plan\nShips Nov 1.'));
      expect(withoutStillRight(kept, signalsOf(page(kept), DecayLibrary([page(kept)]), now: now)), isEmpty);
    });
  });
}
