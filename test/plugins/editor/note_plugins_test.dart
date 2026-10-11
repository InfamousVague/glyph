// editor/notePlugins.test.ts, case for case, and the two functions over the registry it left untested there
// (`itemSend`, `lineOffers`), asked of a registry of this test's own with a stand-in plugin.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/note_plugins.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';

/// The note as plugins change it: through the editor, one line at a time and one undo each, reading the editor's
/// words when there is one and the screen's live body when there is not.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  EditorView view(String doc, [List<Extension> extensions = const <Extension>[]]) {
    final made = EditorView(state: EditorState.create(doc: doc, extensions: Extension.list(extensions)), wholeDocument: true);
    addTearDown(made.destroy);
    return made;
  }

  group('the note, as plugins change it', () {
    test('rewrites the first line it is asked for, and only that one, as one undo', () {
      final on = view('- [ ] milk\n- [ ] eggs\n- [ ] milk', <Extension>[history()]);
      final editing = noteEditing('n1', on, () => 'unused', (_) {});
      final seen = <int>[];
      final found = editing.replaceLine((text, line) {
        seen.add(line);
        return text.contains('milk');
      }, (text) => '$text [notion](https://notion.so/1)');
      expect(found, isTrue);
      expect(seen, <int>[1]);
      expect(on.state.doc.toString(), '- [ ] milk [notion](https://notion.so/1)\n- [ ] eggs\n- [ ] milk');
      undo(on);
      expect(on.state.doc.toString(), '- [ ] milk\n- [ ] eggs\n- [ ] milk');
    });

    test('answers false when no line is the one, and writes nothing', () {
      final on = view('- [ ] eggs');
      final editing = noteEditing('n1', on, () => 'unused', (_) {});
      expect(editing.replaceLine((_, _) => false, (_) => 'x'), isFalse);
      expect(on.state.doc.toString(), '- [ ] eggs');
    });

    test('reads the live body when no editor is drawn, and can change nothing then', () {
      final said = <String>[];
      final editing = noteEditing('n1', null, () => '{"nodes":[]}', said.add);
      expect(editing.body(), '{"nodes":[]}');
      expect(editing.replaceLine((_, _) => true, (_) => 'x'), isFalse);
      editing.say('Sent.');
      expect(said, <String>['Sent.']);
      expect(editing.noteId, 'n1');
    });
  });

  group('what the switched-on plugins offer on a note (not tested on the page)', () {
    final ran = <String>[];
    GlyphPlugin board() => GlyphPlugin(
      manifest: const PluginManifest(id: 'testboard', name: 'Testboard', description: 'Stands in.', version: '1', author: 'test', standard: true, permissions: <PluginPermission>[PluginPermission(Permission.notes, 'Sends items.')], storage: <String>[]),
      icon: 'square-kanban',
      itemAction: ItemAction(id: 'send', label: 'Send to Testboard', busyLabel: 'Sending…', available: (noteId) => noteId == 'n1', run: (text, editing) async => ran.add('${editing.noteId}: $text')),
      suggest: (noteId, body) => <Suggestion>[
        for (final (index, text) in body.split('\n').indexed)
          if (text.startsWith('- [ ] ')) Suggestion(line: index + 1, label: 'Testboard', busyLabel: 'Sending', run: (editing) async => ran.add('${editing.noteId} line ${index + 1}')),
      ],
    );

    test('the swipe’s action is the plugin’s own, run on the item’s words with this note; none where no plugin takes the note’s items, or it is off', () async {
      ran.clear();
      final registry = createRegistry(<GlyphPlugin>[board()], store: MemorySwitches());
      final editing = noteEditing('n1', null, () => '', (_) {});
      final action = itemSend('n1', editing, registry: registry)!;
      expect((action.label, action.busyLabel), ('Send to Testboard', 'Sending…'));
      await action.run('Buy milk');
      expect(ran, <String>['n1: Buy milk']);
      expect(itemSend('n2', noteEditing('n2', null, () => '', (_) {}), registry: registry), isNull);
      registry.setEnabled('testboard', false);
      expect(itemSend('n1', editing, registry: registry), isNull);
    });

    test('the words after lines are the plugins’ suggestions for the note as it reads now, each run with this note', () async {
      ran.clear();
      final registry = createRegistry(<GlyphPlugin>[board()], store: MemorySwitches());
      final editing = noteEditing('n1', null, () => '', (_) {});
      final offers = lineOffers('n1', editing, 'words\n- [ ] milk\n- [x] eggs\n- [ ] bread', registry: registry);
      expect(offers.map((offer) => (offer.line, offer.label, offer.busyLabel)), <(int, String, String)>[(2, 'Testboard', 'Sending'), (4, 'Testboard', 'Sending')]);
      await offers.last.run();
      expect(ran, <String>['n1 line 4']);
      registry.setEnabled('testboard', false);
      expect(lineOffers('n1', editing, '- [ ] milk', registry: registry), isEmpty);
    });
  });
}
