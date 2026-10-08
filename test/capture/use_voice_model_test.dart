import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/voice_model.dart';

/// The voice model's fetch as the app opens (lib/capture/voice_model.dart): shown while it runs, said when it
/// fails, and tried again each time the app comes back to the screen until it is there - the freeze on the Fold that
/// left an empty models/ folder and nothing on screen is what the retry is for. Case for case with the web's
/// `capture/useVoiceModel.test.tsx`: where that renders the hook in a probe, this drives the plain class.

bool native = true;
int asked = 0;
Future<Object?> Function(void Function(int received, int total)? onProgress) answer = (_) async => null;
void Function()? visible;

/// The probe: the model as the app would follow it, started.
VoiceModel show() => VoiceModel(
      native: native,
      ensureModel: ([onProgress]) {
        asked += 1;
        return answer(onProgress);
      },
      onVisible: (listener) {
        visible = listener;
        return () => visible = null;
      },
    )..start();

/// The app comes back to the screen.
void comeBack() => visible?.call();

/// Lets everything already settled have its turn.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  setUp(() {
    native = true;
    asked = 0;
    visible = null;
    answer = (_) async => null;
  });

  group('the voice model', () {
    test('is not asked about in a browser', () {
      native = false;
      final host = show();
      expect(host.state.kind, 'unsupported');
      expect(asked, 0);
    });

    test('shows its download as it comes, and then that it is ready', () async {
      final finish = Completer<Object?>();
      answer = (onProgress) {
        onProgress?.call(30, 60);
        return finish.future;
      };
      final host = show();
      await settle();
      expect(host.state, const VoiceModelStateDownloading(received: 30, total: 60));
      finish.complete(true);
      await settle();
      expect(host.state.kind, 'ready');
    });

    test('says why it failed, and tries again when the app comes back to the screen', () async {
      var calls = 0;
      answer = (_) async {
        calls += 1;
        if (calls == 1) throw Exception('the download stopped');
        return true;
      };
      final host = show();
      await settle();
      expect(host.state, const VoiceModelStateFailed(message: 'the download stopped'));
      comeBack();
      await settle();
      expect(host.state, const VoiceModelStateReady());
      expect(asked, 2);
      // There: coming back again asks nothing.
      comeBack();
      await settle();
      expect(asked, 2);
    });

    test('asks once while a fetch is still running, however often the app comes back', () async {
      answer = (_) => Completer<Object?>().future;
      show();
      comeBack();
      comeBack();
      await settle();
      expect(asked, 1);
    });

    test('tries again on the retry it offers', () async {
      var calls = 0;
      answer = (_) async {
        calls += 1;
        // A rejection with a bare string, as Rust's reach the page.
        // ignore: only_throw_errors
        if (calls == 1) throw 'offline';
        return true;
      };
      final host = show();
      await settle();
      expect(host.state.kind, 'failed');
      host.retry();
      await settle();
      expect(host.state.kind, 'ready');
    });
  });
}
