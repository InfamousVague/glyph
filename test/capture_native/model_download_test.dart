// The voice model's download through the real C functions on the Mac, from a server this test starts on
// 127.0.0.1 and from nowhere else: `CaptureEngine.ensureModel` over `NativeCaptureBackend`, the first connection
// cut a third of the way through the file, the rest picked up with a `Range`, the whole verified by its SHA-256.
// Needs tool/build-native.sh host and tauri/models (which the server only reads); says SKIPPED otherwise.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/native_backend.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/preferences.dart';

import 'support.dart';

void main() {
  const name = 'ggml-base.en-q5_1.bin';
  const bytes = 59721011;
  String? why;
  var opened = false;
  late TestCore held;

  setUpAll(() async {
    why = await TestCore.missing() ?? (File('${webModels.path}/$name').existsSync() ? null : 'no ${webModels.path}/$name');
    if (why != null) return;
    held = await TestCore.open('download');
    opened = true;
    if (!await held.hasVoice) why = 'the Mac\'s core was built without the engines (GHOST_VOICE=0)';
  });

  tearDownAll(() async {
    if (opened) await held.close();
  });

  test('a download cut partway resumes where it stopped, and the file that lands is the model', () async {
    if (why != null) return markTestSkipped('SKIPPED: $why');
    const cut = 20 * 1024 * 1024;
    final server = await CuttingServer.start(webModels, cutAfter: cut);
    addTearDown(server.close);
    final backend = NativeCaptureBackend(held.core, mirrors: [server.base]);
    final engine = CaptureEngine(backend: backend, hasNativeGeneration: (wanted) async => true, preferences: () => const Preferences());

    final before = await backend.modelStatus();
    expect(before.present, isFalse);
    expect((before.name, before.bytes, before.path), (name, bytes, '${held.models.path}/$name'));

    final reports = <(int, int)>[];
    final whole = Stopwatch()..start();
    final status = await engine.ensureModel((received, total) => reports.add((received, total)));
    // ignore: avoid_print
    print('base.en from 127.0.0.1, cut once after $cut bytes: ${whole.elapsedMilliseconds} ms, ${reports.length} reports, requests ${server.requests}');
    expect(status!.present, isTrue);
    expect(File(status.path).lengthSync(), bytes);
    expect(File('${status.path}.part').existsSync(), isFalse, reason: 'the .part became the file');
    expect(server.requests.length, 2, reason: 'one connection cut, one that picked it up');
    expect(server.requests.first, '/$name from 0');
    final resumedAt = int.parse(server.requests.last.split(' ').last);
    expect(resumedAt, inInclusiveRange(1, cut), reason: 'the rest is asked for from where the first stopped');
    expect(reports.length, greaterThan(10));
    for (var i = 1; i < reports.length; i += 1) {
      expect(reports[i].$1, greaterThanOrEqualTo(reports[i - 1].$1), reason: 'the count never starts over');
    }
    expect(reports.last, (bytes, bytes));

    // There now: asked again, no request is made.
    expect((await engine.ensureModel())!.present, isTrue);
    expect(server.requests.length, 2);

    // And it is the model: it loads and hears the fixture.
    final heard = await backend.transcribeWav('${webModels.path}/fixture.wav');
    expect(heard.text.toLowerCase(), contains('oat milk'));
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('a mirror without the file is said by name, and Local only downloads nothing', () async {
    if (why != null) return markTestSkipped('SKIPPED: $why');
    final empty = Directory.systemTemp.createTempSync('ghost-empty-');
    addTearDown(() => empty.deleteSync(recursive: true));
    final server = await CuttingServer.start(empty);
    addTearDown(server.close);
    final backend = NativeCaptureBackend(held.core, mirrors: [server.base]);
    // The refine model is not here and this mirror has none.
    await expectLater(
      backend.fetchRefineModel(),
      throwsA(isA<CoreError>().having((e) => e.message, 'message', allOf(contains('could not download ggml-small.en-q5_1.bin'), contains(server.base), contains('404')))),
    );
    expect(held.models.listSync().where((f) => f.path.contains('small')), isEmpty, reason: 'a refused download leaves nothing');
    expect((await backend.refineModelStatus()).present, isFalse);
    await expectLater(backend.refine(id: 'n1', fromMs: 0, promptTail: ''), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'model missing')));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
