import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/plugins/github/manifest.dart';
import 'package:ghost_md/plugins/github/repos.dart';
import 'package:ghost_md/plugins/host.dart' show usePluginGround;

import 'support.dart';

/// A GitHub repo read into a project (repos.dart `addProject`), against GitHub's API stood in for by a recorded
/// `Fetcher`: which of its files are read and how, what the briefing is with a model on the phone and without one,
/// GitHub's refusals as sentences, and what is kept: the project, which notes link to it, the token. A port of
/// `src/app/plugins/github/projects.test.ts`.
///
/// What differs: the model is repos.dart's seam ([githubDistiller]), so which model is used (the chosen one, else
/// the smallest on the phone) is not this file's to test; that case of the page's is lib/ai's.
void main() {
  const readme = '# AttackFM\n\n[![CI](https://x/badge.svg)](https://x)\n\nA radio for [bands](https://docs).';

  late TestGround ground;

  /// GitHub's answers for one repo: its meta, its tree, and each file's text by path.
  void github({Map<String, String> files = const {'README.md': readme, 'package.json': '{"name":"attackfm"}'}, int status = 200}) {
    ground.asked.clear();
    answer = (request) async {
      final url = request.url.toString();
      if (status != 200) return FetchResponse(status);
      if (url == 'https://api.github.com/repos/infamousvague/attackfm') {
        return FetchResponse.json(200, {'default_branch': 'main', 'description': 'A radio.', 'html_url': 'https://github.com/InfamousVague/AttackFM', 'full_name': 'InfamousVague/AttackFM'});
      }
      if (url == 'https://api.github.com/repos/InfamousVague/AttackFM/git/trees/main?recursive=1') {
        return FetchResponse.json(200, {
          'tree': [
            for (final path in [...files.keys, 'src/main.ts', 'src/']) {'path': path, 'type': path.endsWith('/') ? 'tree' : 'blob'},
          ],
        });
      }
      final file = RegExp(r'\/contents\/(.+)\?ref=main$').firstMatch(url)?[1];
      if (file != null) {
        final text = files[Uri.decodeComponent(file)];
        return text == null ? FetchResponse(404) : textAnswer(200, text);
      }
      return FetchResponse(404);
    };
  }

  setUp(() {
    ground = useGround((request) => answer(request));
    githubDistiller = null;
    githubNow = () => DateTime.now().millisecondsSinceEpoch;
  });

  tearDown(() => githubDistiller = null);

  Matcher refuses(String message) => throwsA(isA<GithubFailure>().having((f) => f.message, 'message', message));

  group('adding a project', () {
    test('reads the repo and the files that say what it is, and keeps the README’s words where there is no model', () async {
      github();
      final steps = <String>[];
      final project = await addProject('https://github.com/infamousvague/attackfm', (step) => steps.add(switch (step) { ReadFiles(:final done, :final total) => 'files $done/$total', ReadReading() => 'reading', ReadDistilling() => 'distilling' }));
      // The name as GitHub spells it, and the id as a key.
      expect([project.id, project.owner, project.repo, project.packModel], ['infamousvague/attackfm', 'InfamousVague', 'AttackFM', null]);
      expect(project.pack, '# AttackFM\n\nA radio for bands.');
      expect(steps, ['reading', 'files 0/2', 'files 1/2', 'files 2/2']);
      expect([for (final p in projects()) p.id], ['infamousvague/attackfm']);
      // The files as raw text, the rest as GitHub's JSON, and no token asked for when none was kept.
      final contents = [for (final request in ground.asked) if (request.url.toString().contains('/contents/')) request];
      expect([for (final request in contents) request.url.toString()], [
        'https://api.github.com/repos/InfamousVague/AttackFM/contents/README.md?ref=main',
        'https://api.github.com/repos/InfamousVague/AttackFM/contents/package.json?ref=main',
      ]);
      expect(header(contents.first, 'Accept'), 'application/vnd.github.raw+json');
      expect(header(ground.asked.first, 'Accept'), 'application/vnd.github+json');
      expect(header(ground.asked.first, 'Authorization'), isNull);
      expect({for (final request in ground.asked) request.method}, {'GET'});
      expect({for (final request in ground.asked) request.url.host}, {'api.github.com'});
    });

    test('skips a file that will not read rather than failing the project, and falls back to the description', () async {
      // The README is listed but will not read when it is asked for.
      answer = (request) async {
        final url = request.url.toString();
        if (url.contains('/contents/')) return FetchResponse(500);
        if (url.endsWith('recursive=1')) {
          return FetchResponse.json(200, {
            'tree': [
              {'path': 'README.md', 'type': 'blob'},
            ],
          });
        }
        return FetchResponse.json(200, {'default_branch': 'main', 'description': 'A radio.', 'html_url': 'u', 'full_name': 'InfamousVague/AttackFM'});
      };
      final project = await addProject('infamousvague/attackfm', (_) {});
      expect(project.pack, 'A radio.');
    });

    test('sends the token kept on this phone, trimmed, and forgets it when it is cleared', () async {
      github();
      await setGithubToken('  ghp_secret  ');
      expect(githubToken(), 'ghp_secret');
      await addProject('infamousvague/attackfm', (_) {});
      expect(header(ground.asked.first, 'Authorization'), 'Bearer ghp_secret');
      // Kept as a secret, and never in the plugin's storage.
      expect(ground.secrets.held, {'glyph-github-token': 'ghp_secret'});
      expect(ground.kept.getItem('glyph-github-token'), isNull);
      expect(ground.kept.allKeys.any((key) => (ground.kept.getItem(key) ?? '').contains('ghp_secret')), isFalse);
      await setGithubToken('   ');
      expect(githubToken(), '');
      expect(ground.secrets.held, isEmpty);
    });

    // Not a case of the page's, whose localStorage answered at once: the secure store has to be read first.
    test('knows a token kept by an earlier launch once its secrets are warmed', () async {
      await setGithubToken('ghp_secret');
      final later = TestGround();
      later.secrets.held.addAll(ground.secrets.held);
      usePluginGround(later.ground);
      expect(githubToken(), '', reason: 'nothing has read the store yet');
      await warmGithub();
      expect(githubToken(), 'ghp_secret');
    });

    test('says what GitHub refused, as a person would need to hear it', () async {
      github(status: 404);
      await expectLater(addProject('o/r', (_) {}), refuses('GitHub can’t find that repo. If it’s private, add a token.'));
      await setGithubToken('ghp_secret');
      await expectLater(addProject('o/r', (_) {}), refuses('GitHub can’t find that repo with this token.'));
      github(status: 401);
      await expectLater(addProject('o/r', (_) {}), refuses('GitHub didn’t accept that token.'));
      github(status: 403);
      await expectLater(addProject('o/r', (_) {}), refuses('GitHub is limiting requests right now. Try again in a while, or add a token.'));
      github(status: 500);
      await expectLater(addProject('o/r', (_) {}), refuses('GitHub answered 500.'));
      ground.asked.clear();
      await expectLater(addProject('not a repo', (_) {}), refuses('That doesn’t look like a GitHub repo. Paste a link like github.com/owner/repo.'));
      expect(ground.asked, isEmpty);
      expect(projects(), isEmpty);
    });
  });

  group('the briefing on a phone', () {
    test('is the model’s, when there is one on the phone', () async {
      final asked = <DistillAsk>[];
      githubDistiller = () async => Distiller(
            id: 'qwen3.5-9b',
            name: 'Qwen3.5 9B',
            write: (ask) async {
              asked.add(ask);
              ask.onProgress(12, 'AttackFM is');
              return '  AttackFM is a radio for bands.  ';
            },
          );
      github();
      final steps = <String>[];
      final project = await addProject('infamousvague/attackfm', (step) => steps.add(step is ReadDistilling ? '${step.model}: ${step.text}' : step.runtimeType.toString()));
      expect([project.pack, project.packModel], ['AttackFM is a radio for bands.', 'qwen3.5-9b']);
      expect(asked.single.prompt, contains('Repository: InfamousVague/AttackFM'));
      expect(asked.single.prompt, contains('Description: A radio.'));
      expect(asked.single.prompt, contains('Folders:\nREADME.md\npackage.json\nsrc/ (1 file)'));
      expect(asked.single.prompt, contains('--- README.md ---'));
      expect([asked.single.system, asked.single.maxTokens, asked.single.temperature], [distillPrompt, 700, 0.2]);
      expect(steps, contains('Qwen3.5 9B: AttackFM is'));
    });

    test('keeps the README’s words when the model fails or writes nothing', () async {
      String? written;
      githubDistiller = () async => Distiller(id: 'qwen3.5-4b', name: 'Qwen3.5 4B', write: (ask) async => written ?? (throw StateError('out of memory')));
      github();
      final failed = await addProject('infamousvague/attackfm', (_) {});
      expect([failed.pack, failed.packModel], ['# AttackFM\n\nA radio for bands.', null]);
      written = '   ';
      expect((await addProject('infamousvague/attackfm', (_) {})).packModel, isNull);
    });

    test('keeps the README’s words when the phone has no model', () async {
      githubDistiller = () async => null;
      github();
      final project = await addProject('infamousvague/attackfm', (_) {});
      expect([project.pack, project.packModel], ['# AttackFM\n\nA radio for bands.', null]);
    });
  });

  group('what a note is linked to', () {
    Future<Project> added() {
      github();
      return addProject('infamousvague/attackfm', (_) {});
    }

    test('gives a linked note the project as context for the model, and its version', () async {
      githubNow = () => 1760000000000;
      final project = await added();
      expect(projectContextFor('n1'), isNull);
      expect(projectContextVersion('n1'), 0);
      linkProject('n1', project.id);
      expect(projectFor('n1')?.id, project.id);
      expect(
        projectContextFor('n1'),
        'This note is about the project InfamousVague/AttackFM. What is known about it, for spelling names and understanding terms (do not add any of it to the note):\n\n# AttackFM\n\nA radio for bands.',
      );
      expect(projectContextVersion('n1'), project.packedAt);
      expect(project.packedAt, 1760000000000);
      linkProject('n1', null);
      expect(projectFor('n1'), isNull);
    });

    test('keeps one copy of a project read twice, the newest first', () async {
      await added();
      await added();
      expect(projects(), hasLength(1));
    });

    test('unlinks every note from a project that is removed, and leaves the rest linked', () async {
      final project = await added();
      ground.kept.setItem('glyph-github-projects', jsonEncode([for (final p in projects()) p.toJson(), {...project.toJson(), 'id': 'o/other', 'owner': 'o', 'repo': 'other'}]));
      linkProject('n1', project.id);
      linkProject('n2', project.id);
      linkProject('n3', 'o/other');
      removeProject(project.id);
      expect([for (final p in projects()) p.id], ['o/other']);
      expect(projectFor('n1'), isNull);
      expect(projectFor('n2'), isNull);
      expect(projectFor('n3')?.id, 'o/other');
    });

    test('reads a kept list from another shape as no projects rather than failing', () {
      ground.kept.setItem('glyph-github-projects', jsonEncode([{'id': 'x'}, 'nonsense', null]));
      expect(projects(), isEmpty);
      ground.kept.setItem('glyph-github-projects', jsonEncode({'not': 'a list'}));
      expect(projects(), isEmpty);
    });
  });
}

/// What the network answers now; each test sets it.
Future<FetchResponse> Function(FetchRequest request) answer = (request) async => FetchResponse(404);
