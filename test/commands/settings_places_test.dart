// What the command bar finds in Settings and among the plugins (lib/commands/settings_places.dart; Matt, 2026-10-29:
// "Add the ability to search settings and plugins from the command search"): the index read from Settings' own table
// with the facts Settings reads, a sample of what is typed and what it finds, the palette's bands and headings after
// the notes and commands, and where choosing each goes.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/commands/app_commands.dart' show paletteNotes;
import 'package:ghost_md/commands/palette.dart';
import 'package:ghost_md/commands/settings_places.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart' show seedLibrary;
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/settings/settings_sections.dart';
import 'package:glacier/glacier.dart' show groupCommands, matchCommands;

import 'support.dart';

const Preferences _advanced = Preferences(theme: 'light', experience: 'advanced', experienceChosen: true);
const Preferences _simple = Preferences(theme: 'light', experience: 'simple', experienceChosen: true);

SettingsFacts _facts(Preferences prefs, {bool developer = false}) => SettingsFacts(prefs: prefs, wide: true, haptics: true, android: true, ios: false, developer: developer);

/// The built-in plugins with [added] switched on and every other off.
Registry _registry(Set<String> added) => createRegistry(builtIn, store: MemorySwitches({for (final plugin in builtIn) plugin.manifest.id: added.contains(plugin.manifest.id)}));

/// The index Settings' table makes for [prefs] over [registry], which is the app's for as long as it is read.
SettingsIndex _index(Preferences prefs, Registry registry, {bool developer = false}) {
  final before = plugins;
  usePlugins(registry);
  try {
    return settingsIndex(_facts(prefs, developer: developer), registry: registry);
  } finally {
    usePlugins(before);
  }
}

/// What [query] finds, each as "label · detail"; with [plugins], only what is under Plugins.
List<String> _found(SettingsIndex index, String query, {bool market = true, bool plugins = false}) => [
      for (final place in findPlaces(index, query, market: market))
        if (!plugins || place.ofPlugins) place.detail == null ? place.label : '${place.label} · ${place.detail}',
    ];

List<String> _ids(SettingsIndex index, String query) => [for (final place in findPlaces(index, query)) place.id];

