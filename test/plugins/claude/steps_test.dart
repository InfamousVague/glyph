import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/claude/claude.dart';
import 'package:ghost_md/plugins/types.dart';

/// The words of Settings › Claude (lib/plugins/claude/steps.dart): the web app's `steps.test.ts`, case for case.
void main() {
  tearDown(() => claudeApiBase = 'https://ghostmarkdown.com/api');

  group('the words of Settings › Claude', () {
    test('points Claude at the MCP server beside this build’s sync service, and at the one-file server published beside the app', () {
      expect(mcpUrl, endsWith('/api/mcp'));
      expect(localFileUrl, endsWith('/mcp/glyph-mcp.mjs'));
      expect(Uri.parse(mcpUrl).origin, Uri.parse(localFileUrl).origin);
      // With no base given, the real service's, as the page's build falls back to.
      expect(mcpUrl, 'https://ghostmarkdown.com/api/mcp');
      expect(localFileUrl, 'https://ghostmarkdown.com/mcp/glyph-mcp.mjs');
      // A local build's own.
      claudeApiBase = 'http://10.0.2.2:8787/api';
      expect(mcpUrl, 'http://10.0.2.2:8787/api/mcp');
      expect(localFileUrl, 'http://10.0.2.2:8787/mcp/glyph-mcp.mjs');
      expect(guides(null).first.steps.first.snippets.first, 'http://10.0.2.2:8787/api/mcp');
    });

    test('has the hosted way carry the address and the Claude Code line, and the local way the file, the sign-in and the way out', () {
      final [hosted, local] = guides(null);
      expect(hosted.steps[0].snippets, [mcpUrl, 'claude mcp add --transport http glyph $mcpUrl']);
      expect([for (final s in hosted.steps) s.title], contains('To end it'));
      expect(local.steps[0].snippets[0], contains(localFileUrl));
      expect(local.steps.expand((s) => s.snippets).any((s) => s.endsWith('logout')), isTrue);
      expect((hosted.way, hosted.label, local.way, local.label), (Way.hosted, 'Hosted', Way.local, 'On your computer'));
    });

    test('fills the sign-in command with the handle this device is signed in with, or leaves a blank to fill', () {
      String signIn(String? handle) => guides(handle)[1].steps[1].snippets[0];
      expect(signIn('matt'), 'node ~/glyph-mcp.mjs login matt');
      expect(signIn(null), 'node ~/glyph-mcp.mjs login <your handle>');
    });

    test('says what the tools do, one row each, a delete that goes only as far as the Trash among them', () {
      expect(canDo, hasLength(9));
      expect({for (final t in canDo) t.name}, hasLength(9));
      expect(canDo.firstWhere((t) => t.name == 'Delete a note').words, contains('Emptying the Trash is yours alone.'));
    });
  });

  // Not in the web's file: index.tsx, which the page's tests reach only through Settings.
  group('the plugin', () {
    test('is its page and nothing else: the web’s manifest word for word, no storage, no secrets, no way into a note', () {
      final m = claudePlugin.manifest;
      expect((m.id, m.name, m.version, m.author, m.standard), ('claude', 'Claude', '1.0.0', 'Ghost.md', true));
      expect(m.description, 'Read, add to and change your notes from Claude, through Ghost.md’s MCP server.');
      expect([for (final p in m.permissions) (p.kind, p.why)], [
        (Permission.notes, 'Claude reads and writes the notes of your account once you sign it in: from outside the phone, through the sync service, never through this app.'),
        (Permission.network, 'Claude talks to Ghost.md’s sync service and nothing else. This page only carries the instructions.'),
      ]);
      expect(m.hosts, ['ghostmarkdown.com']);
      expect(m.storage, isEmpty);
      expect(m.secrets, isEmpty);
      expect(m.native, isNull);
      expect(claudePlugin.icon, 'bot');
      expect(claudePlugin.settings!.summary(), 'Read and write your notes from Claude');
      expect(claudePlugin.settings!.hue, 'coral');
      expect([for (final s in claudePlugin.settings!.settings) '${s.name}: ${s.words}'], ['Connect: mcp server address hosted computer', 'What Claude can do: tools', 'Your key: secret connections']);
      expect(claudePlugin.noteLinks, isEmpty);
      expect(claudePlugin.noteActions, isEmpty);
      expect([claudePlugin.itemAction, claudePlugin.suggest, claudePlugin.marks, claudePlugin.tips, claudePlugin.formatContext, claudePlugin.newRows], everyElement(isNull));
    });
  });
}
