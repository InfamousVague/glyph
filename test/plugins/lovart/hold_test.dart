// The device held while Lovart makes any picture (lib/plugins/lovart/lovart_hold.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/plugins/lovart/lovart.dart';

class _Jobs implements BackgroundJobs {
  final List<String> heard = [];

  @override
  Future<void> running(String id, {required String title, required String text, int? done, int? total}) async => heard.add('running $id $text');

  @override
  Future<void> ended(String id, {required String title, String? text, bool quiet = false}) async => heard.add('ended $id${quiet ? ' quiet' : ''}');

  @override
  void onStop(void Function(String id)? stop) {}
}

void main() {
  late _Jobs jobs;
  late LovartHold hold;
  var runGoing = false;

  setUp(() {
    jobs = _Jobs();
    runGoing = false;
    hold = LovartHold(background: jobs, runGoing: () => runGoing)..start();
  });

  tearDown(() {
    hold.dispose();
    lovartBannerMaking.value = const {};
    lovartMaking.value = const {};
    lovartInspiring.value = const {};
  });

  test('holds the device while any picture is made, says how many, and lets it go quietly after the last', () {
    expect(jobs.heard, isEmpty);
    lovartBannerMaking.value = {'n1'};
    lovartMaking.value = {'n2\n{image: a fox}'};
    lovartInspiring.value = {'m1'};
    lovartBannerMaking.value = const {};
    lovartMaking.value = const {};
    lovartInspiring.value = const {};
    expect(jobs.heard, ['running lovart-work 1 picture', 'running lovart-work 2 pictures', 'running lovart-work 3 pictures', 'running lovart-work 2 pictures', 'running lovart-work 1 picture', 'ended lovart-work quiet']);
  });

  test('leaves the device to the header run while it goes, which says its own words', () {
    runGoing = true;
    lovartBannerMaking.value = {'n1', 'n2'};
    expect(jobs.heard, isEmpty);
    // The run ended, a picture still being made: held for it.
    runGoing = false;
    lovartBannerRun.value = const BannerRun(total: 2, done: 2, made: 2, running: false);
    expect(jobs.heard, ['running lovart-work 2 pictures']);
    lovartBannerRun.value = null;
  });

  test('a failure that passes is told apart from one that does not', () {
    expect(const LovartFailure(lovartUnreachable).passing, isTrue);
    expect(const LovartFailure(lovartNoAnswer).lost, isTrue);
    expect(const LovartFailure('x', status: 502).lost, isTrue);
    expect(const LovartFailure('Concurrent task limit reached. Wait for a running task to finish before starting a new one.').busy, isTrue);
    expect(const LovartFailure('Your Lovart credits have run out.', code: 2012).passing, isFalse);
    expect(const LovartFailure('bad keys', status: 401).passing, isFalse);
  });
}
