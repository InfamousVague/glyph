import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/mark_details.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart' show GlyphPlugin;

import 'support.dart';

/// What an item's mark links to, read back (lib/plugins/mark_details.dart), case for case from
/// `src/app/core/markDetails.test.ts`: the editor asks by the mark's name and address, and the plugin that owns the
/// name answers through the provider it registered. Nothing there knows a plugin, so a test registers its own.
///
/// What differs from the web's cases: a provider is a class here, so "one whose `reads` is undefined" is one that
/// keeps the class's own answer (no). The last group is the registry's side of it, which the page had no case for.

const MarkEntry loading = MarkLoading();

/// A provider for links under `https://tasks.test/`, and what it was asked.
class _Tasks extends MarkDetailsProvider {
  _Tasks({this.under = 'https://tasks.test/'});
  final String under;
  final List<(String, bool)> wanted = [];
  final List<String> opened = [];

  @override
  MarkEntry? peek(String url) => url.contains('known') ? loading : null;

  @override
  void want(String url, {bool fresh = false}) => wanted.add((url, fresh));

  @override
  Future<void> open(String url) async => opened.add(url);

  @override
  bool reads(String url) => url.startsWith(under);

  @override
  List<MarkAction> actions(String url, String words) => [MarkAction(id: 'done', label: 'Mark $words done', icon: MarkActionIcon.done, busyLabel: 'Marking done…', run: () async => url)];
}

/// One that says nothing of ordinary links or of what can be done.
class _Silent extends MarkDetailsProvider {
  @override
  MarkEntry? peek(String url) => null;

  @override
  void want(String url, {bool fresh = false}) {}

  @override
  Future<void> open(String url) async {}
}

