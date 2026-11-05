import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/core_library.dart';
import 'package:ghost_md/core/metrics.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/plugins/built_in.dart';
import 'package:ghost_md/plugins/registry.dart';
import 'package:ghost_md/root/metrics_wiring.dart' show formFactor, metricsContext;
import 'package:ghost_md/shell/screen.dart';

import '../library/fake_core.dart';

/// The batches a fake transport was handed, and whether it takes them.
class FakeSend {
  bool online = true;
  final List<Map<String, Object?>> batches = [];
  int tries = 0;

  Future<bool> call(Uri url, Uint8List body) async {
    tries += 1;
    if (!online) return false;
    expect(url.path, '/batch/');
    batches.add(jsonDecode(utf8.decode(body)) as Map<String, Object?>);
    return true;
  }

  List<Map<String, Object?>> get events => [for (final b in batches) ...(b['batch'] as List).cast<Map<String, Object?>>()];
  List<String> get names => [for (final e in events) e['event'] as String];
}

const _context = {'app_version': '2.4.19', 'app_build': '20261104120000', 'platform': 'android', 'form_factor': 'fold', 'simple': false, 'lang': 'en', 'plugins_on': ',lovart,notion,', 'plugin_count': 2};

({Metrics metrics, FakeSend send, MemoryMetricsKeep keep}) _made({bool localOnly = false, bool on = true, int batchSize = 1000}) {
  final send = FakeSend();
  final keep = MemoryMetricsKeep(on: on);
  final metrics = Metrics(key: 'phc_test', host: 'https://us.i.posthog.com', keep: keep, send: send.call, localOnly: () => localOnly, context: () => _context, batchSize: batchSize, sendEvery: const Duration(hours: 1));
  return (metrics: metrics, send: send, keep: keep);
}

/// A value that could be someone's words: more than a few words, or long, and not a word of a vocabulary.
bool _looksLikeText(Object? value, Set<String> vocabulary) {
  if (value is! String) return false;
  if (vocabulary.contains(value)) return false;
  return value.split(RegExp(r'\s+')).length > 3 || value.length > 48 || value.contains(' ');
}

Set<String> _vocabulary() => {
      for (final event in MetricEvent.values)
        for (final shape in event.props.values)
          if (shape is WordProp) ...shape.words,
      ...durationBuckets,
      ...countBuckets,
      ...startBuckets,
    };

