import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/notifications.dart' show FeedNotification;
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/reach.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/plugins/types.dart';

import 'support.dart';

/// The registry (lib/plugins/registry.dart), case for case from `src/app/plugins/registry.test.ts`. That file's
/// "a plugin's host" cases are host_test.dart, beside the rest of the host.
///
/// What differs from the web's cases:
/// - Local only is the `localOnly` the registry is made with and [Registry.preferencesChanged], where the page's
///   registry listened to the preferences itself.
/// - "ships Notion, GitHub, Marks and Claude as standard…" is held over the stand-ins made from the web's manifests
///   (support.dart `webBuiltIn`): lib/plugins/built_in.dart is the lead's and is not written yet, and its own test
///   has to hold the real list to the same table.
/// - The secrets a reset forgets and the feed's rows have no case on the page; theirs are at the end.

final Matcher throwsPermission = throwsA(isA<PluginPermissionError>());
Matcher throwsArgument(Pattern words) => throwsA(isA<ArgumentError>().having((e) => '${e.message}', 'message', matches(words)));

List<String> ids(Iterable<GlyphPlugin> plugins) => [for (final p in plugins) p.manifest.id];

void main() {
  group('the plugin registry', () {
    final linked = GlyphPlugin(
      manifest: manifestOf('linked'),
      icon: 'puzzle',
      formatContext: FormatContext(forNote: (id) => id == 'n1' ? 'Briefing one.' : null, version: (id) => id == 'n1' ? 42 : 0),
    );
    final optional = GlyphPlugin(
      manifest: manifestOf('optional', standard: false, storage: ['glyph-optional']),
      icon: 'puzzle',
      formatContext: FormatContext(forNote: (_) => 'Briefing two.', version: (_) => 7),
    );

    test('has standard plugins on and others off until switched', () {
      final registry = createRegistry([linked, optional], store: MemorySwitches());
      expect(ids(registry.enabled()), ['linked']);
    });

    test('keeps a switch, tells listeners, and offers nothing from a plugin that is off', () {
      final store = MemorySwitches();
      final registry = createRegistry([linked, optional], store: store);
      var heard = 0;
      registry.subscribe(() => heard++);
      registry.setEnabled('linked', false);
      registry.setEnabled('optional', true);
      expect(store.held, {'linked': false, 'optional': true});
      expect(heard, 2);
      expect(registry.contextFor('n1'), 'Briefing two.');
    });

    test('gives one plugin’s context version as it is, so notes formatted before plugins stay formatted', () {
      final registry = createRegistry([linked, optional], store: MemorySwitches());
      expect(registry.contextFor('n1'), 'Briefing one.');
      expect(registry.contextVersion('n1'), 42);
      expect(registry.contextVersion('n2'), 0);
      registry.setEnabled('optional', true);
      expect(registry.contextFor('n1'), 'Briefing one.\n\nBriefing two.');
      expect(registry.contextVersion('n1'), isNot(42));
      // As the page folds them: ((7 * 31 + 42) * 31 + 7) % 2^52.
      expect(registry.contextVersion('n1'), (7 * 31 + 42) * 31 + 7);
    });

    test('refuses a plugin whose extension points go past its manifest', () {
      final noisy = GlyphPlugin(manifest: manifestOf('noisy'), icon: 'puzzle', suggest: (_, _) => const []);
      expect(() => createRegistry([noisy], store: MemorySwitches()), throwsPermission);
      final editor = GlyphPlugin(
        manifest: manifestOf('editor', permissions: [Permission.network]),
        icon: 'puzzle',
        itemAction: ItemAction(id: 'x', label: 'X', busyLabel: 'X…', available: (_) => true, run: (_, _) async {}),
      );
      expect(() => createRegistry([editor], store: MemorySwitches()), throwsA(isA<PluginPermissionError>().having((e) => e.message, 'message', contains('“notes” permission'))));
    });

    test('refuses two plugins with one id', () {
      expect(() => createRegistry([linked, linked], store: MemorySwitches()), throwsArgument('Two plugins'));
    });

    test('lists every plugin’s storage for a reset, switched on or not', () {
      expect(createRegistry([linked, optional], store: MemorySwitches()).storageKeys(), ['glyph-plugins', 'glyph-optional']);
    });

    test('ships Notion, GitHub, Marks and Claude as standard, and Slack off until switched on, each within its manifest', () {
      final builtIn = webBuiltIn();
      expect([for (final p in builtIn) (p.manifest.id, p.manifest.standard)], [('notion', true), ('github', true), ('marks', true), ('claude', true), ('slack', false)]);
      for (final plugin in builtIn) {
        if (plugin.manifest.native != null) expect(plugin.manifest.declares(Permission.native), isTrue, reason: plugin.manifest.id);
        if (plugin.manifest.hosts.isNotEmpty) expect(plugin.manifest.declares(Permission.network), isTrue, reason: plugin.manifest.id);
      }
      // And they load: nothing among them reaches past its manifest.
      expect(ids(createRegistry(builtIn, store: MemorySwitches()).enabled()), ['notion', 'github', 'marks', 'claude']);
    });
  });

  group('what plugins offer on a note’s lines', () {
    final offering = GlyphPlugin(
      manifest: manifestOf('offering', permissions: [Permission.notes]),
      icon: 'puzzle',
      suggest: (noteId, body) => noteId == 'n1' && body.contains('- [ ]') ? [Suggestion(line: 1, label: 'Notion', busyLabel: 'Sending', run: (_) async {})] : const [],
    );
    final quiet = GlyphPlugin(
      manifest: manifestOf('quiet', standard: false, permissions: [Permission.notes]),
      icon: 'puzzle',
      suggest: (_, _) => [Suggestion(line: 2, label: 'Quiet', busyLabel: 'Quiet', run: (_) async {})],
    );

    test('gathers the words of the switched-on plugins for the note as it stands', () {
      final registry = createRegistry([offering, quiet], store: MemorySwitches());
      expect([for (final s in registry.suggestions('n1', '- [ ] milk')) s.label], ['Notion']);
      expect(registry.suggestions('n1', 'plain'), isEmpty);
      expect(registry.suggestions('n2', '- [ ] milk'), isEmpty);
    });

    test('refuses a plugin that offers words without the notes permission', () {
      final overreach = GlyphPlugin(manifest: manifestOf('overreach'), icon: 'puzzle', suggest: (_, _) => const []);
      expect(() => createRegistry([overreach], store: MemorySwitches()), throwsPermission);
    });
  });

  group('Local only', () {
    final online = GlyphPlugin(manifest: manifestOf('online', permissions: [Permission.network], hosts: ['api.example']), icon: 'puzzle');
    final offline = GlyphPlugin(manifest: manifestOf('offline'), icon: 'puzzle');

    test('turns off every plugin that uses the network, and tells listeners, until it is turned off again', () {
      var localOnly = false;
      final registry = createRegistry([online, offline], store: MemorySwitches(), localOnly: () => localOnly);
      var heard = 0;
      registry.subscribe(() => heard++);
      expect(ids(registry.enabled()), ['online', 'offline']);
      localOnly = true;
      registry.preferencesChanged();
      expect(ids(registry.enabled()), ['offline']);
      expect(registry.isEnabled('online'), isFalse);
      expect(heard, greaterThan(0));
      localOnly = false;
      registry.preferencesChanged();
      expect(ids(registry.enabled()), ['online', 'offline']);
    });

    test('holds a plugin off whatever its switch says, and keeps the switch for when it is off again', () {
      var localOnly = true;
      final store = MemorySwitches({'online': true});
      final registry = createRegistry([online, offline], store: store, localOnly: () => localOnly);
      expect(registry.isEnabled('online'), isFalse);
      // Switching it on while it is held changes nothing that can be seen, and the switch is kept as asked.
      registry.setEnabled('online', true);
      expect(registry.isEnabled('online'), isFalse);
      localOnly = false;
      registry.preferencesChanged();
      expect(registry.isEnabled('online'), isTrue);
      expect(usesNetwork(online.manifest), isTrue);
      expect(usesNetwork(offline.manifest), isFalse);
    });
  });

  group('what a note is linked to', () {
    final boards = GlyphPlugin(manifest: manifestOf('boards'), icon: 'puzzle', noteLinks: [linkOf('board', 'Board', (id) => id == 'n1' ? 'Ghost.md Tasks' : null)]);
    final repos = GlyphPlugin(manifest: manifestOf('repos', standard: false), icon: 'puzzle', noteLinks: [linkOf('repo', 'Repo', (_) => 'attackfm/app')]);

    test('names each link from every switched-on plugin, and nothing for a note without one', () {
      final registry = createRegistry([boards, repos], store: MemorySwitches({'repos': true}));
      expect([for (final l in registry.linksOf('n1')) '${l.link.label}: ${l.name}'], ['Board: Ghost.md Tasks', 'Repo: attackfm/app']);
      expect([for (final l in registry.linksOf('n2')) l.name], ['attackfm/app']);
      registry.setEnabled('repos', false);
      expect(registry.linksOf('n2'), isEmpty);
    });

    test('offers the formattings of switched-on plugins only, and refuses a delimiter Markdown already uses', () {
      final shout = GlyphPlugin(manifest: manifestOf('shout'), icon: 'puzzle', formats: const [GlyphFormat(name: 'Shout', delimiter: '==', look: StyleLook('text-transform: uppercase'))]);
      final registry = createRegistry([shout], store: MemorySwitches());
      expect([for (final f in registry.formats()) f.name], ['Shout']);
      registry.setEnabled('shout', false);
      expect(registry.formats(), isEmpty);
      final bold = GlyphPlugin(manifest: manifestOf('bold'), icon: 'puzzle', formats: const [GlyphFormat(name: 'Louder', delimiter: '**', look: WispLook())]);
      expect(() => createRegistry([bold], store: MemorySwitches()), throwsArgument('delimiter'));
      final lower = GlyphPlugin(manifest: manifestOf('lower'), icon: 'puzzle', formats: const [GlyphFormat(name: 'shout', delimiter: '==', look: WispLook())]);
      expect(() => createRegistry([lower], store: MemorySwitches()), throwsArgument('capitalised'));
    });

    test('takes an emoji twice as an effect’s delimiter, and not once, three times, or an emoji with words', () {
      GlyphPlugin effect(String delimiter) => GlyphPlugin(manifest: manifestOf('effects'), icon: 'puzzle', formats: [GlyphFormat(name: 'Glow', delimiter: delimiter, look: const EffectLook('heat'))]);
      for (final delimiter in ['🔥🔥', '❄️❄️', '✨✨']) {
        expect(() => createRegistry([effect(delimiter)], store: MemorySwitches()), returnsNormally, reason: delimiter);
      }
      for (final delimiter in ['🔥', '🔥🔥🔥', '🔥❄️', 'a🔥a🔥']) {
        expect(() => createRegistry([effect(delimiter)], store: MemorySwitches()), throwsArgument('delimiter'), reason: delimiter);
      }
    });
  });

  group('what the registry gathers from the plugins that are on', () {
    GlyphPlugin noted(String id, {List<NoteAction> noteActions = const [], ItemAction? itemAction, List<Tip> Function(String?)? tips, FormatContext? formatContext}) =>
        GlyphPlugin(manifest: manifestOf(id, permissions: [Permission.notes]), icon: 'puzzle', noteActions: noteActions, itemAction: itemAction, tips: tips, formatContext: formatContext);
    ItemAction action(String id, bool Function(String noteId) available) => ItemAction(id: id, label: id, busyLabel: '…', available: available, run: (_, _) async {});

    test('offers a note the first switched-on plugin’s item action that is available for it', () {
      final registry = createRegistry([noted('a', itemAction: action('a-send', (n) => n == 'n1')), noted('b', itemAction: action('b-send', (_) => true))], store: MemorySwitches());
      expect(registry.itemAction('n1')?.id, 'a-send');
      expect(registry.itemAction('n2')?.id, 'b-send');
      registry.setEnabled('b', false);
      expect(registry.itemAction('n2'), isNull);
    });

    test('lists note actions and tips in the plugins’ order, and joins their context for the formatter', () {
      NoteAction cog(String id) => NoteAction(id: id, label: id, icon: noIcon, visible: (_, _) => true, hint: (_, _) => '', enabled: (_, _) => true, run: (_, [_]) async {});
      final registry = createRegistry(
        [
          noted('a', noteActions: [cog('a1')], tips: (_) => const [Tip(say: 'Send that to A', does: 'to send it')], formatContext: FormatContext(forNote: (_) => 'About A.', version: (_) => 1)),
          noted('b', noteActions: [cog('b1'), cog('b2')], formatContext: FormatContext(forNote: (_) => '  ', version: (_) => 0)),
          noted('c', formatContext: FormatContext(forNote: (_) => 'About C.', version: (_) => 2)),
        ],
        store: MemorySwitches(),
      );
      expect([for (final a in registry.noteActions()) a.id], ['a1', 'b1', 'b2']);
      expect([for (final tip in registry.tips(null)) (tip.say, tip.does)], [('Send that to A', 'to send it')]);
      // A context that is only space says nothing, and is not joined in.
      expect(registry.contextFor('n1'), 'About A.\n\nAbout C.');
      registry.setEnabled('a', false);
      registry.setEnabled('c', false);
      expect(registry.contextFor('n1'), isNull);
      expect([for (final a in registry.noteActions()) a.id], ['b1', 'b2']);
    });
  });

  // ---- not on the page ---------------------------------------------------------------------------------------------

  group('what the port’s registry adds', () {
    test('lists every secret any plugin names for a reset, switched on or not', () {
      final registry = createRegistry(
        [
          GlyphPlugin(manifest: manifestOf('a', secrets: ['glyph-a-token']), icon: 'puzzle'),
          GlyphPlugin(manifest: manifestOf('b', standard: false, secrets: ['glyph-b-webhook:']), icon: 'puzzle'),
        ],
        store: MemorySwitches(),
      );
      expect(registry.secretNames(), ['glyph-a-token', 'glyph-b-webhook:']);
    });

    test('hands the feed’s rows to every switched-on plugin that asks, and one’s failure is not another’s', () async {
      final told = <String>[];
      GlyphPlugin hears(String id, {bool standard = true, bool fails = false, bool throwsAtOnce = false}) => GlyphPlugin(
            manifest: manifestOf(id, standard: standard),
            icon: 'puzzle',
            newRows: (before, rows) {
              told.add('$id:$before');
              if (throwsAtOnce) throw StateError('at once');
              return fails ? Future.error(StateError('later')) : Future.value();
            },
          );
      final registry = createRegistry([hears('a', fails: true), hears('b', throwsAtOnce: true), hears('c'), hears('off', standard: false)], store: MemorySwitches());
      await registry.newRows(3, const <FeedNotification>[]);
      expect(told, ['a:3', 'b:3', 'c:3']);
    });

    test('finds a plugin by its id, keeps one list of the enabled between changes, and does nothing for a switch that would not move', () {
      final store = MemorySwitches();
      final registry = createRegistry([GlyphPlugin(manifest: manifestOf('a'), icon: 'puzzle')], store: store);
      expect(registry.byId('a')?.manifest.id, 'a');
      expect(registry.byId('nobody'), isNull);
      expect(identical(registry.enabled(), registry.enabled()), isTrue);
      var heard = 0;
      final stop = registry.subscribe(() => heard++);
      registry.setEnabled('a', true);
      registry.setEnabled('nobody', true);
      expect(heard, 0);
      expect(store.held, isEmpty);
      stop();
      registry.setEnabled('a', false);
      expect(heard, 0);
      expect(registry.isEnabled('a'), isFalse);
    });

    test('keeps its switches in the device’s memory under glyph-plugins, and reads a kept shape that is not switches as none', () {
      final ground = TestGround();
      final switches = StoredSwitches(ground.kept);
      expect(switches.read(), isEmpty);
      switches.write({'slack': true});
      expect(ground.kept.readText(pluginSwitchesKey), '{"slack":true}');
      expect(switches.read(), {'slack': true});
      ground.kept.writeText(pluginSwitchesKey, '{"slack":"yes","notion":false}');
      expect(switches.read(), {'notion': false});
      ground.kept.writeText(pluginSwitchesKey, '[1,2]');
      expect(switches.read(), isEmpty);
    });

    test('is the app’s once it is put in place, and empty until then', () {
      final before = plugins;
      addTearDown(() => usePlugins(before));
      final mine = createRegistry([GlyphPlugin(manifest: manifestOf('mine'), icon: 'puzzle')], store: MemorySwitches());
      usePlugins(mine);
      expect(identical(plugins, mine), isTrue);
    });
  });
}
