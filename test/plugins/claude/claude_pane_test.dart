import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/claude/claude.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';

import '../../settings/support.dart';
import '../../support/icons.dart';

/// Settings › Claude (lib/plugins/claude/claude_pane.dart) and its instructions drawer (claude_guide.dart): the web
/// app's `ClaudePane.test.tsx`, case for case. The clipboard is the test's own.
void main() {
  setUpAll(loadAppFonts);
  final written = <String>[];

  setUp(() {
    written.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') written.add((call.arguments as Map)['text'] as String);
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null);
    claudeHandle = null;
  });

  final finder = SettingsFinder();
  Future<void> pane(WidgetTester tester, {String? handle}) => pumpSettings(tester, SettingsPaneScope(finder: finder, child: SingleChildScrollView(child: ClaudePane(handle: handle))));
  Finder dialog() => find.byKey(ClaudeGuide.cardKey);
  Finder inDialog(Finder what) => find.descendant(of: dialog(), matching: what, skipOffstage: false);

  /// Every word the drawer says, in one line: a thing to copy as it is written, not as its lines are broken.
  String said(WidgetTester tester) => [for (final text in tester.widgetList<Text>(inDialog(find.byType(Text, skipOffstage: false)))) text.semanticsLabel ?? text.data].join(' ');
  Future<void> press(WidgetTester tester, Finder what) async {
    await tester.ensureVisible(what);
    await tester.pump();
    await tester.tap(what);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// Past a Copy's moment of saying Copied, so no timer outlives the test.
  Future<void> away(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 2));
    await endSettings(tester);
  }

  group('Settings › Claude', () {
    testWidgets('says the address Claude connects to, and copies it', (tester) async {
      await pane(tester);
      expect(find.text(mcpUrl), findsOneWidget);
      await press(tester, find.descendant(of: find.byType(RowAction), matching: find.text('Copy')));
      expect(written, [mcpUrl]);
      expect(find.descendant(of: find.byType(RowAction), matching: find.text('Copied')), findsOneWidget);
      // For a second and a half, and then it says Copy again.
      await tester.pump(const Duration(milliseconds: 1600));
      expect(find.descendant(of: find.byType(RowAction), matching: find.text('Copy')), findsOneWidget);
      await away(tester);
    });

    testWidgets('opens the instructions drawer on the hosted way, with the Claude Code line to copy, and closes on Escape', (tester) async {
      final semantics = tester.ensureSemantics();
      await pane(tester);
      expect(dialog(), findsNothing);
      await press(tester, find.text('How to connect'));
      expect(dialog(), findsOneWidget);
      expect(find.bySemanticsLabel('Connecting Claude'), findsWidgets);
      expect(said(tester), contains('claude mcp add --transport http glyph $mcpUrl'));
      expect(said(tester), contains('Sign in on the page that opens'));
      // A Copy on a snippet copies that snippet, and says so for a moment.
      expect(inDialog(byLucide(Lucide.copy)), findsNWidgets(2));
      await press(tester, inDialog(byLucide(Lucide.copy)).at(1));
      expect(written, ['claude mcp add --transport http glyph $mcpUrl']);
      expect(find.bySemanticsLabel('Copied'), findsOneWidget);
      expect(inDialog(byLucide(Lucide.check)), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(dialog(), findsNothing);
      semantics.dispose();
      await away(tester);
    });

    testWidgets('opens on the local way from its own row, with the file, the sign-in and the way out', (tester) async {
      final semantics = tester.ensureSemantics();
      await pane(tester);
      await press(tester, find.text('On your own computer'));
      expect(dialog(), findsOneWidget);
      expect(said(tester), contains('glyph-mcp.mjs login'));
      expect(said(tester), contains('glyph-mcp.mjs logout'));
      expect(said(tester), isNot(contains('--transport http')));
      // The segments switch ways without closing.
      await press(tester, inDialog(find.text('Hosted')));
      expect(said(tester), contains('--transport http'));
      // The close closes.
      await press(tester, find.bySemanticsLabel('Close'));
      expect(dialog(), findsNothing);
      semantics.dispose();
      await away(tester);
    });

    // Not in the web's file: the page's browser broke the commands; here it is done by hand, to the page's lines
    // (the web app's drawer at 390 px, where a block is thirty letters across).
    test('breaks a thing to copy where the page does: after a space or a hyphen in a word, and a long address where the line is full', () {
      expect(wrapCode('https://ghostmarkdown.com/api/mcp', 30), ['https://ghostmarkdown.com/api/', 'mcp']);
      expect(wrapCode('claude mcp add --transport http glyph https://ghostmarkdown.com/api/mcp', 30), ['claude mcp add --transport ', 'http glyph ', 'https://ghostmarkdown.com/api/', 'mcp']);
      expect(wrapCode('curl -fsSL https://ghostmarkdown.com/mcp/glyph-mcp.mjs -o ~/glyph-mcp.mjs', 30), ['curl -fsSL ', 'https://ghostmarkdown.com/mcp/', 'glyph-mcp.mjs -o ~/glyph-', 'mcp.mjs']);
      expect(wrapCode('node ~/glyph-mcp.mjs login <your handle>', 30), ['node ~/glyph-mcp.mjs login ', '<your handle>']);
      expect(wrapCode('claude mcp add glyph -- node ~/glyph-mcp.mjs', 30), ['claude mcp add glyph -- node ', '~/glyph-mcp.mjs']);
      expect(wrapCode('node ~/glyph-mcp.mjs logout', 30), ['node ~/glyph-mcp.mjs logout']);
      expect(wrapCode('{\n  "mcpServers": {\n    "glyph": { "command": "node", "args": ["/Users/you/glyph-mcp.mjs"] }\n  }\n}', 30), [
        '{',
        '  "mcpServers": {',
        '    "glyph": { "command": ',
        '"node", "args": ',
        '["/Users/you/glyph-mcp.mjs"] }',
        '  }',
        '}',
      ]);
      // Wide enough, nothing is broken; and every letter is kept, in order.
      expect(wrapCode('claude mcp add --transport http glyph https://ghostmarkdown.com/api/mcp', 80), hasLength(1));
      for (final guide in guides('matt')) {
        for (final step in guide.steps) {
          for (final text in step.snippets) {
            for (final columns in [7, 30, 41]) {
              expect(wrapCode(text, columns).join().replaceAll('\n', ''), text.replaceAll('\n', ''));
            }
          }
        }
      }
    });

    // Not in the web's file.
    testWidgets('closes on a press of the scrim and on the phone’s back, and every open lands on the way asked for', (tester) async {
      await pane(tester);
      await press(tester, find.text('How to connect'));
      await press(tester, inDialog(find.text('On your computer')));
      expect(said(tester), contains('glyph-mcp.mjs logout'));
      // The scrim, above the card.
      await tester.tapAt(const Offset(195, 30));
      await tester.pump();
      expect(dialog(), findsNothing);
      // Left on the local way; opened again for the hosted one, it shows the hosted one.
      await press(tester, find.text('How to connect'));
      expect(said(tester), contains('--transport http'));
      expect(testBack.depth, 1);
      expect(testBack.goBack(), isTrue);
      await tester.pump();
      expect(dialog(), findsNothing);
      expect(testBack.depth, 0);
      await away(tester);
    });

    testWidgets('fills the sign-in command and the footnote with the handle this device is signed in with', (tester) async {
      await pane(tester, handle: 'matt');
      expect(find.textContaining('Signed in here as matt; the same handle and password sign Claude in.'), findsOneWidget);
      await press(tester, find.text('On your own computer'));
      expect(said(tester), contains('node ~/glyph-mcp.mjs login matt'));
      await away(tester);

      await pane(tester);
      expect(find.textContaining('Sign in to an account first: Claude connects to the same one.'), findsOneWidget);
      await away(tester);

      // The plugin's own page asks the app for the handle.
      claudeHandle = () => 'sam';
      await pumpSettings(tester, SingleChildScrollView(child: Builder(builder: claudePlugin.settings!.pane)));
      expect(find.textContaining('Signed in here as sam;'), findsOneWidget);
      await away(tester);
    });

    // Settings' contract (docs/DESIGN.md §138): each name the search lists for the page is a card on it.
    testWidgets('draws every card the search lists for the page, and a row for each thing Claude can do', (tester) async {
      await pane(tester);
      final names = [for (final setting in claudePlugin.settings!.settings) setting.name];
      expect(names, ['Connect', 'What Claude can do', 'Your key']);
      expect(names.where((name) => finder.find(name) == null), isEmpty);
      for (final tool in canDo) {
        expect(find.text(tool.name, skipOffstage: false), findsOneWidget);
        expect(find.text(tool.words, skipOffstage: false), findsOneWidget);
      }
      await away(tester);
    });
  });
}