void main() {
  setUp(() {
    Metrics.pluginIds = {for (final p in builtIn) p.manifest.id};
    debugForgetMetricsRun();
  });
  tearDown(() => useMetrics(Metrics.off()));

  group('the allow-list', () {
    test('every event has a snake_case name of its own, and every prop a shape', () {
      final names = <String>{};
      for (final event in MetricEvent.values) {
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(event.wire), isTrue, reason: event.wire);
        expect(names.add(event.wire), isTrue, reason: '${event.wire} twice');
        for (final MapEntry(:key, :value) in event.props.entries) {
          expect(RegExp(r'^[a-z][a-z_]*$').hasMatch(key), isTrue, reason: '${event.wire}.$key');
          expect(value, isA<MetricProp>());
          // A prop is never free text: each shape refuses a sentence and a long string.
          expect(value.allows('Meeting notes with Sarah about the launch'), isFalse, reason: '${event.wire}.$key takes a sentence');
          expect(value.allows('x' * 60), isFalse, reason: '${event.wire}.$key takes a long string');
        }
      }
    });

    test('a prop outside the schema, or of the wrong shape, is left out', () {
      // The asserts are a debug build's word on it; the release behaviour is the dropping, checked here.
      final kept = <String, Object>{};
      for (final MapEntry(:key, :value) in {'screen': 'note'}.entries) {
        if (MetricEvent.screenViewed.props[key]!.allows(value)) kept[key] = value;
      }
      expect(kept, {'screen': 'note'});
      expect(MetricEvent.screenViewed.props['screen']!.allows('My secret note'), isFalse);
      expect(MetricEvent.screenViewed.props.containsKey('title'), isFalse);
      expect(() => Metrics.checkProps(MetricEvent.screenViewed, {'title': 'Groceries'}), throwsA(isA<AssertionError>()));
      expect(() => Metrics.checkProps(MetricEvent.noteCreated, {'source': 'a note about cats'}), throwsA(isA<AssertionError>()));
    });

    test('each shape takes its kind and nothing else', () {
      expect(const FlagProp().allows(true), isTrue);
      expect(const FlagProp().allows('true'), isFalse);
      expect(const NumberProp().allows(3), isTrue);
      expect(const NumberProp().allows(double.nan), isFalse);
      expect(const NumberProp().allows('3'), isFalse);
      expect(const CodeProp().allows('lovart-banners'), isTrue);
      expect(const CodeProp().allows('Lovart'), isFalse);
      expect(const ChoiceProp().allows('generate_image_nano_banana_pro'), isTrue);
      expect(const ChoiceProp().allows('two words'), isFalse);
      expect(const PluginProp().allows('notion'), isTrue);
      expect(const PluginProp().allows('not-a-plugin'), isFalse);
      expect(const TypeNameProp().allows('SocketException'), isTrue);
      expect(const TypeNameProp().allows('Connection refused'), isFalse);
    });

    test('the settings it may name are the preferences\' own, with their own words', () {
      expect(settingWords.keys.toSet(), settingWordsKeys);
      final json = Preferences.defaults.toJson();
      for (final MapEntry(key: setting, value: words) in settingWords.entries) {
        if (setting == 'usageStats') continue;
        // Two switches off by default are left out of the stored shape while off.
        if (setting == 'calm' || setting == 'menuBarAlways') {
          expect(json.containsKey(setting), isFalse);
          continue;
        }
        expect(json.containsKey(setting), isTrue, reason: '$setting is not a preference');
        if (words == null) {
          expect(json[setting], isA<bool>(), reason: setting);
        } else {
          expect(words, contains(json[setting]), reason: '$setting\'s default is not among its words');
        }
      }
      expect(settingWords['theme'], {...themes});
      expect(settingWords['density'], {...densities});
      expect(settingWords['accent'], {...accents});
      expect(settingWords['typeface'], {...typefaces});
      expect(settingWords['iconPack'], {...iconPackChoices});
    });

    // A picture given to the assistant (lib/claude/chat_images.dart): how many, as a bucket, and to whom; never what is
    // in it, its name or its size.
    test('a picture sent to the AI is counted by a bucket and the provider, nothing else', () {
      expect(MetricEvent.aiImageAttached.wire, 'ai_image_attached');
      expect(MetricEvent.aiImageAttached.props.keys.toSet(), {'count', 'provider'});
      expect(MetricEvent.aiImageAttached.props['count']!.allows('2-5'), isTrue);
      expect(MetricEvent.aiImageAttached.props['count']!.allows(3), isFalse);
      expect(MetricEvent.aiImageAttached.props['provider']!.allows('gemini'), isTrue);
      expect(MetricEvent.aiImageAttached.props['provider']!.allows('appointments.jpg'), isFalse);
      expect(() => Metrics.checkProps(MetricEvent.aiImageAttached, {'bytes': 482113}), throwsA(isA<AssertionError>()));
    });

    test('the screens it may name are the shell\'s', () {
      expect(screenNames, containsAll([const Screen.list().name, const Screen.academy().name, const Screen.market().name, const Screen.tickets().name, const Screen.notes().name]));
    });
  });

  group('the queue', () {
    test('every event carries the super properties, the install ID and no person profile', () async {
      final it = _made();
      it.metrics.track(MetricEvent.appOpened, {'cold': true, 'start': '1-2s'});
      it.metrics.track(MetricEvent.screenViewed, {'screen': 'note'});
      await it.metrics.flush();
      expect(it.send.names, ['app_opened', 'screen_viewed']);
      expect(it.send.batches.single['api_key'], 'phc_test');
      final id = it.keep.installId;
      expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(id), isTrue);
      for (final event in it.send.events) {
        final props = event['properties'] as Map<String, Object?>;
        expect(props[r'$process_person_profile'], isFalse);
        expect(props[r'$geoip_disable'], isTrue);
        expect(props.containsKey(r'$ip') && props[r'$ip'] == null, isTrue);
        expect(props['distinct_id'], id);
        for (final MapEntry(:key, :value) in _context.entries) {
          expect(props[key], value, reason: key);
        }
        expect(event['uuid'], isA<String>());
      }
    });

    test('a super property that is not of its shape is left out', () async {
      final send = FakeSend();
      final metrics = Metrics(key: 'phc_test', keep: MemoryMetricsKeep(), send: send.call, context: () => {'platform': 'android', 'lang': 'en-GB', 'handle': 'matt'});
      metrics.track(MetricEvent.noteOpened);
      await metrics.flush();
      final props = send.events.single['properties'] as Map;
      expect(props['platform'], 'android');
      expect(props.containsKey('lang'), isFalse);
      expect(props.containsKey('handle'), isFalse);
    });

    test('batches at the batch size, and keeps a batch that did not go for the next try', () async {
      final it = _made(batchSize: 3);
      it.send.online = false;
      for (var i = 0; i < 3; i += 1) {
        it.metrics.track(MetricEvent.noteOpened);
      }
      await pumpEventQueue();
      expect(it.send.tries, 1);
      expect(it.metrics.queued, hasLength(3));
      // Offline as the app goes behind another: kept on the device for the next launch.
      await it.metrics.hidden();
      expect(jsonDecode(it.keep.queue), hasLength(3));
      it.send.online = true;
      await it.metrics.flush();
      expect(it.send.names, ['note_opened', 'note_opened', 'note_opened']);
      expect(it.metrics.queued, isEmpty);
    });

    test('what a killed app left unsent goes with the next launch', () async {
      final keep = MemoryMetricsKeep();
      final first = Metrics(key: 'phc_test', keep: keep, send: (_, _) async => false);
      first.track(MetricEvent.noteCreated, {'source': 'editor'});
      await first.hidden();
      first.dispose();
      final send = FakeSend();
      final next = Metrics(key: 'phc_test', keep: keep, send: send.call);
      await next.flush();
      expect(send.names, ['note_created']);
    });

    test('Local only queues nothing and drops what was waiting', () async {
      var local = false;
      final send = FakeSend();
      final metrics = Metrics(key: 'phc_test', keep: MemoryMetricsKeep(), send: send.call, localOnly: () => local);
      metrics.track(MetricEvent.noteOpened);
      expect(metrics.queued, hasLength(1));
      local = true;
      metrics.track(MetricEvent.noteOpened);
      expect(metrics.queued, isEmpty);
      await metrics.flush();
      expect(send.tries, 0);
    });

    test('no project key: nothing is queued or sent', () async {
      final send = FakeSend();
      final metrics = Metrics(keep: MemoryMetricsKeep(), send: send.call);
      metrics.track(MetricEvent.noteOpened);
      await metrics.flush();
      expect(metrics.queued, isEmpty);
      expect(send.tries, 0);
    });

    test('a loop never floods: one event is queued at most so many times a run', () {
      final metrics = Metrics(key: 'phc_test', keep: MemoryMetricsKeep(), send: (_, _) async => true, perSession: 5, sendEvery: const Duration(hours: 1));
      for (var i = 0; i < 20; i += 1) {
        metrics.track(MetricEvent.noteOpened);
      }
      expect(metrics.queued, hasLength(5));
    });
  });

  group('the switch', () {
    test('off: the queue dropped, the ID deleted, nothing more queued; on again, a fresh ID', () async {
      final it = _made();
      it.metrics.track(MetricEvent.noteOpened);
      final first = it.keep.installId;
      expect(first, isNotEmpty);
      it.keep.on = false;
      expect(it.metrics.queued, isEmpty);
      expect(it.keep.installId, isEmpty);
      it.metrics.track(MetricEvent.noteOpened);
      expect(it.metrics.queued, isEmpty);
      await it.metrics.flush();
      expect(it.send.tries, 0);
      it.keep.on = true;
      it.metrics.track(MetricEvent.noteOpened);
      expect(it.keep.installId, allOf(isNotEmpty, isNot(first)));
    });

    test('is the device\'s own switch, on by default', () {
      expect(usageStatsPref.value, isTrue);
      expect(usageStatsPref.key, 'glyph-usage-stats');
    });
  });

  group('the choke points', () {
    late FakeSend send;
    setUp(() {
      send = FakeSend();
      useMetrics(Metrics(key: 'phc_test', keep: MemoryMetricsKeep(), send: send.call, sendEvery: const Duration(hours: 1), batchSize: 1000));
    });

    test('a plugin switched on and off', () async {
      final registry = createRegistry(builtIn, store: MemorySwitches());
      registry.setEnabled('lovart', true);
      registry.setEnabled('lovart', false);
      // Another device's switch is that device's to count.
      registry.setSwitch('figma', true);
      await metrics.flush();
      expect([for (final e in send.events) (e['event'], (e['properties'] as Map)['plugin'])], [('plugin_enabled', 'lovart'), ('plugin_disabled', 'lovart')]);
    });

    test('a job begun and finished, by its code and never its note or title', () async {
      final record = Activity();
      record.begin('summary:note-123', kind: JobKind.ai, title: 'Summary of Secret plans', personStarted: true).done();
      record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images', plugin: 'lovart').failed('Lovart is out of credits', fix: JobFix(JobFixKind.topUp, () {}));
      record.begin('cleanup:folder-9', kind: JobKind.ai, title: 'Tidying Work').stopped();
      // A sync's passes are not counted; a failed one is.
      record.begin('sync', kind: JobKind.sync, title: 'Syncing').done();
      await metrics.flush();
      final seen = [for (final e in send.events) (e['event'], (e['properties'] as Map)['job'])];
      expect(seen, [('job_started', 'summary'), ('job_finished', 'summary'), ('job_started', 'lovart-banners'), ('job_failed', 'lovart-banners'), ('job_started', 'cleanup'), ('job_stopped', 'cleanup')]);
      final failed = send.events.firstWhere((e) => e['event'] == 'job_failed')['properties'] as Map;
      expect((failed['kind'], failed['plugin'], failed['fix'], failed['took']), ('images', 'lovart', 'topUp', '<1s'));
      expect(jsonEncode(send.events).contains('Secret'), isFalse);
      expect(jsonEncode(send.events).contains('note-123'), isFalse);
      expect(jsonEncode(send.events).contains('credits'), isFalse);
    });

    test('a note created, edited once per run, trashed and restored, never by its id or words', () async {
      final core = FakeCore();
      final library = CoreLibrary(core.invoke, resume: false, wait: (_) async {}, log: (_) {});
      final note = await library.createNote('# Diary\n\nPrivate words');
      await library.update(note.id, '# Diary\n\nMore private words', note.revision);
      final again = library.noteOf(note.id)!;
      await library.update(note.id, '# Diary\n\nEven more', again.revision);
      await library.putInTrash(note.id);
      await library.takeFromTrash(note.id);
      await metrics.flush();
      expect(send.names, ['note_created', 'note_edited', 'note_trashed', 'note_restored']);
      final all = jsonEncode(send.events);
      expect(all.contains(note.id), isFalse);
      expect(all.contains('Diary'), isFalse);
    });

    test('a screen viewed by its name', () async {
      track(MetricEvent.screenViewed, {'screen': const Screen.market().name});
      await metrics.flush();
      expect((send.events.single['properties'] as Map)['screen'], 'market');
    });

    test('an error counted by its type, once a run, never its message', () async {
      trackError(StateError('the note “Taxes 2026” would not open'), 'platform');
      trackError(StateError('again'), 'platform');
      trackError(const FormatException('bad'), 'framework');
      await metrics.flush();
      expect([for (final e in send.events) (e['properties'] as Map)['type']], ['StateError', 'FormatException']);
      expect(jsonEncode(send.events).contains('Taxes'), isFalse);
    });
  });

  group('a fake session through the guard', () {
    test('no prop value looks like a note\'s text', () async {
      final send = FakeSend();
      useMetrics(Metrics(key: 'phc_test', keep: MemoryMetricsKeep(), send: send.call, context: () => metricsContext(registry: createRegistry(builtIn, store: MemorySwitches()), prefs: Preferences.defaults), sendEvery: const Duration(hours: 1), batchSize: 1000));
      final registry = createRegistry(builtIn, store: MemorySwitches());
      final core = FakeCore();
      final library = CoreLibrary(core.invoke, resume: false, wait: (_) async {}, log: (_) {});
      final record = Activity();
      // Someone opens the app, writes, searches, sets things up and makes pictures.
      track(MetricEvent.appOpened, {'cold': true, 'start': startBucket(const Duration(milliseconds: 1800))});
      track(MetricEvent.screenViewed, {'screen': 'list'});
      final note = await library.createNote('# Meeting with Dr. Alvarez about my results\n\nThe biopsy came back fine.');
      track(MetricEvent.screenViewed, {'screen': 'note'});
      await library.update(note.id, '${note.body}\nCall mum.', note.revision);
      registry.setEnabled('lovart', true);
      trackPlugin('lovart', 'style_chosen', choice: 'journal');
      trackPlugin('lovart', 'model_chosen', choice: 'generate_image_nano_banana_pro');
      trackPlugin('notion', 'import_finished', count: 140, ok: true);
      record.begin('banner:${note.id}', kind: JobKind.images, title: 'Header image for Meeting with Dr. Alvarez', plugin: 'lovart').done();
      track(MetricEvent.searchUsed, {'results': countBucket(3)});
      track(MetricEvent.settingChanged, {'setting': 'theme', 'value': 'dusk'});
      track(MetricEvent.aiUsed, {'feature': 'request', 'provider': 'claude'});
      track(MetricEvent.aiImageAttached, {'count': countBucket(2), 'provider': 'openai'});
      trackError(ArgumentError('Dr. Alvarez'), 'framework');
      await metrics.flush();
      expect(send.events.length, greaterThan(10));
      final vocabulary = _vocabulary();
      for (final event in send.events) {
        for (final MapEntry(:key, :value) in (event['properties'] as Map<String, Object?>).entries) {
          if (key == 'plugins_on' || key == 'distinct_id') continue;
          expect(_looksLikeText(value, vocabulary), isFalse, reason: '${event['event']}.$key = $value');
        }
      }
      final all = jsonEncode(send.events);
      for (final word in ['Alvarez', 'biopsy', 'mum', note.id]) {
        expect(all.contains(word), isFalse, reason: word);
      }
    });
  });

  group('the helpers', () {
    test('buckets', () {
      expect(durationBucket(const Duration(milliseconds: 400)), '<1s');
      expect(durationBucket(const Duration(minutes: 5)), '2-10m');
      expect(durationBucket(const Duration(hours: 3)), '>1h');
      expect([0, 1, 4, 19, 99, 400, 9000].map(countBucket), countBuckets);
      expect(startBucket(const Duration(seconds: 3)), '2-4s');
    });

    test('a job\'s code is what comes before its note', () {
      expect(jobCode('summary:abc'), 'summary');
      expect(jobCode('lovart-banners'), 'lovart-banners');
      expect(jobCode('Weird Id'), isNull);
    });

    test('form factors', () {
      expect(formFactor(platform: 'macos', width: 1400, height: 900), 'desktop');
      expect(formFactor(platform: 'android', width: 390, height: 844), 'phone');
      expect(formFactor(platform: 'android', width: 904, height: 750), 'fold');
      expect(formFactor(platform: 'ios', width: 820, height: 1180), 'tablet');
    });

    test('the early events wait for the real client, and go only if it sends', () async {
      useMetrics(Metrics.off());
      track(MetricEvent.onboardingStarted);
      final send = FakeSend();
      useMetrics(Metrics(key: 'phc_test', keep: MemoryMetricsKeep(), send: send.call));
      await metrics.flush();
      expect(send.names, ['onboarding_started']);
    });
  });

  test('the device keep is the device\'s flag and words', () {
    const keep = DeviceMetricsKeep();
    expect(keep.on, usageStatsPref.value);
    expect(keep.switched, same(usageStatsPref));
    expect(kReleaseMode, isFalse);
  });
}
