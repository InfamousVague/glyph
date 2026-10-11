// Settings on every device (lib/sync/prefs.dart), against the service in memory. A port of
// `src/app/core/sync/prefs.test.ts`, case for case: one sealed blob, written from the revision last seen. A device
// that changed nothing takes what another wrote; one that changed something sends it, and the one sending now wins
// the settings both changed; a write that loses a race reads again, once.
//
// The pass works on the settings as JSON, as the page's does on its plain object, so a device here is a map that
// starts as the defaults. The typed store behind a PrefsBridge is prefs_lossless_test.dart.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/sync/prefs.dart';

import 'support.dart';

/// A device's settings and what it remembers of the account's, synced through [service].
class PrefsDevice {
  PrefsDevice(this.service, [Fetcher? fetcher]) : api = apiOf(service, fetcher);
  final FakeService service;
  final Api api;
  Map<String, Object?> prefs = Preferences.defaults.toJson();
  PrefsState state = const PrefsState();

  void set(Map<String, Object?> next) => prefs = {...prefs, ...next};

  Future<bool> sync() => syncPrefs(PrefsContext(
        token: service.signedIn(),
        key: service.accountKey,
        read: () => prefs,
        write: set,
        state: state,
        save: (next) => state = next,
        api: api,
        crypto: service.crypto,
      ));
}

