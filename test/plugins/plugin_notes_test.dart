import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/plugins/github/repos.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/client.dart';

/// Per-note plugin links in the note itself (lib/plugins/host.dart `PluginNotes`; docs/MARKDOWN_FIRST.md §5, gap 12):
/// `notion-board:` and `github:` read where the device's own storage says nothing, and written as a link is made.
void main() {
  late MemoryStored kept;
  late Map<String, String> bodies;
  late List<(String, String, String?)> written;

  setUp(() {
    kept = MemoryStored();
    bodies = {};
    written = [];
    usePluginGround(PluginGround(stored: () => kept));
    usePluginNotes(PluginNotes(bodyOf: (id) => bodies[id], setProperty: (id, key, value) async => written.add((id, key, value))));
  });
  tearDown(() {
    usePluginGround(PluginGround());
    usePluginNotes(const PluginNotes());
  });

  group('a note’s GitHub repo', () {
    test('is read from `github: owner/repo` where this device has no link, matching a kept project by its repo', () {
      bodies['n1'] = '---\ngithub: InfamousVague/attackfm\n---\n# Plan\n';
      final found = projectFor('n1')!;
      expect((found.owner, found.repo, found.id, found.pack), ('InfamousVague', 'attackfm', 'infamousvague/attackfm', ''));
      kept.setItem('glyph-github-projects', jsonEncode([{'id': 'infamousvague/attackfm', 'owner': 'infamousvague', 'repo': 'attackfm', 'pack': 'the pack'}]));
      expect(projectFor('n1')!.pack, 'the pack', reason: 'the kept project, read by its repo');
      bodies['n2'] = '---\ngithub: https://github.com/o/r, o/other\n---\n# Two\n';
      expect(projectFor('n2')!.id, 'o/r', reason: 'the first of a notebook’s list');
      expect(projectFor('n3'), isNull);
    });

    test('is written into the note as it is linked, and taken off as it is unlinked', () {
      kept.setItem('glyph-github-projects', jsonEncode([{'id': 'o/app', 'owner': 'o', 'repo': 'app', 'pack': ''}]));
      linkProject('n1', 'o/app');
      linkProject('n1', null);
      linkProject('n1', 'o/unknown');
      expect(written, [('n1', 'github', 'o/app'), ('n1', 'github', null)]);
    });
  });

  group('a note’s Notion board', () {
    test('is read from `notion-board:` where this device has no link, by its URL and id', () {
      bodies['n1'] = '---\nnotion-board: https://www.notion.so/matt/8a1f9b2c3d4e4f5a8b6c7d8e9f0a1b2c?v=1\n---\n# Jobs\n';
      final board = boardFor('n1')!;
      expect((board.id, board.url, board.titleProperty), ('8a1f9b2c3d4e4f5a8b6c7d8e9f0a1b2c', 'https://www.notion.so/matt/8a1f9b2c3d4e4f5a8b6c7d8e9f0a1b2c?v=1', 'Name'));
      expect(boardFor('n2'), isNull);
    });

    test('is written into the note as it is linked, as its URL', () {
      const board = Board(id: 'b1', title: 'Jobs', url: 'https://notion.so/b1', titleProperty: 'Task');
      linkBoard('n1', board);
      expect(boardFor('n1'), board, reason: 'this device’s own link first');
      linkBoard('n1', null);
      expect(written, [('n1', 'notion-board', 'https://notion.so/b1'), ('n1', 'notion-board', null)]);
    });
  });
}