void main() {
  setUp(forgetMarkProviders);
  tearDown(forgetMarkProviders);

  group('a mark’s details', () {
    test('are asked of the provider registered for the mark’s name, whatever its case', () async {
      final tasks = _Tasks();
      provideMarkDetails('Tasks', () => tasks);
      expect(hasMarkDetails('tasks'), isTrue);
      expect(peekMarkDetails('TASKS', 'https://tasks.test/known'), same(loading));
      expect(peekMarkDetails('tasks', 'https://tasks.test/other'), isNull);
      wantMarkDetails('tasks', 'https://tasks.test/known');
      wantMarkDetails('tasks', 'https://tasks.test/known', fresh: true);
      expect(tasks.wanted, [('https://tasks.test/known', false), ('https://tasks.test/known', true)]);
      await openMarked('tasks', 'https://tasks.test/known');
      expect(tasks.opened, ['https://tasks.test/known']);
      expect([for (final action in markActions('tasks', 'https://tasks.test/known', 'Buy milk')) action.label], ['Mark Buy milk done']);
    });

    test('are nothing for a mark no plugin answers, or one whose plugin is off', () async {
      provideMarkDetails('switched-off', () => null);
      for (final name in ['nobody', 'switched-off']) {
        expect(hasMarkDetails(name), isFalse);
        expect(peekMarkDetails(name, 'https://tasks.test/known'), isNull);
        expect(markActions(name, 'https://tasks.test/known', 'x'), isEmpty);
        expect(() => wantMarkDetails(name, 'https://tasks.test/known'), returnsNormally);
        await expectLater(openMarked(name, 'https://tasks.test/known'), completes);
      }
    });

    test('are found for an ordinary link a provider reads, written the old way or pasted into a sentence', () {
      provideMarkDetails('reader', () => _Tasks(under: 'https://reader.test/'));
      provideMarkDetails('silent', _Silent.new);
      expect(markNameFor('https://reader.test/abc'), 'reader');
      expect(markNameFor('https://elsewhere.test/abc'), isNull);
      expect(markActions('silent', 'https://reader.test/abc', 'x'), isEmpty);
    });

    test('tell every pill and card to read again when a provider has something new, until they stop listening', () {
      var heard = 0;
      final stop = onMarkDetails(() => heard++);
      markDetailsChanged();
      markDetailsChanged();
      expect(heard, 2);
      stop();
      markDetailsChanged();
      expect(heard, 2);
      // The same changes, for a widget that listens.
      var seen = 0;
      void see() => seen++;
      markDetailsListenable.addListener(see);
      markDetailsChanged();
      markDetailsListenable.removeListener(see);
      expect(seen, 1);
    });
  });

  group('how long ago', () {
    test('is said as a person says it', () {
      const now = 10 * 24 * 60 * 60000;
      expect(agoText(now - 30000, now), 'just now');
      expect(agoText(now + 60000, now), 'just now');
      expect(agoText(now - 3 * 60000, now), '3 min ago');
      expect(agoText(now - 5 * 60 * 60000, now), '5 hr ago');
      expect(agoText(now - 24 * 60 * 60000, now), 'yesterday');
      expect(agoText(now - 3 * 24 * 60 * 60000, now), '3 days ago');
    });
  });

  // ---- not on the page ---------------------------------------------------------------------------------------------

  group('a plugin’s marks, through the registry', () {
    test('are answered by the plugin whose id is the mark’s name, and by nobody while it is switched off', () {
      final tasks = _Tasks();
      final registry = createRegistry([GlyphPlugin(manifest: manifestOf('tasks'), icon: 'puzzle', marks: tasks)], store: MemorySwitches());
      var heard = 0;
      final stop = onMarkDetails(() => heard++);
      addTearDown(stop);
      expect(hasMarkDetails('tasks'), isTrue);
      expect(markNameFor('https://tasks.test/1'), 'tasks');
      registry.setEnabled('tasks', false);
      expect(heard, 1, reason: 'a switch tells the pills to read again');
      expect(hasMarkDetails('tasks'), isFalse);
      expect(peekMarkDetails('tasks', 'https://tasks.test/known'), isNull);
      expect(markNameFor('https://tasks.test/1'), isNull);
      registry.setEnabled('tasks', true);
      expect(peekMarkDetails('tasks', 'https://tasks.test/known'), same(loading));
    });
  });

  group('what is kept of an answer', () {
    const details = MarkDetails(
      url: 'https://tasks.test/1',
      title: 'Buy milk',
      status: MarkStatus('In progress', Stage.doing),
      brief: ['P1', 'Due Sep 20'],
      fields: [MarkField('Priority', 'P1')],
      editedAt: 1000,
      readAt: 2000,
    );

    test('is the page’s own shape, with gone said only when it is', () {
      expect(details.toJson(), {
        'url': 'https://tasks.test/1',
        'title': 'Buy milk',
        'status': {'label': 'In progress', 'stage': 'doing'},
        'brief': ['P1', 'Due Sep 20'],
        'fields': [
          {'label': 'Priority', 'value': 'P1'},
        ],
        'editedAt': 1000,
        'readAt': 2000,
      });
      expect(details.copyWith(gone: true).toJson()['gone'], isTrue);
    });

    test('reads back as it was written, and as nothing from another shape', () {
      final back = MarkDetails.fromJson(details.copyWith(gone: true).toJson())!;
      expect((back.url, back.title, back.status, back.editedAt, back.readAt, back.gone), ('https://tasks.test/1', 'Buy milk', const MarkStatus('In progress', Stage.doing), 1000, 2000, true));
      expect(back.brief, ['P1', 'Due Sep 20']);
      expect(back.fields, [const MarkField('Priority', 'P1')]);
      expect(MarkDetails.fromJson({'title': 7}), isNull);
      expect(MarkDetails.fromJson(null), isNull);
      expect(MarkDetails.fromJson({'url': 'u', 'title': 't', 'readAt': 1, 'status': {'label': 'Odd', 'stage': 'sideways'}})!.status, isNull);
      expect(details.copyWith(clearStatus: true).status, isNull);
      expect(stageNamed('done'), Stage.done);
      expect(stageNamed('later'), isNull);
    });
  });
}