void main() {
  group('settings kept the same on every device', () {
    test('are sent by the first device, and taken by the next one to sign in', () async {
      final service = await FakeService.start(seed: testAccount);
      final phone = PrefsDevice(service);
      phone.set({'theme': 'ember', 'textSize': 'larger'});
      expect(await phone.sync(), isFalse);
      expect(service.calls, ['GET prefs', 'PUT prefs']);
      final desk = PrefsDevice(service);
      expect(await desk.sync(), isTrue);
      expect((desk.prefs['theme'], desk.prefs['textSize']), ('ember', 'larger'));
      // Nothing more to say on either side.
      service.calls.clear();
      expect(await phone.sync(), isFalse);
      expect(await desk.sync(), isFalse);
      expect(service.calls, ['GET prefs', 'GET prefs']);
    });

    test('take a change from another device when this one changed nothing, and send this one’s when it did', () async {
      final service = await FakeService.start(seed: testAccount);
      final phone = PrefsDevice(service);
      final desk = PrefsDevice(service);
      await phone.sync();
      await desk.sync();
      desk.set({'theme': 'dawn'});
      await desk.sync();
      expect(await phone.sync(), isTrue);
      expect(phone.prefs['theme'], 'dawn');
      // Both change the same setting: the one sending now wins, settings being chosen rather than typed.
      phone.set({'theme': 'boreal'});
      desk.set({'theme': 'ember'});
      await desk.sync();
      await phone.sync();
      expect(await desk.sync(), isTrue);
      expect(desk.prefs['theme'], 'boreal');
    });

    test('keep a note filed on one device when another, with a tab just opened, sends its own settings', () async {
      final service = await FakeService.start(seed: testAccount);
      final desk = PrefsDevice(service);
      final other = PrefsDevice(service);
      const team = {'id': 'org-a', 'name': 'Team'};
      desk.set({
        'workspaces': {
          'list': [team],
          'notes': {'n1': 'org-a'},
        },
      });
      await desk.sync();
      await other.sync();
      // Filed elsewhere (the connector, a phone), while this desk opened a tab and filed a note of its own.
      other.set({
        'workspaces': {
          'list': [team],
          'notes': {'n1': 'org-a', 'n2': 'org-a', 'n3': 'org-a'},
        },
        'trash': {'gone': 5},
      });
      await other.sync();
      desk.set({
        'openNotes': ['n1'],
        'workspaces': {
          'list': [
            team,
            {'id': 'w-1', 'name': 'Mine'},
          ],
          'notes': {'n4': 'w-1'},
        },
      });
      expect(await desk.sync(), isTrue);
      final spaces = desk.prefs['workspaces'] as Map;
      expect(spaces['notes'], {'n2': 'org-a', 'n3': 'org-a', 'n4': 'w-1'});
      expect([for (final each in spaces['list'] as List) (each as Map)['id']], ['org-a', 'w-1']);
      expect(desk.prefs['trash'], {'gone': 5});
      expect(desk.prefs['openNotes'], ['n1']);
      // The other device takes the lot, and then neither has anything to say.
      expect(await other.sync(), isTrue);
      expect(other.prefs['workspaces'], desk.prefs['workspaces']);
      expect(other.prefs['openNotes'], ['n1']);
      service.calls.clear();
      await desk.sync();
      await other.sync();
      expect(service.calls, ['GET prefs', 'GET prefs']);
    });

    test('carry only what describes the person: which model a phone formats with, and whether it syncs, stay with it', () async {
      final service = await FakeService.start(seed: testAccount);
      final phone = PrefsDevice(service);
      phone.set({'theme': 'ember', 'formatModel': 'qwen3.5-2b', 'localOnly': true});
      await phone.sync();
      final desk = PrefsDevice(service);
      await desk.sync();
      expect((desk.prefs['theme'], desk.prefs['formatModel'], desk.prefs['localOnly']), ('ember', Preferences.defaults.formatModel, false));
    });

    test('carry the map and the place names, and leave tagging new notes with the device that asks for its position', () async {
      final service = await FakeService.start(seed: testAccount);
      final phone = PrefsDevice(service);
      phone.set({'mapTiles': false, 'placeNames': false, 'tagNewNotes': false});
      await phone.sync();
      final desk = PrefsDevice(service);
      await desk.sync();
      expect((desk.prefs['mapTiles'], desk.prefs['placeNames'], desk.prefs['tagNewNotes']), (false, false, Preferences.defaults.tagNewNotes));
    });

    test('carry which notes are in the trash and which are meetings, so the shelf on a second device knows them', () async {
      final service = await FakeService.start(seed: testAccount);
      final phone = PrefsDevice(service);
      phone.set({
        'trash': {'t': 7},
        'meetings': {'m': 40},
      });
      await phone.sync();
      final desk = PrefsDevice(service);
      await desk.sync();
      expect(desk.prefs['trash'], {'t': 7});
      expect(desk.prefs['meetings'], {'m': 40});
    });

    test('carry when a meeting is written up and whether its audio syncs: the person’s choices on every device', () async {
      final service = await FakeService.start(seed: testAccount);
      final phone = PrefsDevice(service);
      phone.set({'writeUp': 'now', 'syncMeetingRecordings': true});
      await phone.sync();
      final desk = PrefsDevice(service);
      await desk.sync();
      expect((desk.prefs['writeUp'], desk.prefs['syncMeetingRecordings']), ('now', true));
    });

    test('carry which notifications are drawn and which organizations are muted', () async {
      final service = await FakeService.start(seed: testAccount);
      final phone = PrefsDevice(service);
      const chosen = {
        'team': true,
        'claude': false,
        'summaries': true,
        'conflicts': true,
        'mutedOrgs': ['o1'],
      };
      phone.set({'notifications': chosen});
      await phone.sync();
      final desk = PrefsDevice(service);
      await desk.sync();
      expect(desk.prefs['notifications'], chosen);
    });

    test('ignore what a newer build wrote that this one does not know', () async {
      final service = await FakeService.start(seed: testAccount);
      final blob = await service.crypto.seal(service.accountKey, {'theme': 'dawn', 'fromTheFuture': true}, 'prefs');
      await apiOf(service).call('PUT', 'prefs', token: service.signedIn(), body: {'base': 0, 'blob': blob});
      final phone = PrefsDevice(service);
      expect(await phone.sync(), isTrue);
      expect(phone.prefs['theme'], 'dawn');
      expect(phone.prefs.containsKey('fromTheFuture'), isFalse);
    });

    test('read again, once, when another device wrote between the read and the write', () async {
      final service = await FakeService.start(seed: testAccount);
      final desk = PrefsDevice(service);
      await desk.sync();
      final phone = PrefsDevice(service);
      await phone.sync();
      // The desk writes in the moment between the phone's read and its write.
      var raced = false;
      Future<FetchResponse> racing(FetchRequest request) async {
        if (request.method == 'PUT' && !raced) {
          raced = true;
          desk.set({'theme': 'dawn'});
          await desk.sync();
        }
        return service.fetcher(request);
      }

      final late = PrefsDevice(service, racing);
      await late.sync();
      late.set({'theme': 'ember'});
      await late.sync();
      expect(raced, isTrue);
      // Refused once, read again, and sent from the revision the desk's write made: the phone's choice stands.
      expect(service.calls.where((call) => call == 'PUT prefs').length, greaterThanOrEqualTo(3));
      expect(await desk.sync(), isTrue);
      expect(desk.prefs['theme'], 'ember');
    });
  });
}