void main() {
  // A setup asked to read its keys answers after its test: let it, then forget it.
  setUp(forgetPreparedSetups);
  tearDown(() async {
    await pumpEventQueue();
    forgetPreparedSetups();
  });

  group('the index', () {
    test('is Settings’ own sections for the facts, the Market’s row left to the palette’s Market', () {
      final index = _index(_advanced, _registry({}));
      final among = [
        for (final spec in settingsSections)
          if ((spec.where?.call(_facts(_advanced)) ?? true) && spec.id != marketSectionId) spec.id,
      ];
      expect([for (final section in index.sections) section.id], among);
      expect(index.sections.map((section) => section.id), isNot(contains('market')));
      // Every plugin Ghost.md carries, in the catalogue's order.
      expect(index.plugins, hasLength(builtIn.length));
    });

    test('finds a sample of settings by name, by their words, without minding case or accents, at the start of a word', () {
      final index = _index(_advanced, _registry({}));
      expect(_found(index, 'dark'), contains('Page · Appearance'));
      expect(_found(index, 'geotag'), containsAll(['Location · Account', 'Tag new notes with my location · Account']));
      expect(_found(index, 'header toolbar'), contains('Top bar · Appearance'));
      expect(_found(index, 'font size'), contains('Text size · Appearance'));
      expect(_found(index, 'sync'), contains(startsWith('Account · ')));
      expect(_found(index, 'sync'), contains('Conflicts · Notifications'));
      expect(_found(index, 'meeting summaries'), contains('Summaries · Recording'));
      // A page by its own name, with its line beside it, and none of its settings again.
      expect(_found(index, 'appearance'), [startsWith('Appearance · ')]);
      // Case and accents: what is typed is matched as what is drawn.
      expect(_found(index, 'TEXT SIZE'), contains('Text size · Appearance'));
      expect(_found(index, 'thème'), contains(startsWith('Appearance · ')));
      expect(_found(index, 'tëxt sïze'), contains('Text size · Appearance'));
      // A word is found at its start, never inside another.
      expect(_found(index, 'ark'), isNot(contains('Page · Appearance')));
      expect(_found(index, 'ize'), isEmpty);
      // A sub-page's settings say the page they are behind too.
      expect(_found(index, 'bold'), contains('Bold · About › Cheat sheet'));
      expect(findPlaces(index, ''), isEmpty);
      expect(findPlaces(index, '   '), isEmpty);
    });

    test('the developer’s settings only while the developer’s pages are shown', () {
      expect(_found(_index(_advanced, _registry({})), 'header toolbar'), isNot(contains('Header toolbar · Developer')));
      expect(_found(_index(_advanced, _registry({}), developer: true), 'header toolbar'), contains('Header toolbar · Developer'));
      expect(_found(_index(_simple, _registry({}), developer: true), 'header toolbar'), contains('Header toolbar · Developer'));
    });

    test('in Simple: the rows Simple keeps behind More, and nothing of the pages Simple puts away', () {
      final index = _index(_simple, _registry({'notion'}));
      // Behind More on Simple's pages, and found.
      expect(_found(index, 'typewriter'), contains('Typewriter scroll · Appearance'));
      expect(_found(index, 'volume'), contains('Volume · Sounds'));
      // Advanced's cards and pages are not Simple's.
      expect(_found(index, 'accent'), isEmpty);
      expect(_found(index, 'snippets'), isEmpty);
      // No Market in Simple: no plugin but those whose page Simple keeps.
      expect(_found(index, 'notion'), isEmpty);
      expect(index.plugins, isEmpty);
    });

    test('finds the plugins by name, line and words, saying whether each is added', () {
      final none = _index(_advanced, _registry({}));
      expect(_found(none, 'notion'), ['Notion · Not added']);
      expect(findPlaces(none, 'notion').single.page, isNull, reason: 'a plugin not added opens in the Market');
      final added = _index(_advanced, _registry({'notion', 'keyboard-modes', 'lovart'}));
      expect(_found(added, 'notion'), contains('Notion · Added'));
      expect(findPlaces(added, 'notion').first.page, 'plugin:notion', reason: 'an added plugin opens its page in Settings');
      // Found by what it does.
      expect(_found(none, 'vim'), contains('Keyboard modes · Not added'));
      expect(_found(none, 'emacs'), contains('Keyboard modes · Not added'));
    });

    test('an added plugin’s own settings, on its page, with its name beside them', () {
      final none = _index(_advanced, _registry({}));
      expect(_found(none, 'jk'), isEmpty, reason: 'a plugin not added has no page to open at');
      final added = _index(_advanced, _registry({'keyboard-modes', 'lovart'}));
      expect(_found(added, 'vim'), containsAll(['Keyboard modes · Added', 'Start notes in Normal mode · Keyboard modes', 'jk to leave Insert · Keyboard modes']));
      expect(_found(added, 'jk'), ['jk to leave Insert · Keyboard modes']);
      expect(_found(added, 'header images'), contains('Header images for notes · Lovart'));
      final jk = findPlaces(added, 'jk').single;
      expect((jk.page, jk.setting, jk.ofPlugins), ('plugin:keyboard-modes', 'jk to leave Insert', true));
      // Its page is the plugin's row, not offered twice.
      expect(_ids(added, 'keyboard modes'), ['find:plugin:keyboard-modes']);
    });

    test('an added plugin whose setup is not done has Set up, once its keys have been read', () async {
      final registry = _registry({'lovart'});
      // The first index asks the setup to read its keys, and offers nothing it cannot be sure of yet.
      expect(_found(_index(_advanced, registry), 'lovart', plugins: true), ['Lovart · Added']);
      await pumpEventQueue();
      final index = _index(_advanced, registry);
      expect(_found(index, 'lovart', plugins: true), ['Lovart · Added', 'Set up Lovart · Not set up yet']);
      expect(_found(index, 'set up'), contains('Set up Lovart · Not set up yet'));
      final setUp = findPlaces(index, 'lovart').last;
      expect((setUp.kind, setUp.page, setUp.setting), (SettingsPlaceKind.setUp, 'plugin:lovart', 'Set up Lovart'));
      // A plugin not added has no setup to offer.
      expect(_found(_index(_advanced, _registry({})), 'lovart', plugins: true), ['Lovart · Not added']);
    });

    test('offers at most a dozen of Settings’ and ten of the plugins’, the best by name', () {
      final index = _index(_advanced, _registry({for (final plugin in builtIn) plugin.manifest.id}));
      final all = findPlaces(index, 'plugin');
      expect(all.where((place) => place.ofPlugins), hasLength(lessThanOrEqualTo(mostPlugins)));
      final settings = findPlaces(index, 'a');
      expect(settings.where((place) => !place.ofPlugins), hasLength(mostSettings));
      expect(settings.where((place) => !place.ofPlugins).first.label, startsWith('A'));
    });
  });

  group('in the palette', () {
    final calls = Calls();
    setUp(calls.said.clear);

    PaletteDoing doing({bool market = true}) {
      final every = everyDoing(calls);
      return PaletteDoing(
        openNote: every.openNote,
        newNote: every.newNote,
        closeTab: every.closeTab,
        showList: every.showList,
        browseNotes: every.browseNotes,
        back: every.back,
        forward: every.forward,
        settings: every.settings,
        chooseWorkspace: every.chooseWorkspace,
        fileNote: every.fileNote,
        setTheme: every.setTheme,
        pin: every.pin,
        archive: every.archive,
        remove: every.remove,
        settingsAt: (page, setting) => calls('settingsAt $page ${setting ?? '-'}'),
        marketPlugin: market ? (id) => calls('marketPlugin $id') : null,
      );
    }

    PaletteWorld world(SettingsIndex index, {bool simple = false}) => PaletteWorld(notes: paletteNotes(seedLibrary()), theme: 'light', simple: simple, settings: () => index);

    test('comes after the notes and the commands, under Settings and then Plugins, and only once something is typed', () {
      final index = _index(_advanced, _registry({'keyboard-modes'}));
      final commands = paletteCommands(world(index), doing(), 'dark');
      final groups = [for (final group in groupCommands(matchCommands([for (final command in commands) command.descriptor], 'dark'))) group.group];
      // The theme's command first, however well a setting's name was hit.
      expect(groups.first, 'Look');
      expect(groups.sublist(groups.indexOf('Settings')), ['Settings']);
      expect(groups.where((group) => group == 'Settings'), hasLength(1), reason: 'one heading, not split by the tiers');
      // Notes by name, when a note is found, before Settings.
      final notes = paletteCommands(world(index), doing(), 'groceries');
      final noteGroups = [for (final group in groupCommands(matchCommands([for (final command in notes) command.descriptor], 'groceries'))) group.group];
      expect(noteGroups.first, 'Notes by name');
      final vim = paletteCommands(world(index), doing(), 'vim');
      final vimGroups = [for (final group in groupCommands(matchCommands([for (final command in vim) command.descriptor], 'vim'))) group.group];
      expect(vimGroups.last, 'Plugins');
      // Nothing typed, nothing of Settings' or the plugins'.
      expect(paletteCommands(world(index), doing(), '').where((command) => command.descriptor.id.startsWith('find:')), isEmpty);
      // Each says where it is beside its name.
      final page = paletteCommands(world(index), doing(), 'dark').singleWhere((command) => command.descriptor.id == 'find:settings:theme/Page');
      expect((page.descriptor.label, page.descriptor.detail, page.descriptor.band), ('Page', 'Appearance', 1));
    });

    test('is kept by the palette’s own matching for an accent or a hyphen it would not find', () {
      final index = _index(_advanced, _registry({}));
      for (final query in ['thème', 'text-size', 'géotag']) {
        final commands = paletteCommands(world(index), doing(), query);
        final offered = [for (final command in commands) if (command.descriptor.id.startsWith('find:')) command.descriptor.id];
        final kept = [for (final match in matchCommands([for (final command in commands) command.descriptor], query)) if (match.item.id.startsWith('find:')) match.item.id];
        expect(offered, isNotEmpty, reason: query);
        expect(kept.toSet(), offered.toSet(), reason: query);
      }
    });

    test('choosing one opens Settings at its page and its setting, or the Market at a plugin not added', () {
      final index = _index(_advanced, _registry({'keyboard-modes'}));
      void choose(String query, String id) => paletteCommands(world(index), doing(), query).singleWhere((command) => command.descriptor.id == id).run();
      choose('font size', 'find:settings:theme/Text size');
      choose('appearance', 'find:settings:theme');
      choose('jk', 'find:plugin:keyboard-modes/jk to leave Insert');
      choose('keyboard modes', 'find:plugin:keyboard-modes');
      choose('notion', 'find:plugin:notion');
      expect(calls.said, ['settingsAt theme Text size', 'settingsAt theme -', 'settingsAt plugin:keyboard-modes jk to leave Insert', 'settingsAt plugin:keyboard-modes -', 'marketPlugin notion']);
    });

    test('without the Market (Simple, or none given) no plugin it would open there', () {
      final index = _index(_advanced, _registry({'keyboard-modes'}));
      final ids = [for (final command in paletteCommands(world(index), doing(market: false), 'notion')) command.descriptor.id];
      expect(ids, isNot(contains('find:plugin:notion')));
      final simple = [for (final command in paletteCommands(world(index, simple: true), doing(), 'notion')) command.descriptor.id];
      expect(simple, isNot(contains('find:plugin:notion')));
      // Without a way to open Settings at a page, nothing at all.
      final bare = PaletteDoing(
        openNote: (_) {}, newNote: () {}, closeTab: (_) {}, showList: () {}, browseNotes: () {}, back: () {}, forward: () {}, settings: () {}, chooseWorkspace: (_) {}, fileNote: (_, _) {}, setTheme: (_) {}, pin: (_, _) {}, archive: (_) {}, remove: (_) {},
      );
      expect(paletteCommands(world(index), bare, 'dark').where((command) => command.descriptor.id.startsWith('find:')), isEmpty);
    });
  });
}
