// What an iPhone is shown where the other builds speak of recording, a model or another platform (Matt,
// 2026-10-13, before the Flutter build went to the App Store): the iPhone app records nothing and runs no model
// (lib/core/iphone_app.dart), so its words leave them out, and nothing changes for a phone that records or a Mac.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/lessons.dart';
import 'package:ghost_md/canvas/how_canvas.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/guide/pages.dart';
import 'package:ghost_md/guide/too_soon.dart';
import 'package:ghost_md/settings/panes/about_pane.dart';
import 'package:ghost_md/settings/settings_sheet.dart';

import 'support.dart';

/// Words no iPhone page of these may hold: another platform, a key an iPhone has not, a recorder, a model.
final RegExp _notOnIPhone = RegExp(r'android|side key|microphone|voice|record|spoken|\bsay\b|\bsaid\b|hears|the model|\bfold\b', caseSensitive: false);

String _shown(WidgetTester tester) => tester.widgetList<Text>(find.byType(Text)).map((text) => text.data ?? text.textSpan?.toPlainText() ?? '').join('\n');

void main() {
  group('The “How Ghost.md works” canvas', () {
    test('is the web app’s where the app records, and the same cards with typed words on an iPhone', () {
      final spoken = howCanvas(voice: true), typed = howCanvas(voice: false);
      expect(spoken.nodeOf('speak')!.text, contains('press the side key'));
      expect(typed.nodes.map((node) => node.id), spoken.nodes.map((node) => node.id));
      expect(typed.edges, spoken.edges);
      for (final node in typed.nodes) {
        final twin = spoken.nodeOf(node.id)!;
        expect((node.x, node.y, node.width, node.height, node.color), (twin.x, twin.y, twin.width, twin.height, twin.color));
      }
      expect(serializeCanvas(typed), isNot(matches(_notOnIPhone)));
      expect(typed.nodeOf('speak')!.text, startsWith('# Write it'));
      expect(howCanvasBody(voice: false), contains('From your words to the page'));
    });

    test('asks the platform when it is not told', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final iPhone = howCanvas();
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final android = howCanvas();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final mac = howCanvas();
      debugDefaultTargetPlatformOverride = null;
      expect(iPhone, howCanvas(voice: false));
      expect(android, howCanvas(voice: true));
      expect(mac, howCanvas(voice: true));
    });
  });

  group('The sample note', () {
    test('on an iPhone teaches every mark by what to type and says nothing of saying one', () {
      final typed = sampleNoteTyped();
      expect(typed, isNot(contains('Say "')));
      expect(typed, isNot(matches(RegExp(r'\b(say|recording|voice|microphone)\b', caseSensitive: false))));
      // Every heading and every example line of the note is still there: only sentences went.
      final kept = sampleNoteBody.split('\n').where((line) => line.startsWith('#') || line.startsWith('- ') || line.startsWith('|') || line.startsWith('```')).toList();
      for (final line in kept) {
        expect(typed.split('\n'), contains(line), reason: line);
      }
      expect(typed.split('\n').length, sampleNoteBody.split('\n').length);
      // No sentence left half cut: no line starts or ends with a space, and none has two together.
      final were = sampleNoteBody.split('\n').toSet();
      final changed = typed.split('\n').where((line) => !were.contains(line) && !line.contains('A[Write it]')).toList();
      expect(changed, isNotEmpty);
      for (final line in changed) {
        expect(line, isNot(matches(RegExp(r'^ |  | $'))), reason: line);
        expect(line, matches(RegExp(r'[.:)\]]$')), reason: line);
      }
      expect(typed, contains('Type `#` and a space for the note\'s name, `##` for a section, and more hashes, up to six, for smaller ones.\n'));
      expect(typed, contains('\nAn effect lifts while the caret is in its words'));
      expect(typed, contains('> Write it now, and fix it after.'));
    });

    test('is the web app’s where the app records, with or without its picture', () {
      expect(sampleNoteWith(null, voice: true), sampleNoteBody);
      expect(sampleNoteWith('a.jpg', voice: true), contains('Say "heading"'));
      expect(sampleNoteWith('a.jpg', voice: false), allOf(contains('## Pictures'), isNot(contains('Say "'))));
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final iPhone = sampleNoteWith(null);
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final mac = sampleNoteWith(null);
      debugDefaultTargetPlatformOverride = null;
      expect(iPhone, sampleNoteTyped());
      expect(mac, sampleNoteBody);
    });
  });

  group('The Academy’s video lesson', () {
    test('names Android and its + everywhere but on an iPhone', () {
      final video = lessons.firstWhere((lesson) => lesson.id == 'video');
      expect(teachOf(video, voice: true), video.teach);
      expect(taskOf(video, voice: true), video.task);
      expect(video.teach, contains('on Android'));
      expect(teachOf(video, voice: false), isNot(matches(RegExp(r'Android|the \+'))));
      expect(taskOf(video, voice: false), 'Write a video’s line.');
      // No other lesson is reworded, and none names another platform.
      for (final lesson in lessons.where((lesson) => lesson.id != 'video')) {
        expect(teachOf(lesson, voice: false), lesson.teach);
        expect(taskOf(lesson, voice: false), lesson.task);
        expect('${lesson.teach} ${lesson.task} ${lesson.hint} ${lesson.praise}', isNot(matches(RegExp(r'Android|side key|\bMac\b|Windows'))), reason: lesson.id);
      }
    });
  });

  group('The walkthrough', () {
    test('has no model page on an iPhone, nor the pages on speaking and the AI it has not, and its last page is the last', () {
      expect(walkthroughPagesNow, GuidePage.values);
      expect(isReadingPage(5), isTrue);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final pages = walkthroughPagesNow;
      final reading = [isReadingPage(4), isReadingPage(5)];
      debugDefaultTargetPlatformOverride = null;
      expect(pages, [GuidePage.welcome, GuidePage.meetings, GuidePage.sync, GuidePage.market, GuidePage.mode, GuidePage.start]);
      expect(reading, [true, false]);
    });
  });

  group('Settings on an iPhone', () {
    test('About’s row says whose the updates are, where another build says how its check stands', () {
      expect(updatesSummary(SettingsUpdates(version: '2.0.5', store: 'appstore')), 'Updates through the App Store');
      expect(updatesSummary(SettingsUpdates(version: '2.0.5', onCheck: () {})), 'Not checked yet');
    });

    testWidgets('About offers no Guide and promises no model; elsewhere both are as they were', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await openPane(tester, 'about');
      final labels = rowLabels(tester), shown = _shown(tester);
      final findable = aboutFindable(updates: false, alerts: false, whatsNew: false).map((found) => found.name).toList();
      debugDefaultTargetPlatformOverride = null;
      expect(labels.take(5), ['Ghost.md Academy', 'The welcome walkthrough', 'Cheat sheet', 'Specification', 'Examples']);
      expect(shown, contains('The tour from the first launch, read aloud: what it does, and where the rest is taught.'));
      expect(shown, isNot(contains('model')));
      expect(findable, isNot(contains('Ghost.md: The Guide')));
      await endSettings(tester);

      await openPane(tester, 'about');
      expect(rowLabels(tester).take(6), ['Ghost.md Academy', 'The welcome walkthrough', 'Cheat sheet', 'Specification', 'Ghost.md: The Guide', 'Examples']);
      expect(_shown(tester), contains('The tour from the first launch, read aloud: what it does, and where the rest is taught.'));
      expect(aboutFindable(updates: false, alerts: false, whatsNew: false).map((found) => found.name), contains('Ghost.md: The Guide'));
      await endSettings(tester);
    });

    testWidgets('Examples says write it; Account and Privacy say nothing of recordings; Appearance has no ripples', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      await openPane(tester, 'examples');
      final examples = _shown(tester);
      await endSettings(tester);
      await openPane(tester, 'account', size: const Size(390, 2400));
      final account = _shown(tester);
      await endSettings(tester);
      await openPane(tester, 'theme', size: const Size(390, 3600));
      final appearance = rowLabels(tester);
      await endSettings(tester);
      await openPane(tester, 'notifications', size: const Size(390, 1600));
      final notifications = _shown(tester);
      debugDefaultTargetPlatformOverride = null;
      await endSettings(tester);

      expect(examples, contains('Eight plain cards, in order: write it, it lands as a note, and where a note can go.'));
      expect(account, contains('Keep your notes and settings the same on your phone and computer.'));
      expect(account, contains('Your notes and pictures stay on this device. Signed in, they sync encrypted on the device first'));
      expect(account, contains('Every note you make here starts with where you were. Off,'));
      expect(account, isNot(matches(RegExp(r'recording|voice|spoken|the model|microphone', caseSensitive: false))));
      expect(appearance, contains('Blur at the edges'));
      expect(appearance, isNot(contains('Ripples while recording')));
      expect(notifications, contains('A meeting written up on another of your devices.'));
      expect(notifications, isNot(contains('under Recording')));

      await openPane(tester, 'account', size: const Size(390, 2400));
      expect(_shown(tester), contains('Keep your notes, recordings and settings the same on your phone and computer.'));
      expect(_shown(tester), contains('and your voice is turned into text here.'));
      expect(_shown(tester), contains('where you were, typed or spoken. Off,'));
      await endSettings(tester);
      await openPane(tester, 'theme', size: const Size(390, 3600));
      expect(rowLabels(tester), contains('Ripples while recording'));
      await endSettings(tester);
    });
  });
}
