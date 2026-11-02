import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/courses.dart';
import 'package:ghost_md/academy/lessons.dart';
import 'package:ghost_md/academy/voice.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/guide/narrator.dart';

import 'support.dart';

/// The Academy read aloud and in colour (Matt, 2026-10-28: "Add the voiceover to the academy sections and spice up
/// the academy with more colors and iconography"): every clip made from the words voice.dart has now, as the
/// walkthrough's test holds its own (test/guide/narration_test.dart); a welcome on the catalog, a course's hello
/// then the lesson as a course is begun, the lesson alone after that, quiet on the catalog and a course's page, the
/// walkthrough's speaker and its remembered switch; every course a colour and a sign; and Simple's More.
class FakeVoice implements NarrationOutput {
  final List<String> calls = [];

  @override
  Future<bool> narrate(String key, Uint8List bytes) async {
    calls.add('narrate ${key.split('/').last}');
    return true;
  }

  @override
  Future<void> hush() async => calls.add('hush');
}

void main() {
  setUpAll(loadAppFonts);

  final manifest = jsonDecode(File(academyVoiceManifest).readAsStringSync()) as Map<String, dynamic>;
  final files = (manifest['files'] as Map<String, dynamic>).cast<String, Map<String, dynamic>>();
  String digest(String words) => sha256.convert(utf8.encode(words)).toString().substring(0, 16);

  group('the words and the files', () {
    test('have every file made from the words voice.dart has now', () {
      for (final MapEntry(key: name, value: words) in academyVoice.entries) {
        final made = files[name];
        expect(made, isNotNull, reason: '$name has no voice yet; run python3 tool/academy_voice.py');
        expect(made!['words'], digest(words), reason: '$name: its words changed; run python3 tool/academy_voice.py');
        expect(File(academyVoiceAsset(name)).existsSync(), isTrue, reason: name);
      }
      expect(files.keys.toSet(), academyVoice.keys.toSet(), reason: 'a file for words that are gone');
    });

    test('read the words the way the tool does', () {
      // tool/academy_voice.py's pattern over voice.dart: an entry it cannot read would be a clip with no voice.
      final source = File('lib/academy/voice.dart').readAsStringSync();
      final read = {for (final m in RegExp(r"^\s*'([\w-]+)':\s*'((?:[^'\\]|\\.)*)',\s*$", multiLine: true).allMatches(source)) m[1]!: m[2]!};
      expect(read, academyVoice);
    });

    test('have a welcome, a hello for every chapter and every lesson, plugin marks too, small enough to carry', () {
      expect(academyVoice.keys, contains('welcome'));
      expect(chapterVoiceNames.keys.toList(), chapters);
      for (final chapter in chapters) {
        expect(academyVoice[chapterVoice(chapter)], isNotEmpty, reason: chapter);
      }
      for (final lesson in lessons) {
        expect(academyVoice[lesson.id], isNotEmpty, reason: lesson.id);
        // Said, not shown: no mark a voice would read out symbol by symbol.
        expect(academyVoice[lesson.id], isNot(matches(RegExp(r'\*\*|~~|==|```|\[\[|\]\]|%%|@@|\^\^|\+\+|\|\|'))), reason: lesson.id);
      }
      for (final made in files.values) {
        expect(made['model'], 'eleven_v4');
        expect(made['voice'], 'cgSgspJ2msm6clMCkdW9');
        expect(made['seconds'] as num, greaterThan(1));
      }
      final total = files.values.fold<int>(0, (sum, made) => sum + (made['bytes'] as int));
      expect(total, lessThan(6 * 1024 * 1024));
    });

    test('give each course a sign of its own, and each course on a shelf a colour of its own', () {
      expect(courses.map((course) => course.look.icon).toSet(), hasLength(courses.length));
      for (final shelf in CourseShelf.values) {
        final on = courses.where((course) => course.shelf == shelf);
        expect(on.map((course) => course.look.hues.first).toSet(), hasLength(on.length), reason: shelf.name);
      }
    });
  });

  group('the voice', () {
    Future<ByteData> anyFile(String asset) async => ByteData(8);

    Future<(FakeVoice, VoiceOver)> open(WidgetTester tester, {Set<String>? learned}) async {
      freshDevice(learned: learned);
      // The clips' lengths, read for real once, as the app reads them before a chapter is begun.
      await tester.runAsync(academyVoiceLengths);
      final fake = FakeVoice();
      final voice = VoiceOver(output: fake, load: anyFile);
      addTearDown(voice.dispose);
      await showAcademy(tester, voice: voice);
      await settle(tester, 2);
      return (fake, voice);
    }

    List<String> said(FakeVoice fake) => fake.calls.where((call) => call.startsWith('narrate')).toList();

    testWidgets('welcomes on the catalog, then says a course’s hello and its lesson, and the lesson alone after that', (tester) async {
      final (fake, _) = await open(tester);
      expect(said(fake), ['narrate welcome.mp3']);
      fake.calls.clear();
      await press(tester, key('academy-go'));
      // The hello now, the lesson once the hello has had its length and a breath.
      expect(said(fake), ['narrate chapter-basics.mp3']);
      final hello = Duration(milliseconds: ((files['chapter-basics']!['seconds'] as num) * 1000).round());
      await tester.pump(hello + VoiceOver.breath);
      await tester.pump();
      expect(said(fake), ['narrate chapter-basics.mp3', 'narrate title.mp3']);
      fake.calls.clear();
      await press(tester, find.text('Skip'));
      expect(fake.calls, ['hush', 'narrate heading.mp3']);
      await away(tester);
    });

    testWidgets('stops a lesson’s hello and what follows when the page turns, and is quiet on a course’s page and the catalog', (tester) async {
      final (fake, _) = await open(tester);
      await press(tester, key('academy-go'));
      fake.calls.clear();
      await press(tester, find.bySemanticsLabel('The course’s lessons'));
      expect(fake.calls, ['hush']);
      await press(tester, find.bySemanticsLabel('All courses'));
      await tester.pump(const Duration(seconds: 30));
      expect(said(fake), isEmpty);
      // Begun again from the catalog, the course says hello again.
      await press(tester, key('academy-go'));
      expect(said(fake), ['narrate chapter-basics.mp3']);
      await away(tester);
      expect(fake.calls.last, 'hush');
    });

    testWidgets('keeps quiet once the speaker is off, remembered for the walkthrough too, and stops as the app leaves', (tester) async {
      final (fake, voice) = await open(tester);
      fake.calls.clear();
      await press(tester, key('academy-voice'));
      expect(fake.calls, ['hush']);
      expect(stored.readText(guideMutedKey), '1');
      await press(tester, key('academy-go'));
      expect(said(fake), isEmpty);
      await press(tester, key('academy-voice'));
      expect(said(fake), ['narrate chapter-basics.mp3']);
      fake.calls.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(fake.calls, contains('hush'));
      expect(voice.sayingAsset, isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await away(tester);
    });
  });

  group('the look', () {
    testWidgets('heads the contents, each lesson and a chapter’s end with a band, and names the Academy Ghost', (tester) async {
      freshDevice();
      await showAcademy(tester);
      expect(find.text('Ghost Academy'), findsOneWidget);
      expect(key('academy-band'), findsOneWidget);
      await press(tester, key('academy-go'));
      expect(key('academy-band'), findsOneWidget);
      expect(tester.widget<Text>(key('academy-band-mark')).data, lessons.first.symbol);
      await away(tester);
    });

    testWidgets('in Simple, shows the Markdown courses and opens the rest in place behind More', (tester) async {
      freshDevice();
      await showAcademy(tester, simple: true, size: const Size(390, 6000));
      expect(key('course:basics'), findsOneWidget);
      expect(key('course:more'), findsOneWidget);
      expect(key('course:marks'), findsNothing);
      await press(tester, key('academy-more-courses'));
      for (final course in courses) {
        expect(key('course:${course.id}'), findsOneWidget, reason: course.id);
      }
      expect(key('academy-more-courses'), findsNothing);
      await away(tester);
    });

    testWidgets('says nothing for a lesson that has no clip yet, and its course no hello', (tester) async {
      freshDevice();
      await tester.runAsync(academyVoiceLengths);
      final fake = FakeVoice();
      final voice = VoiceOver(output: fake, load: (_) async => ByteData(8));
      addTearDown(voice.dispose);
      await showAcademy(tester, voice: voice);
      await settle(tester, 2);
      expect(academyVoice.containsKey('gantt'), isFalse);
      fake.calls.clear();
      await press(tester, key('course:gantt'));
      await press(tester, key('academy-course-start'));
      await tester.pump(const Duration(seconds: 10));
      expect(fake.calls.where((call) => call.startsWith('narrate')), isEmpty);
      await away(tester);
    });
  });
}
