import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/export_all.dart';
import 'package:ghost_md/core/library_folder.dart' show filesChannel;
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/events.dart';

/// Everything as one zip (lib/core/export_all.dart; docs/DESIGN.md §167 of tauri/): the archive's name, what the
/// app writes into it, where it can go, Android's picker and descriptor, and what is said after. A port of
/// `src/app/core/exportAll.test.ts`, without the browser's export and the Mac's panel, which this app has not: the
/// core, its job and the activity are stood in for; the activity's own words are read out of its Kotlin.
final at = DateTime(2026, 10, 1, 21, 42, 5);
const done = Exported(name: 'ghostmarkdown_2026-10-01_21-42-05.zip', notes: 12, files: 40, bytes: 9000000, written: 8100000);

void main() {
  late List<String> calls;
  late List<Map<String, Object?>> runs;
  late List<String> commands;
  Object? failure;

  ExportAll export({String? answer, TargetPlatform platform = TargetPlatform.android, Map<String, String> kept = const {}}) => ExportAll(
        invoke: (command, [args = const {}]) async {
          commands.add(command);
          return null;
        },
        platform: platform,
        kept: (key) => kept[key],
        picker: answer == null
            ? null
            : ExportPicker(
                choose: (name) async {
                  calls.add('choose $name');
                  return answer;
                },
                done: () => calls.add('done'),
                discard: () => calls.add('discard'),
              ),
        run: (args, onProgress) async {
          runs.add(args);
          onProgress(const ExportProgress(done: 5, total: 10, files: 1, of: 2));
          if (failure != null) throw failure!;
          return done;
        },
      );

  setUp(() {
    calls = [];
    runs = [];
    commands = [];
    failure = null;
  });

  group('the archive’s name', () {
    test('is ghostmarkdown_, the day and the time on the device’s clock, with no colon a USB drive would refuse', () {
      expect(exportName(at), 'ghostmarkdown_2026-10-01_21-42-05.zip');
      expect(exportName(DateTime(2027, 1, 9, 7, 3, 9)), 'ghostmarkdown_2027-01-09_07-03-09.zip');
    });
  });

  group('what the app writes into it', () {
    test('carries the settings, and never an account, a key or a token', () {
      final kept = {
        'glyph-preferences': jsonEncode({'theme': 'dark'}),
        'glyph-plugins': jsonEncode({'marks': true}),
        'glyph-workspace-current': 'work',
        'glyph-account-session': jsonEncode({'token': 'secret'}),
        'glyph-github-token': 'ghp_secret',
      };
      final file = settingsFile((key) => kept[key]);
      expect(jsonDecode(file), {'glyph-preferences': {'theme': 'dark'}, 'glyph-plugins': {'marks': true}, 'glyph-workspace-current': 'work'});
      expect(file, isNot(contains('secret')));
    });

    test('strips the share keys, the calendars, the webhooks and every sealed value out of the preferences, and keeps the rest', () {
      final prefs = {
        'theme': 'dark',
        'workspaces': {'list': [{'id': 'w-1', 'name': 'Work'}], 'notes': {'n1': 'w-1'}},
        'trash': {'n2': 1},
        'meetings': {'n3': 2},
        'shares': {'n1': {'id': 'abcdefghijklmnop', 'key': 'KEYKEYKEYKEYKEYK', 'sent': 'x'}},
        // An older build's blob, the secrets still in the clear (lib/calendar/setup.dart `storedInTheClear`), beside a
        // newer one's id and name.
        'calendars': {'addresses': [{'id': 'e776f1db', 'url': 'https://cal.test/secretfeed.ics', 'name': 'Work'}, {'id': 'a1b2c3', 'name': 'Home'}], 'google': {'refreshToken': 'REFRESH', 'ticked': ['me@example.com']}, 'sources': ['https://calendar.google.com/ical/secretfeed']},
        'webhooks': [{'id': 'h1', 'url': 'https://example.com/hook', 'secret': 'HOOKSECRET'}],
        'sealedKeys': {'anthropic': 'SEALED'},
        'more': {'github': {'token': 'ghp_nested'}, 'kept': true},
      };
      final file = settingsFile((key) => key == 'glyph-preferences' ? jsonEncode(prefs) : null);
      final out = (jsonDecode(file) as Map)['glyph-preferences'] as Map;
      expect(out.keys, ['theme', 'workspaces', 'trash', 'meetings', 'calendars', 'more']);
      expect(out['more'], {'github': {}, 'kept': true}, reason: 'the token goes, the key that held it stays');
      // The calendars' ids, names and choices stay (decision 22 keeps the secrets out of the blob); the addresses go.
      expect(out['calendars'], {'addresses': [{'id': 'e776f1db', 'name': 'Work'}, {'id': 'a1b2c3', 'name': 'Home'}], 'google': {'ticked': ['me@example.com']}, 'sources': <Object?>[]});
      for (final leak in ['KEYKEYKEY', 'REFRESH', 'secretfeed', 'HOOKSECRET', 'SEALED', 'ghp_nested', 'abcdefghijklmnop']) {
        expect(file, isNot(contains(leak)));
      }
      expect(secretPreferenceKeys, {'shares', 'webhooks', 'sealedKeys'});
      expect(readme(exportName(at), at), isNot(contains('No account, password or key')));
      expect(readme(exportName(at), at), contains('share links, calendars and webhooks are left out'));
      expect(file, endsWith('}\n'));
      expect(settingsFile((key) => null), '{}\n');
      expect(settingsFile((key) => throw StateError('refused')), '{}\n', reason: 'storage that will not answer is no settings');
      expect(settingsKeys, ['glyph-preferences', 'glyph-plugins', 'glyph-workspace-current', 'glyph-note-bookmarks', 'glyph-book-spots']);
    });

    test('says what every folder is in a README', () {
      final text = readme(exportName(at), at);
      for (final folder in ['Library/', 'Library/image/', 'Library/file/', 'Library/video/', 'Library/recordings/', 'settings.json', 'manifest.json']) {
        expect(text, contains(folder));
      }
      expect(text, contains('ghostmarkdown_2026-10-01_21-42-05/'));
      expect(text.split('\n').first, 'Ghost.md, exported 10/1/2026, 9:42:05 PM');
    });

    group('says when in the phone’s own words (core/locale_dates.dart)', () {
      tearDown(() => toldLocale = null);

      test('an American phone has the month first and a 12-hour clock', () {
        toldLocale = DateLocale.enUS;
        expect(readme(exportName(at), at).split('\n').first, 'Ghost.md, exported 10/1/2026, 9:42:05 PM');
      });

      test('a British phone has the day first, two figures each, and a 24-hour clock', () {
        toldLocale = DateLocale.enGB;
        expect(readme(exportName(at), at).split('\n').first, 'Ghost.md, exported 01/10/2026, 21:42:05');
      });
    });
  });

  group('where it can go', () {
    test('is Android’s picker, an update where this build has none, and nowhere on an iPhone', () async {
      expect(await export(answer: '{}').way(), ExportWay.android);
      expect(await export().way(), ExportWay.update);
      // The Mac app's save panel answers as Android's picker does; a Mac run without it (a test, a desktop run
      // outside the app) has no way yet.
      expect(await export(answer: '{}', platform: TargetPlatform.macOS).way(), ExportWay.mac);
      expect(await export(platform: TargetPlatform.macOS).way(), ExportWay.update);
      expect(await export(answer: '{}', platform: TargetPlatform.iOS).way(), ExportWay.none);
      expect(exportGeneration, 22);
      await expectLater(export().exportEverything((_) {}, at: at), throwsA(isA<StateError>().having((e) => e.message, 'message', 'Update Ghost.md to export everything.')));
      await expectLater(export(platform: TargetPlatform.iOS).exportEverything((_) {}, at: at), throwsA(isA<StateError>().having((e) => e.message, 'message', 'Exporting isn’t on iPhone yet.')));
    });
  });

  group('on Android', () {
    test('writes into the file the picker made, by its descriptor, and keeps it', () async {
      final heard = <ExportProgress>[];
      final wrote = await export(answer: '{"fd":87,"name":"ghostmarkdown_2026-10-01_21-42-05 (1).zip"}', kept: {'glyph-plugins': '{"marks":true}'}).exportEverything(heard.add, at: at);
      expect(calls, ['choose ghostmarkdown_2026-10-01_21-42-05.zip', 'done']);
      expect(wrote, done.named('ghostmarkdown_2026-10-01_21-42-05 (1).zip'));
      final sent = runs.single;
      expect(sent['fd'], 87);
      final request = sent['request']! as Map<String, Object?>;
      expect(request['name'], 'ghostmarkdown_2026-10-01_21-42-05.zip');
      expect(request['offsetMinutes'], at.timeZoneOffset.inMinutes);
      expect(request['page'], 'flutter');
      expect(request['exportedAt'], matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$')));
      final files = (request['files']! as List).cast<Map<String, Object?>>();
      expect(files.map((file) => file['name']), ['README.txt', 'settings.json']);
      expect(jsonDecode(files[1]['text']! as String), {'glyph-plugins': {'marks': true}});
      expect(heard.single.of, 2);
    });

    test('answers nothing when the picker is closed, and asks Rust for nothing', () async {
      expect(await export(answer: '{"cancelled":true}').exportEverything((_) {}, at: at), isNull);
      expect(runs, isEmpty);
      expect(calls, ['choose ghostmarkdown_2026-10-01_21-42-05.zip']);
    });

    test('takes the half-written file away when the export fails, and says why', () async {
      failure = const CoreError('The drive is full.');
      await expectLater(export(answer: '{"fd":87,"name":"x.zip"}').exportEverything((_) {}, at: at), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'The drive is full.')));
      expect(calls, ['choose ghostmarkdown_2026-10-01_21-42-05.zip', 'discard']);
      await expectLater(export(answer: '{"error":"That place can’t be written to."}').exportEverything((_) {}, at: at), throwsA(isA<StateError>().having((e) => e.message, 'message', 'That place can’t be written to.')));
    });

    test('reads the picker’s answer, and anything else as a place it cannot write', () {
      expect(readTargetAnswer('{"fd":87,"name":"a.zip"}'), const TargetMade(87, 'a.zip'));
      expect(readTargetAnswer('{"cancelled":true}'), const TargetCancelled());
      expect(readTargetAnswer('{"error":"No."}'), const TargetRefused('No.'));
      for (final odd in ['{"fd":1}', '{"fd":"87"}', '{"fd":87.5}', 'nonsense', '[]']) {
        expect(readTargetAnswer(odd), const TargetRefused('That place can’t be written to.'), reason: odd);
      }
    });

    test('uses the activity’s own words for the channel and the answer', () async {
      String kotlin(String path) => File('android/app/src/main/kotlin/com/mattssoftware/$path').readAsStringSync();
      final bridge = kotlin('ghost_md/FilesBridge.kt');
      expect(bridge, contains('const val CHANNEL = "${filesChannel.name}"'));
      for (final method in ['chooseExport', 'exportDone', 'discardExport']) {
        expect(bridge, contains('"$method" ->'));
      }
      expect(bridge, contains('call.argument<String>("name")'));
      final target = kotlin('glyph/files/ExportTarget.kt');
      expect(target, contains('put("fd", fd)'));
      expect(target, contains('put("cancelled", true)'));
      expect(target, contains('const val NO_PICKER = "This phone has no way to choose where to save."'));
      expect(target, contains('const val UNWRITABLE = "That place can’t be written to."'));
      // And with no phone half behind the channel, the picker says what the page said of a shell without one.
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(readTargetAnswer(await ExportPicker.phone.choose('x.zip')), const TargetRefused('This phone has no way to choose where to save.'));
    });

    test('is a job over the core, heard as it goes, and stopped by its own command', () async {
      final events = StreamController<CoreEvent>.broadcast(sync: true);
      final end = Completer<Object?>();
      final started = <(String, Map<String, Object?>)>[];
      final run = coreExportRun(
        startJob: (command, [args = const {}]) async {
          started.add((command, args));
          return CoreJob('j1', const Stream.empty(), end.future, () async => true);
        },
        events: events.stream,
      );
      final heard = <ExportProgress>[];
      final wrote = run({'request': {'name': 'x.zip'}, 'fd': 9}, heard.add);
      await pumpEventQueue();
      expect(started.single.$1, 'export_fd');
      expect(started.single.$2['fd'], 9);
      events.add(const CoreEvent('export://progress', {'done': 1, 'total': 4, 'files': 0, 'of': 2}));
      events.add(const CoreEvent('backup://progress', {'done': 9, 'total': 9, 'files': 9, 'of': 9}));
      expect(heard.map((p) => (p.done, p.total, p.files, p.of)), [(1, 4, 0, 2)]);
      end.complete({'name': 'x.zip', 'notes': 2, 'files': 3, 'bytes': 4, 'written': 5});
      expect(await wrote, const Exported(name: 'x.zip', notes: 2, files: 3, bytes: 4, written: 5));
      expect(events.hasListener, isFalse);
      await events.close();
      export(answer: '{}').cancel();
      expect(commands, ['export_cancel']);
    });
  });

  group('what it says it wrote', () {
    test('counts the notes, then the other files, and the archive’s size and name', () {
      expect(doneSaid(done), 'Exported 12 notes and 28 other files, 8.1 MB, as ghostmarkdown_2026-10-01_21-42-05.zip.');
      expect(doneSaid(const Exported(name: 'ghostmarkdown_2026-10-01_21-42-05.zip', notes: 1, files: 1, bytes: 9000000, written: 2000)), 'Exported one note, 2 KB, as ghostmarkdown_2026-10-01_21-42-05.zip.');
      expect(doneSaid(const Exported(name: 'ghostmarkdown_2026-10-01_21-42-05.zip', notes: 3, files: 4, bytes: 9000000, written: 8100000)), 'Exported 3 notes and one other file, 8.1 MB, as ghostmarkdown_2026-10-01_21-42-05.zip.');
    });
  });

  group('a size', () {
    test('is said the way a person reads it', () {
      expect([sizeSaid(512), sizeSaid(820000), sizeSaid(1400000000), sizeSaid(12500000)], ['512 bytes', '820 KB', '1.4 GB', '13 MB']);
    });
  });
}
