import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the app is dressed in, and what survives a store written by another build: the web app's
/// src/app/core/preferences.test.ts, case for case, on the Dart port. The look itself is the token sheets'; these
/// are the attributes it hangs on, which is the part that can silently stop working.
///
/// [_web] is the web app's own module asked the same questions (2026-10-07, over its dev server): its defaults as
/// `JSON.stringify` writes them, and for each stored shape what `settle` read back, what `applyPreferences` stamped
/// on `<html>` and what it wrote as inline style. The port has to agree with every one.
void main() {
  final web = jsonDecode(_web) as Map<String, dynamic>;
  final cases = (web['cases'] as Map<String, dynamic>).cast<String, Map<String, dynamic>>();

  /// The preferences as a launch reads [stored] laid over the defaults (`launchWith`).
  Preferences launchWith(Map<String, Object?> stored) => Preferences.fromJson(jsonDecode(jsonEncode({...Preferences.defaults.toJson(), ...stored})));

  group('how the app is drawn', () {
    test('stamps nothing while everything is the app’s own', () {
      final attrs = Preferences.defaults.attrs;
      expect(attrs.containsKey('accent'), isFalse);
      expect(attrs.containsKey('rounding'), isFalse);
      expect(attrs.containsKey('density'), isFalse);
      // The theme is the exception: Ghost.md's own default is dark, not the phone's, so it is always stamped.
      expect(attrs['theme'], Preferences.defaults.theme);
    });

    test('stamps the accent and the rounding once they are chosen, and clears them again', () {
      final chosen = Preferences.defaults.copyWith(accent: 'teal', rounding: 'square', density: 'compact');
      expect(chosen.attrs, containsPair('accent', 'teal'));
      expect(chosen.attrs, containsPair('rounding', 'square'));
      expect(chosen.attrs, containsPair('density', 'compact'));
      final back = chosen.copyWith(accent: 'ink', rounding: 'round', density: 'comfortable');
      expect(back.attrs.keys, isNot(anyOf(contains('accent'), contains('rounding'), contains('density'))));
    });

    test('knows its own names, and no others', () {
      expect(isAccent('purple'), isTrue);
      expect(isAccent('ink'), isTrue);
      // The accent used to be a colour the app never drew with; a store from that build must not stamp it.
      expect(isAccent('blue'), isFalse);
      expect(isRounding('rounder'), isTrue);
      expect(isRounding('squircle'), isFalse);
    });

    test('takes an accent or a rounding it does not know as the app’s own', () {
      final read = launchWith({'accent': 'blue', 'rounding': 'squircle'});
      expect(read.accent, isNot('blue'));
      expect(read.rounding, isNot('squircle'));
      expect(read.attrs.containsKey('accent'), isFalse);
      expect(read.attrs.containsKey('rounding'), isFalse);
      // And one that reaches the attributes unsettled, as a choice made in memory could, is still not stamped.
      expect(const Preferences(accent: 'blue', rounding: 'squircle', topBar: 'strip').attrs.keys, isNot(anyOf(contains('accent'), contains('rounding'), contains('topbar'))));
    });

    test('draws notes in Maple Mono and the interface in Inter by default, and stamps both', () {
      expect(Preferences.defaults.faces, (ui: 'inter', note: 'maple'));
      // The interface's own default stamps nothing, as the kit expects; the note's face is always stamped.
      expect(Preferences.defaults.attrs.containsKey('font'), isFalse);
      expect(Preferences.defaults.attrs['note-font'], 'maple');
      final chosen = Preferences.defaults.copyWith(noteFace: 'inter', typeface: 'plex');
      expect(chosen.attrs['note-font'], 'inter');
      expect(chosen.attrs['font'], 'plex');
    });

    test('reads one face for everything, from a store or another device, as a pair', () {
      // A coding face chosen for the whole app, before there were two: the note's now, and the interface its default.
      expect(facesOf(typeface: 'maple'), (ui: 'inter', note: 'maple'));
      expect(facesOf(typeface: 'fira'), (ui: 'inter', note: 'fira'));
      // A sans chosen then keeps the interface in it, and the note takes the default.
      expect(facesOf(typeface: 'plex'), (ui: 'plex', note: 'maple'));
      // Names from a newer build are the defaults here.
      expect(facesOf(typeface: 'comic', noteFace: 'wingdings'), (ui: 'inter', note: 'maple'));
      // A note face said outright wins over an old coding face in the interface's place.
      expect(facesOf(typeface: 'maple', noteFace: 'noto'), (ui: 'inter', note: 'noto'));
      // And the attributes follow, for preferences that reach them with one face for everything.
      final legacy = const Preferences(typeface: 'fira', noteFace: '').attrs;
      expect(legacy.containsKey('font'), isFalse);
      expect(legacy['note-font'], 'fira');
    });

    test('stamps a named theme twice, its side of the page and its name, and nothing for System', () {
      expect(const Preferences(theme: 'system').attrs.keys, isNot(anyOf(contains('theme'), contains('theme-preset'))));
      expect(const Preferences(theme: 'light').attrs, containsPair('theme', 'light'));
      expect(const Preferences(theme: 'light').attrs.containsKey('theme-preset'), isFalse);
      for (final entry in themePresets.entries) {
        final attrs = Preferences(theme: entry.key).attrs;
        expect(attrs, containsPair('theme', entry.value.scheme));
        expect(attrs, containsPair('theme-preset', entry.key));
      }
    });

    test('stamps each choice by its own attribute, and leaves each default out', () {
      const d = Preferences.defaults;
      for (final density in densities) {
        expect(d.copyWith(density: density).attrs['density'], density == 'comfortable' ? isNull : density);
      }
      for (final accent in accents) {
        expect(d.copyWith(accent: accent).attrs['accent'], accent == 'ink' ? isNull : accent);
      }
      for (final rounding in roundings) {
        expect(d.copyWith(rounding: rounding).attrs['rounding'], rounding == 'round' ? isNull : rounding);
      }
      for (final size in textSizes) {
        expect(d.copyWith(textSize: size).attrs['text-size'], size == 'large' ? isNull : size);
      }
      for (final bar in topBarIds) {
        expect(d.copyWith(topBar: bar).attrs['topbar'], bar == 'classic' ? isNull : bar);
      }
      for (final face in interfaceFaces) {
        expect(d.copyWith(typeface: face).attrs['font'], face == 'inter' ? isNull : face);
      }
      for (final face in typefaces) {
        expect(d.copyWith(noteFace: face).attrs['note-font'], face);
      }
      // Both code themes are always stamped.
      expect(d.copyWith(codeLight: 'github', codeDark: 'nord').attrs, allOf(containsPair('code-light', 'github'), containsPair('code-dark', 'nord')));
    });

    test('writes the size and the pace as the page’s inline styles, and leaves the pace to a still device', () {
      expect(Preferences.defaults.rootStyle(), {'--app-motion-scale': '1'});
      expect(const Preferences(uiScale: 0.925).rootStyle()['font-size'], '92.5%');
      expect(const Preferences(uiScale: 1.25).rootStyle()['font-size'], '125%');
      expect(const Preferences(motionSpeed: 'relaxed').rootStyle(), {
        '--glacier-duration-instant': '120ms',
        '--glacier-duration-fast': '240ms',
        '--glacier-duration-normal': '400ms',
        '--glacier-duration-slow': '640ms',
        '--glacier-duration-slower': '960ms',
        '--app-motion-scale': '1.6',
      });
      expect(const Preferences(motionSpeed: 'brisk').rootStyle(still: true), {'--app-motion-scale': '1'});
      expect(const Preferences(motionSpeed: 'brisk').motionScale, 0.6);
    });

    test('brings a named theme’s accent with it, and takes it back only if it was not changed since', () {
      const now = Preferences.defaults;
      final ember = themeChoice('ember', now);
      expect((ember.theme, ember.accent), ('ember', 'amber'));
      // Back to a plain theme: the accent the named one put there goes with it.
      expect(themeChoice('light', ember).accent, 'ink');
      // An accent chosen on purpose afterwards is left alone.
      expect(themeChoice('light', ember.copyWith(accent: 'teal')).accent, 'teal');
      expect(themeChoice('dark', now.copyWith(accent: 'purple')).accent, 'purple');
      expect(themeScheme('boreal'), 'dark');
      expect(themeScheme('system'), 'system');
      expect(isDarkNow('system', platformDark: true), isTrue);
      expect(isDarkNow('dawn', platformDark: true), isFalse);
    });
  });

  group('the web app’s own answers', () {
    test('the defaults are the web’s, written as the web writes them', () {
      expect(jsonEncode(Preferences.defaults.toJson()), web['defaults']);
    });

    for (final name in cases.keys) {
      test('reads the stored shape “$name” as the web app does, and stamps the page as it does', () {
        final read = Preferences.fromJson(cases[name]!['stored']);
        expect(jsonDecode(jsonEncode(read.toJson())), cases[name]!['read'], reason: 'settle');
        expect(read.attrs, cases[name]!['attrs'], reason: 'the attributes applyPreferences stamps');
        expect(read.rootStyle(), cases[name]!['style'], reason: 'the inline styles applyPreferences writes');
        // What is written is read back as itself: a round trip changes nothing.
        expect(Preferences.fromJson(jsonDecode(jsonEncode(read.toJson()))), read);
      });
    }
  });

  group('a store written by another build, or half written', () {
    test('reads a Write up or a Sync meeting recordings it does not know as the default', () {
      final kept = launchWith({'writeUp': 'now', 'syncMeetingRecordings': false, 'syncMeetingRecordingsChosen': true});
      expect((kept.writeUp, kept.syncMeetingRecordings), ('now', false));
      final odd = launchWith({'writeUp': 'overnight', 'syncMeetingRecordings': 'yes', 'syncMeetingRecordingsChosen': true});
      expect((odd.writeUp, odd.syncMeetingRecordings), ('charging', true));
    });

    test('reads Sync meeting recordings as on until the switch is touched, whatever an older build wrote (GHST-112)', () {
      expect(Preferences.defaults.syncMeetingRecordings, isTrue);
      // Every store from before held the old default, off, though nobody chose it.
      expect(Preferences.fromJson({'syncMeetingRecordings': false}).syncMeetingRecordings, isTrue);
      // Turned off on purpose, it stays off, and turned on again, on.
      final off = Preferences.fromJson(jsonDecode(jsonEncode(Preferences.defaults.copyWith(syncMeetingRecordings: false, syncMeetingRecordingsChosen: true).toJson())));
      expect((off.syncMeetingRecordings, off.syncMeetingRecordingsChosen), (false, true));
      expect(Preferences.fromJson({'syncMeetingRecordings': true, 'syncMeetingRecordingsChosen': true}).syncMeetingRecordings, isTrue);
    });

    test('reads a meeting’s own sound as off unless written on, and off by default', () {
      expect(Preferences.defaults.meetingSound, isFalse);
      expect(launchWith({'meetingSound': true}).meetingSound, isTrue);
      expect(launchWith({'meetingSound': 'yes'}).meetingSound, isFalse);
    });

    test('reads as the defaults when there is nothing, or nothing that is JSON', () {
      expect(Preferences.fromJson(null), Preferences.defaults);
      expect(Preferences.fromJson('{half'), Preferences.defaults);
      expect(Preferences.fromJson(const [1, 2]), Preferences.defaults);
    });

    test('keeps only the tabs that are ids, the last eight of them', () {
      final ids = [for (var i = 0; i < 10; i++) 'n$i'];
      expect(launchWith({'openNotes': [...ids.take(2), 7, null, ...ids.skip(2)]}).openNotes, ids.skip(2));
      expect(launchWith({'openNotes': 'n1'}).openNotes, isEmpty);
    });

    test('keeps tab groups that are whole, and only tabs that point at one of them', () {
      final tabGroups = {
        'list': [
          {'id': 'g1', 'name': 'Work', 'hue': 'teal'},
          {'id': 'g2', 'name': 'No colour'},
          'rubbish',
          {'id': 3, 'name': 'Bad id', 'hue': 'red'},
        ],
        'of': {'a': 'g1', 'b': 'g2', 'c': 'gone', 'd': 4},
      };
      final read = launchWith({'tabGroups': tabGroups}).tabGroups;
      expect(read.list.map((g) => (g.id, g.name, g.hue)), [('g1', 'Work', 'teal')]);
      expect(read.of, {'a': 'g1'});
      expect(launchWith({'tabGroups': {'list': 'no'}}).tabGroups.toJson(), {'list': <Object?>[], 'of': <String, String>{}});
    });

    test('keeps workspaces with an id and a name, and filings that point at one of them', () {
      final workspaces = {
        'list': [
          {'id': 'w1', 'name': 'Home'},
          {'id': 'w2'},
          null,
        ],
        'notes': {'a': 'w1', 'b': 'w2', 'c': 5},
      };
      expect(launchWith({'workspaces': workspaces}).workspaces.toJson(), {
        'list': [
          {'id': 'w1', 'name': 'Home'},
        ],
        'notes': {'a': 'w1'},
      });
      expect(launchWith({'workspaces': 'none'}).workspaces.toJson(), {'list': <Object?>[], 'notes': <String, String>{}});
    });

    test('reads the notification switches as on unless written off, and mutes only ids', () {
      expect(launchWith({'notifications': {'team': false, 'mutedOrgs': ['o1', 7, null]}}).notifications.toJson(), {'team': false, 'claude': true, 'summaries': true, 'conflicts': true, 'mutedOrgs': ['o1']});
      expect(launchWith({'notifications': 'all'}).notifications, Preferences.defaults.notifications);
      expect(launchWith({}).notifications.toJson(), {'team': true, 'claude': true, 'summaries': true, 'conflicts': true, 'mutedOrgs': <String>[]});
    });

    test('keeps the trash only as ids with a time', () {
      expect(launchWith({'trash': {'a': 10, 'b': 'yesterday', 'c': null}}).trash, {'a': 10});
      expect(launchWith({'trash': 'none'}).trash, isEmpty);
    });

    test('keeps the meetings only as note ids with the time each started', () {
      expect(launchWith({'meetings': {'a': 10, 'b': 'yesterday', 'c': null}}).meetings, {'a': 10});
      expect(launchWith({'meetings': 'none'}).meetings, isEmpty);
      expect(launchWith({}).meetings, isEmpty);
    });

    test('keeps a share only when its id and key are ones a link could carry', () {
      final id = 'A' * 22, key = 'b_' * 20;
      final shares = {
        'good': {'id': id, 'key': key, 'sent': 'p2:9', 'lacked': ['x.jpg', 4]},
        'unsent': {'id': id, 'key': key},
        'short': {'id': 'abc', 'key': key},
        'spaced': {'id': id, 'key': 'not a key at all, not at all'},
        'none': null,
      };
      expect({for (final e in launchWith({'shares': shares}).shares.entries) e.key: e.value.toJson()}, {
        'good': {'id': id, 'key': key, 'sent': 'p2:9', 'lacked': ['x.jpg']},
        'unsent': {'id': id, 'key': key, 'sent': ''},
      });
    });

    test('keeps whether a share carries where its note was written, only as true', () {
      final id = 'A' * 22, key = 'b_' * 20;
      final shares = {
        'placed': {'id': id, 'key': key, 'sent': 'p2:9', 'place': true},
        'said': {'id': id, 'key': key, 'sent': '', 'place': false},
        'odd': {'id': id, 'key': key, 'sent': '', 'place': 'yes'},
      };
      expect({for (final e in launchWith({'shares': shares}).shares.entries) e.key: e.value.toJson()}, {
        'placed': {'id': id, 'key': key, 'sent': 'p2:9', 'place': true},
        'said': {'id': id, 'key': key, 'sent': ''},
        'odd': {'id': id, 'key': key, 'sent': ''},
      });
    });

    test('reads a pace, a theme, a size or a sidebar this build does not have as its own', () {
      const d = Preferences.defaults;
      final read = launchWith({'motionSpeed': 'ludicrous', 'theme': 'neon', 'uiScale': 3, 'sidebarStyle': 'floating', 'noteView': 'hologram'});
      expect((read.motionSpeed, read.theme, read.uiScale, read.sidebarStyle, read.noteView), (d.motionSpeed, d.theme, d.uiScale, d.sidebarStyle, d.noteView));
    });

    test('keeps code colours only once they have been chosen', () {
      const d = Preferences.defaults;
      final unchosen = launchWith({'codeLight': 'ink', 'codeDark': 'ink', 'codeChosen': false});
      expect((unchosen.codeLight, unchosen.codeDark), (d.codeLight, d.codeDark));
      final chosen = launchWith({'codeLight': 'ink', 'codeDark': 'ink', 'codeChosen': true});
      expect((chosen.codeLight, chosen.codeDark), ('ink', 'ink'));
    });

    test('opens the home page on Spotlight until a layout is picked, the Cards every device stored before it included', () {
      expect(Preferences.defaults.homeLayout, 'spotlight');
      expect(launchWith({'homeLayout': 'cards'}).homeLayout, 'spotlight');
      expect(launchWith({'homeLayout': 'cards', 'homeLayoutChosen': true}).homeLayout, 'cards');
      expect(launchWith({'homeLayout': 'sideways', 'homeLayoutChosen': true}).homeLayout, 'spotlight');
    });

    test('is the whole app until simple or advanced is chosen, and keeps the choice once it is (GHST-103)', () {
      expect(Preferences.defaults.experience, 'advanced');
      expect(Preferences.defaults.simple, isFalse);
      // An install from before there was a choice, or a store written by a later build with a mode this one lacks.
      expect(launchWith({'experience': 'simple'}).simple, isFalse);
      expect(launchWith({'experience': 'simple', 'experienceChosen': true}).simple, isTrue);
      expect(launchWith({'experience': 'expert', 'experienceChosen': true}).experience, 'advanced');
      final chosen = launchWith({'experience': 'simple', 'experienceChosen': true});
      expect(chosen.toJson(), containsPair('experience', 'simple'));
      expect(chosen.copyWith(experience: 'advanced').simple, isFalse);
      // Choosing Simple opens notes formatted; choosing Advanced leaves the view as it was.
      final simple = Preferences.defaults.choosing('simple');
      expect((simple.experience, simple.experienceChosen, simple.noteView), ('simple', true, 'formatted'));
      final advanced = simple.choosing('advanced');
      expect((advanced.experience, advanced.noteView), ('advanced', 'formatted'));
    });

    test('reads a top bar cut from the choices, the Strip or Thumb, as Classic, and keeps the four', () {
      expect(Preferences.defaults.topBar, 'classic');
      for (final gone in ['strip', 'thumb']) {
        expect(launchWith({'topBar': gone}).topBar, 'classic');
      }
      for (final kept in ['ledger', 'masthead', 'islands']) {
        expect(launchWith({'topBar': kept}).topBar, kept);
      }
    });

    test('reads a switch that is not a yes or a no as its default, where the page kept the odd value', () {
      // The one place the typed port settles more than the page does (lib/core/preferences.dart).
      final read = launchWith({'assist': 'on', 'wisp': 0, 'linkPreviews': null});
      expect((read.assist, read.wisp, read.linkPreviews), (true, true, true));
    });

    test('keeps what a newer build stored under keys this one does not know, and writes it back', () {
      final read = Preferences.fromJson({'theme': 'light', 'somethingNew': {'a': 1}});
      expect(read.more, {'somethingNew': {'a': 1}});
      expect(read.copyWith(accent: 'teal').toJson()['somethingNew'], {'a': 1});
    });
  });

  group('kept on the device', () {
    setUp(() => preferences.forget());

    test('reads what the web app stored under its own key, before anything is drawn', () async {
      SharedPreferences.setMockInitialValues({PreferencesStore.storageKey: jsonEncode({'theme': 'ember', 'accent': 'amber', 'density': 'compact'})});
      expect(PreferencesStore.storageKey, 'glyph-preferences');
      expect(preferences.loaded, isFalse);
      await preferences.load();
      expect(preferences.loaded, isTrue);
      expect(preferences.value.theme, 'ember');
      expect(preferences.value.attrs, allOf(containsPair('theme', 'dark'), containsPair('theme-preset', 'ember'), containsPair('accent', 'amber'), containsPair('density', 'compact')));
    });

    test('keeps a choice as the web’s own JSON, and tells everyone following', () async {
      SharedPreferences.setMockInitialValues({});
      await preferences.load();
      var told = 0;
      void listener() => told++;
      preferences.addListener(listener);
      preferences.update((now) => now.copyWith(accent: 'teal', uiScale: 1.1));
      preferences.removeListener(listener);
      expect(told, 1);
      preferences.flush();
      final kept = (await SharedPreferences.getInstance()).getString('glyph-preferences')!;
      expect(jsonDecode(kept), {...(jsonDecode(web['defaults'] as String) as Map<String, dynamic>), 'accent': 'teal', 'uiScale': 1.1});
      // A fresh read of the store is what a launch does.
      preferences.value = preferences.value.copyWith(accent: 'ink');
      expect(preferences.value.accent, 'ink');
      preferences.flush();
      preferences.reload();
      expect(preferences.value.accent, 'ink');
    });

    test('keeps a run of changes once, a moment after the first, and at once when asked', () async {
      SharedPreferences.setMockInitialValues({});
      final store = PreferencesStore(keepAfter: const Duration(milliseconds: 40));
      await store.load();
      final kept = await SharedPreferences.getInstance();
      String? stored() => kept.getString('glyph-preferences');
      store.update((now) => now.copyWith(accent: 'teal'));
      store.update((now) => now.copyWith(openNotes: const ['a']));
      store.update((now) => now.copyWith(openNotes: const ['a', 'b']));
      // Nothing is written in the turn that made the change, nor the next.
      expect(stored(), isNull);
      await Future<void>.delayed(Duration.zero);
      expect(stored(), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(jsonDecode(stored()!), allOf(containsPair('accent', 'teal'), containsPair('openNotes', ['a', 'b'])));
      // Asked, it is kept now: the app asks as it is hidden.
      store.update((now) => now.copyWith(accent: 'red'));
      expect((jsonDecode(stored()!) as Map)['accent'], 'teal');
      store.flush();
      expect((jsonDecode(stored()!) as Map)['accent'], 'red');
      // And a change let go by reading the store again is not kept after all.
      store.update((now) => now.copyWith(accent: 'green'));
      store.reload();
      expect(store.value.accent, 'red');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect((jsonDecode(stored()!) as Map)['accent'], 'red');
    });

    test('tells whoever listens to one preference of that one alone', () async {
      SharedPreferences.setMockInitialValues({});
      await preferences.load();
      final localOnly = preferences.select((prefs) => prefs.localOnly);
      final tabs = preferences.select<List<String>>((prefs) => prefs.openNotes);
      var told = 0, tabbed = 0;
      void heard() => told += 1;
      void tab() => tabbed += 1;
      localOnly.addListener(heard);
      tabs.addListener(tab);
      preferences.update((now) => now.copyWith(accent: 'teal'));
      preferences.update((now) => now.copyWith(openNotes: const ['a']));
      preferences.update((now) => now.copyWith(trash: const {'a': 5}));
      expect((told, tabbed), (0, 1));
      preferences.update((now) => now.copyWith(localOnly: true));
      expect((told, tabbed), (1, 1));
      expect(localOnly.value, isTrue);
      preferences.update((now) => now.copyWith(localOnly: true, accent: 'red'));
      expect(told, 1);
      // Followed by nobody it listens to nothing, and still answers what is chosen now.
      localOnly.removeListener(heard);
      tabs.removeListener(tab);
      preferences.update((now) => now.copyWith(localOnly: false));
      expect(told, 1);
      expect(localOnly.value, isFalse);
    });

    test('reads as the defaults when there is nothing, or nothing that is JSON', () async {
      SharedPreferences.setMockInitialValues({'glyph-preferences': '{half'});
      await preferences.load();
      expect(preferences.value, Preferences.defaults);
    });

    test('keeps a choice made before storage answered, rather than what was stored', () async {
      SharedPreferences.setMockInitialValues({'glyph-preferences': jsonEncode({'theme': 'light'})});
      preferences.value = const Preferences(theme: 'dawn');
      await preferences.load();
      expect(preferences.value.theme, 'dawn');
    });

    test('never replaces what was kept with the defaults: a change made before storage answered is made over what it held', () async {
      // A slow device: the app is drawn on the defaults and a tab is opened, a note thrown away and a theme chosen
      // before what was kept has been read (lib/main.dart waits two seconds for it and goes on).
      SharedPreferences.setMockInitialValues({
        'glyph-preferences': jsonEncode({
          'theme': 'ember',
          'accent': 'amber',
          'homeLayout': 'timeline',
          'homeLayoutChosen': true,
          'openNotes': ['kept'],
          'workspaces': {
            'list': [
              {'id': 'w1', 'name': 'Home'},
            ],
            'notes': {'n1': 'w1', 'n2': 'w1'},
          },
          'trash': {'old': 10},
        }),
      });
      final store = PreferencesStore(keepAfter: const Duration(milliseconds: 20));
      final loading = store.load();
      expect(store.loaded, isFalse);
      store.update((now) => now.copyWith(openNotes: [...now.openNotes, 'new']));
      store.update((now) => now.copyWith(trash: {...now.trash, 'thrown': 20}));
      store.value = store.value.copyWith(density: 'compact');
      // Meanwhile the choices stand over the defaults, for this run.
      expect((store.value.theme, store.value.density), ('dark', 'compact'));
      expect(store.value.openNotes, ['new']);
      await loading;
      // Read, what was kept is all there, with each change made over it.
      expect(store.value.theme, 'ember');
      expect(store.value.accent, 'amber');
      expect(store.value.homeLayout, 'timeline');
      expect(store.value.workspaces.notes, {'n1': 'w1', 'n2': 'w1'});
      expect(store.value.openNotes, ['kept', 'new']);
      expect(store.value.trash, {'old': 10, 'thrown': 20});
      expect(store.value.density, 'compact');
      // And that is what is kept: the stored workspaces, trash and theme were not written over.
      store.flush();
      final kept = jsonDecode((await SharedPreferences.getInstance()).getString('glyph-preferences')!) as Map<String, dynamic>;
      expect(kept['theme'], 'ember');
      expect(kept['workspaces'], {
        'list': [
          {'id': 'w1', 'name': 'Home'},
        ],
        'notes': {'n1': 'w1', 'n2': 'w1'},
      });
      expect(kept['trash'], {'old': 10, 'thrown': 20});
      expect(kept['openNotes'], ['kept', 'new']);
      expect(kept['density'], 'compact');
    });

    test('with nothing chosen meanwhile, reading what was kept writes nothing', () async {
      SharedPreferences.setMockInitialValues({'glyph-preferences': '{"theme":"light"}'});
      final store = PreferencesStore(keepAfter: Duration.zero);
      await store.load();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // To the letter: nothing rewrote it.
      expect((await SharedPreferences.getInstance()).getString('glyph-preferences'), '{"theme":"light"}');
    });

    test('keeps the haptics switch as this device’s own, on or off, apart from the preferences', () async {
      SharedPreferences.setMockInitialValues({'glyph-haptics': 'off'});
      await preferences.load();
      expect(hapticsPref.value, isFalse);
      hapticsPref.set(true);
      await Future<void>.delayed(Duration.zero);
      final kept = await SharedPreferences.getInstance();
      expect(kept.getString('glyph-haptics'), 'on');
      expect(kept.getString('glyph-preferences'), isNull);
      // On by default where there is a motor, which a test's phone has; so off is written, not left out.
      expect(hapticsAvailable(), isTrue);
      hapticsPref.set(false);
      await Future<void>.delayed(Duration.zero);
      expect(kept.getString('glyph-haptics'), 'off');
    });
  });
}

const String _web = r'''{"defaults":"{\"theme\":\"dark\",\"uiScale\":1,\"sidebarStyle\":\"popover\",\"homeLayout\":\"spotlight\",\"homeLayoutChosen\":false,\"experience\":\"advanced\",\"experienceChosen\":false,\"topBar\":\"classic\",\"accent\":\"ink\",\"density\":\"comfortable\",\"rounding\":\"round\",\"assist\":true,\"textSize\":\"large\",\"typeface\":\"inter\",\"noteFace\":\"maple\",\"refine\":true,\"quietStop\":false,\"review\":true,\"summaries\":\"meetings\",\"writeUp\":\"charging\",\"syncMeetingRecordings\":true,\"syncMeetingRecordingsChosen\":false,\"meetingSound\":false,\"localOnly\":false,\"formatModel\":\"qwen3.5-4b\",\"codeLight\":\"pastel\",\"codeDark\":\"pastel\",\"codeChosen\":false,\"noteView\":\"mixed\",\"openNotes\":[],\"tabGroups\":{\"list\":[],\"of\":{}},\"workspaces\":{\"list\":[],\"notes\":{}},\"trash\":{},\"meetings\":{},\"versions\":{},\"shares\":{},\"wisp\":true,\"wispEdge\":true,\"ripples\":true,\"motionSpeed\":\"normal\",\"linkPreviews\":true,\"canvasSnap\":true,\"mapTiles\":true,\"placeNames\":true,\"tagNewNotes\":true,\"lookUpBlanks\":true,\"autoFill\":true,\"notifications\":{\"team\":true,\"claude\":true,\"summaries\":true,\"conflicts\":true,\"mutedOrgs\":[]}}","cases":{"nothing":{"stored":null,"read":{"theme":"dark","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":false,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"comfortable","rounding":"round","assist":true,"textSize":"large","typeface":"inter","noteFace":"maple","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]}},"attrs":{"theme":"dark","note-font":"maple","code-light":"pastel","code-dark":"pastel"},"style":{"--app-motion-scale":"1"}},"empty":{"stored":{},"read":{"theme":"dark","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":false,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"comfortable","rounding":"round","assist":true,"textSize":"large","typeface":"inter","noteFace":"maple","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]}},"attrs":{"theme":"dark","note-font":"maple","code-light":"pastel","code-dark":"pastel"},"style":{"--app-motion-scale":"1"}},"notAnObject":{"stored":5,"read":{"theme":"dark","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":false,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"comfortable","rounding":"round","assist":true,"textSize":"large","typeface":"inter","noteFace":"maple","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]}},"attrs":{"theme":"dark","note-font":"maple","code-light":"pastel","code-dark":"pastel"},"style":{"--app-motion-scale":"1"}},"legacyFace":{"stored":{"typeface":"fira"},"read":{"theme":"dark","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":false,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"comfortable","rounding":"round","assist":true,"textSize":"large","typeface":"inter","noteFace":"maple","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]}},"attrs":{"theme":"dark","note-font":"maple","code-light":"pastel","code-dark":"pastel"},"style":{"--app-motion-scale":"1"}},"legacyFaceNoNote":{"stored":{"typeface":"maple","noteFace":null},"read":{"theme":"dark","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":false,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"comfortable","rounding":"round","assist":true,"textSize":"large","typeface":"inter","noteFace":"maple","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]}},"attrs":{"theme":"dark","note-font":"maple","code-light":"pastel","code-dark":"pastel"},"style":{"--app-motion-scale":"1"}},"faces":{"stored":{"typeface":"plex","noteFace":"noto"},"read":{"theme":"dark","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":false,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"comfortable","rounding":"round","assist":true,"textSize":"large","typeface":"plex","noteFace":"noto","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]}},"attrs":{"theme":"dark","note-font":"noto","code-light":"pastel","code-dark":"pastel","font":"plex"},"style":{"--app-motion-scale":"1"}},"unknowns":{"stored":{"motionSpeed":"ludicrous","theme":"neon","uiScale":3,"sidebarStyle":"floating","noteView":"hologram","accent":"blue","rounding":"squircle","topBar":"strip","homeLayout":"sideways","homeLayoutChosen":true,"summaries":"all","writeUp":"overnight","syncMeetingRecordings":"yes","meetingSound":"yes","canvasSnap":1,"lookUpBlanks":null,"autoFill":"no"},"read":{"theme":"dark","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":true,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"comfortable","rounding":"round","assist":true,"textSize":"large","typeface":"inter","noteFace":"maple","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]}},"attrs":{"theme":"dark","note-font":"maple","code-light":"pastel","code-dark":"pastel"},"style":{"--app-motion-scale":"1"}},"chosen":{"stored":{"theme":"ember","accent":"amber","uiScale":1.1,"density":"more-space","rounding":"rounder","textSize":"largest","typeface":"noto","noteFace":"inter","topBar":"islands","homeLayout":"timeline","homeLayoutChosen":true,"codeLight":"github","codeDark":"nord","codeChosen":true,"motionSpeed":"brisk","sidebarStyle":"docked","noteView":"formatted"},"read":{"theme":"ember","uiScale":1.1,"sidebarStyle":"docked","homeLayout":"timeline","homeLayoutChosen":true,"experience":"advanced","experienceChosen":false,"topBar":"islands","accent":"amber","density":"more-space","rounding":"rounder","assist":true,"textSize":"largest","typeface":"noto","noteFace":"inter","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"github","codeDark":"nord","codeChosen":true,"noteView":"formatted","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"brisk","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]}},"attrs":{"theme":"dark","note-font":"inter","code-light":"github","code-dark":"nord","theme-preset":"ember","density":"more-space","topbar":"islands","accent":"amber","rounding":"rounder","text-size":"largest","font":"noto"},"style":{"font-size":"110%","--glacier-duration-instant":"45ms","--glacier-duration-fast":"90ms","--glacier-duration-normal":"150ms","--glacier-duration-slow":"240ms","--glacier-duration-slower":"360ms","--app-motion-scale":"0.6"}},"notChosen":{"stored":{"homeLayout":"cards","codeLight":"ink","codeDark":"ink"},"read":{"theme":"dark","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":false,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"comfortable","rounding":"round","assist":true,"textSize":"large","typeface":"inter","noteFace":"maple","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]}},"attrs":{"theme":"dark","note-font":"maple","code-light":"pastel","code-dark":"pastel"},"style":{"--app-motion-scale":"1"}},"travels":{"stored":{"openNotes":["n0","n1",7,null,"n2","n3","n4","n5","n6","n7","n8","n9"],"tabGroups":{"list":[{"id":"g1","name":"Work","hue":"teal"},{"id":"g2","name":"No colour"},"rubbish",{"id":3,"name":"Bad id","hue":"red"}],"of":{"a":"g1","b":"g2","c":"gone","d":4}},"workspaces":{"list":[{"id":"w1","name":"Home"},{"id":"w2"},null,{"id":"w3","name":"Work","hue":"moss"}],"notes":{"a":"w1","b":"w2","c":5,"d":"w3"}},"trash":{"a":10,"b":"yesterday","c":null},"meetings":{"a":1759000000000,"b":"yesterday"},"versions":{"a":true,"b":false,"c":"yes"},"shares":{"good":{"id":"AAAAAAAAAAAAAAAAAAAAAA","key":"b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_","sent":"p2:9","lacked":["x.jpg",4],"place":true},"unsent":{"id":"AAAAAAAAAAAAAAAAAAAAAA","key":"b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_"},"short":{"id":"abc","key":"b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_"},"spaced":{"id":"AAAAAAAAAAAAAAAAAAAAAA","key":"not a key at all, not at all"},"none":null,"said":{"id":"AAAAAAAAAAAAAAAAAAAAAA","key":"b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_","sent":"","place":false,"places":true}},"notifications":{"team":false,"mutedOrgs":["o1",7,null]}},"read":{"theme":"dark","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":false,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"comfortable","rounding":"round","assist":true,"textSize":"large","typeface":"inter","noteFace":"maple","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":["n2","n3","n4","n5","n6","n7","n8","n9"],"tabGroups":{"list":[{"id":"g1","name":"Work","hue":"teal"}],"of":{"a":"g1"}},"workspaces":{"list":[{"id":"w1","name":"Home"},{"id":"w3","name":"Work","hue":"moss"}],"notes":{"a":"w1","d":"w3"}},"trash":{"a":10},"meetings":{"a":1759000000000},"versions":{"a":true,"b":false},"shares":{"good":{"id":"AAAAAAAAAAAAAAAAAAAAAA","key":"b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_","sent":"p2:9","lacked":["x.jpg"],"place":true},"unsent":{"id":"AAAAAAAAAAAAAAAAAAAAAA","key":"b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_","sent":""},"said":{"id":"AAAAAAAAAAAAAAAAAAAAAA","key":"b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_b_","sent":"","places":true}},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":false,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":["o1"]}},"attrs":{"theme":"dark","note-font":"maple","code-light":"pastel","code-dark":"pastel"},"style":{"--app-motion-scale":"1"}},"odd":{"stored":{"openNotes":"n1","tabGroups":{"list":"no"},"workspaces":"none","trash":"none","meetings":"none","versions":4,"shares":[],"notifications":"all","textSize":"huge","density":"airy","formatModel":"gemma-3n"},"read":{"theme":"dark","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":false,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"airy","rounding":"round","assist":true,"textSize":"huge","typeface":"inter","noteFace":"maple","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"gemma-3n","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]}},"attrs":{"theme":"dark","note-font":"maple","code-light":"pastel","code-dark":"pastel","density":"airy","text-size":"huge"},"style":{"--app-motion-scale":"1"}},"newer":{"stored":{"somethingNew":{"a":1},"anotherKey":"kept","theme":"light"},"read":{"theme":"light","uiScale":1,"sidebarStyle":"popover","homeLayout":"spotlight","homeLayoutChosen":false,"experience":"advanced","experienceChosen":false,"topBar":"classic","accent":"ink","density":"comfortable","rounding":"round","assist":true,"textSize":"large","typeface":"inter","noteFace":"maple","refine":true,"quietStop":false,"review":true,"summaries":"meetings","writeUp":"charging","syncMeetingRecordings":true,"syncMeetingRecordingsChosen":false,"meetingSound":false,"localOnly":false,"formatModel":"qwen3.5-4b","codeLight":"pastel","codeDark":"pastel","codeChosen":false,"noteView":"mixed","openNotes":[],"tabGroups":{"list":[],"of":{}},"workspaces":{"list":[],"notes":{}},"trash":{},"meetings":{},"versions":{},"shares":{},"wisp":true,"wispEdge":true,"ripples":true,"motionSpeed":"normal","linkPreviews":true,"canvasSnap":true,"mapTiles":true,"placeNames":true,"tagNewNotes":true,"lookUpBlanks":true,"autoFill":true,"notifications":{"team":true,"claude":true,"summaries":true,"conflicts":true,"mutedOrgs":[]},"somethingNew":{"a":1},"anotherKey":"kept"},"attrs":{"theme":"light","note-font":"maple","code-light":"pastel","code-dark":"pastel"},"style":{"--app-motion-scale":"1"}}}}''';
