/// The one-time carry of what the Tauri app kept on a phone into this app's own stores.
///
/// This app replaces Ghost.md's Tauri app as an update under the same Android id (docs/CUTOVER.md), so on its
/// first launch it wakes in that app's data folder. Most of what is there it already reads where it lies, because
/// it was built to: the library (`Library/`, or the folder `library-root.json` names with its tree's grant, which
/// Android keeps for the id), `recordings/`, `images/`, `video/`, `models/`, `jobs/`, the versions files inside
/// the library, the Kotlin side's own preference files, its notification channels and its queued work, all under
/// the names and class names the Tauri app used. What it does NOT read where it lies is what the page kept in its
/// web view, and four things Rust kept that this app keeps in the phone's secure store. Those are carried here:
///
/// | The Tauri app kept | where | this app keeps it |
/// | --- | --- | --- |
/// | every `glyph-…` key of `localStorage` (preferences with the workspaces, trash and open tabs, drafts, kept places, tape ids, the sync cursors, plugin settings, the once-flags) | the web view, origin `http://tauri.localhost` | SharedPreferences, the same key and the same text (lib/core/stored_device.dart, preferences.dart) |
/// | the session (`glyph-account-session`) | `localStorage`, in the clear | the secure store, same name (lib/account/device_keys.dart) |
/// | the account key, the device's signing key, the account's key pair | IndexedDB `glyph-account`, as `CryptoKey`s that cannot be exported | the secure store: `account`, `device`, `encryption`, each its 32 bytes |
/// | a team note's document, with what was typed and not yet sent | IndexedDB `glyph-team` | `team/<account id>/<note id>.json` (lib/team/docs.dart) |
/// | GitHub's token (`glyph-github-token`) | `localStorage` | the secure store, same name |
/// | Slack's webhooks | `slack.json` | the secure store, `glyph-slack-webhook:<channel id>` |
/// | Notion's sign-in | `notion.json` | the secure store, `glyph-notion-account` |
///
/// **How it is read.** A web view asked once (android/…/TauriCarry.kt): Chromium reading its own files, at the
/// page's origin, which is the one honest way to `localStorage` and to a team document. The keys cannot be had
/// that way at all, so their bytes are read from IndexedDB's files (web_stores.dart) BEFORE the web view opens
/// them, and then proven: a pair's private key raised in the core must answer the public key kept beside it, and
/// the account key must open a few bytes the web view sealed under the page's own key. A key that fails is not
/// carried; the person is then signed in and asked for their password once, as on a device that lost its key.
/// With no web view to ask, `localStorage` is read from its files too.
///
/// **In two halves**, because of when each is needed: [settings] before anything reads a preference (main.dart's
/// `_remembered`), [secrets] once the core is loaded and before the account is made (`_opened`).
///
/// **It never deletes and never overwrites.** The Tauri app's files stay where they are, the web view's storage
/// included; a name this app already holds is left as this app has it. So a half that is cut short is simply run
/// again on the next launch and comes to the same place. Each half reads back what it wrote before it is marked
/// done, in `carry/tauri-carry.json`, with a line for every step in `carry/tauri-carry.log` (names and counts;
/// never a token, a key or a note's words).
///
/// **On a Mac the same carry runs over other ground** (lib/carry/mac_carry.dart; docs/CUTOVER.md §7): this app
/// keeps a folder of its own there and never opens the Tauri app's, so there is a half before the other two,
/// [TauriCarry.files], that copies the library, the pictures and the recordings across; and what the page kept is
/// WebKit's, read from copies of its files (webkit_stores.dart), with no web view to ask. Where the things are
/// read from is a [CarrySource]: a phone's is [PhoneCarrySource], which is all there was before the Mac's.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../account/device_keys.dart' show SecureStore;
import '../core/native/core.dart';
import 'leveldb.dart';
import 'web_stores.dart';

/// The page's keys that are secrets: carried to the secure store, never to SharedPreferences.
const String carrySessionKey = 'glyph-account-session';
const String carryGithubKey = 'glyph-github-token';
const String carrySlackPrefix = 'glyph-slack-webhook:';
const String carryNotionKey = 'glyph-notion-account';

/// What a few bytes are sealed under for the account key's proof: a context no note or setting is sealed under.
const String carryProbeContext = 'ghost-carry/v1/probe';

/// The Tauri app's queued work this app has no worker for: its update check (updates/UpdateAlerts.kt).
const List<String> carryStaleWork = ['glyph-update-alerts', 'glyph-update-alerts-now'];

/// The phone's half (android/…/TauriCarry.kt).
abstract interface class CarryDevice {
  /// What the web view holds for the Tauri app's origin, as JSON. Throws when no web view will answer.
  Future<String> readWeb(String probeContext);

  /// Lets go of queued work by its unique names.
  Future<void> forgetWork(List<String> names);
}

/// A device with no web view to ask and no queued work: a Mac.
class NoCarryDevice implements CarryDevice {
  const NoCarryDevice();

  @override
  Future<String> readWeb(String probeContext) => Future.error(StateError('There is no web view to ask here.'));

  @override
  Future<void> forgetWork(List<String> names) async {}
}

class ChannelCarryDevice implements CarryDevice {
  const ChannelCarryDevice();

  static const MethodChannel channel = MethodChannel('ghost_md/tauri_carry');

  @override
  Future<String> readWeb(String probeContext) async => (await channel.invokeMethod<String>('read', {'probeContext': probeContext}).timeout(const Duration(seconds: 18)))!;

  @override
  Future<void> forgetWork(List<String> names) => channel.invokeMethod<void>('forgetWork', {'names': names});
}

/// The store the preferences and every `glyph-` key are kept in: SharedPreferences on a phone, a map in a test.
abstract interface class CarryPrefs {
  String? read(String key);
  Future<bool> write(String key, String value);

  /// Reads the store again from where it is kept, so a read after this is of what was really written.
  Future<void> reload();
}

/// What one half did.
class CarryOutcome {
  const CarryOutcome({required this.ran, required this.done, this.carried = const [], this.left = const [], this.failed = const []});

  /// Whether there was anything to do this launch (false: done before, or no Tauri app was here).
  final bool ran;

  /// Whether the half is marked done.
  final bool done;

  /// Names carried, names left because this app already held them, and names that could not be carried.
  final List<String> carried;
  final List<String> left;
  final List<String> failed;

  @override
  String toString() => 'ran: $ran, done: $done, carried ${carried.length}, left ${left.length}, failed ${failed.length}';
}

/// What the Tauri app's page kept, read: by a web view, or from the web view's files.
class CarryRead {
  const CarryRead({required this.local, required this.fromWebView, this.webFailure, required this.diskCount, required this.keys, this.idbDamaged = 0, this.web = const {}, this.how, this.accountProbes = const [], this.accountRead, this.notes = const []});

  /// Every key and value of `localStorage`.
  final Map<String, String> local;

  /// Whether a web view answered; if not, why not, and [local] is from its files.
  final bool fromWebView;
  final String? webFailure;

  /// How many keys the files alone gave.
  final int diskCount;

  /// The three keys, from the files.
  final DiskKeys keys;
  final int idbDamaged;

  /// What a web view answered (`databases`, `keys`, `team`), or what the files gave of it (`team`).
  final Map<String, Object?> web;

  /// One line for the log saying how it was read, where the phone's two lines do not say it.
  final String? how;

  /// Things the page itself sealed under the account key, each its context and its sealed text: with no web view
  /// to seal a proof, the key that opens one of these is the page's key.
  final List<({String context, String blob})> accountProbes;

  /// What is said of an account key that nothing could prove, where "no web view could seal a proof" is not the
  /// whole of it.
  final String? accountRead;

  /// Lines for the log about the keys (never a key).
  final List<String> notes;
}

/// Where what the Tauri app kept is read from.
abstract interface class CarrySource {
  /// The folder the Tauri app's Rust kept `slack.json` and `notion.json` in.
  String get filesDir;

  /// Whether a Tauri app ever kept anything here.
  Future<bool> wasHere();

  /// Reads it. Asked once a launch.
  Future<CarryRead> read();
}

/// A phone's: the web view's storage is in the app's own data folder, and a web view can be asked.
class PhoneCarrySource implements CarrySource {
  const PhoneCarrySource({required this.dataDir, required this.device});

  final String dataDir;
  final CarryDevice device;

  @override
  String get filesDir => dataDir;

  @override
  Future<bool> wasHere() => localStorageFolder(dataDir).exists();

  @override
  Future<CarryRead> read() async {
    // The keys first, from the files, while no web view has them open.
    final idb = await LevelDb.read(indexedDbFolder(dataDir));
    final keys = DiskKeys.of(idb);
    final disk = localStorageOf(await LevelDb.read(localStorageFolder(dataDir)));
    Map<String, Object?>? web;
    String? webFailure;
    try {
      final read = jsonDecode(await device.readWeb(carryProbeContext));
      if (read is Map && read['local'] is Map) {
        web = read.cast<String, Object?>();
      } else {
        webFailure = 'an answer that is not the page\'s';
      }
    } catch (failure) {
      webFailure = '$failure';
    }
    final Map<String, String> local;
    if (web != null) {
      local = {
        for (final entry in (web['local'] as Map).entries)
          if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
      };
    } else {
      local = disk;
    }
    return CarryRead(local: local, fromWebView: web != null, webFailure: webFailure, diskCount: disk.length, keys: keys, idbDamaged: idb.damaged, web: web ?? const {});
  }
}

/// What the files' half did, in numbers: never a name, since a note's file is named by its title.
class CarryFilesOutcome {
  const CarryFilesOutcome({this.counts = const {}, this.failed = 0, this.notes = const []});

  /// How many of each kind were copied, were already here, or were left on purpose (`notes`, `notes left`, …).
  final Map<String, int> counts;

  /// How many could not be copied. Any at all, and the half is not done.
  final int failed;

  /// Lines for the log.
  final List<String> notes;
}

/// The half that comes first where this app does not wake in the Tauri app's folder (a Mac): the Tauri app's
/// files, copied into this app's own.
abstract interface class CarryFiles {
  /// Copies what is not here yet. It never changes what it copies from, and never writes over a file.
  Future<CarryFilesOutcome> copy();
}

class TauriCarry {
  TauriCarry({required this.dataDir, required this.prefs, required this.secure, required this.device, CarrySource? source, this.files, DateTime Function()? now})
      : source = source ?? PhoneCarrySource(dataDir: dataDir, device: device),
        _now = now ?? DateTime.now;

  /// This app's own data folder: where the marker, the log and the team documents are written.
  final String dataDir;
  final CarryPrefs prefs;
  final SecureStore secure;
  final CarryDevice device;

  /// Where the Tauri app's things are read from: this folder itself on a phone.
  final CarrySource source;

  /// The files' half, where there is one (a Mac), or null where the files are already this app's (a phone).
  final CarryFiles? files;
  final DateTime Function() _now;

  Directory get _folder => Directory('$dataDir${Platform.pathSeparator}carry');
  File get _markerFile => File('${_folder.path}${Platform.pathSeparator}tauri-carry.json');
  File get _logFile => File('${_folder.path}${Platform.pathSeparator}tauri-carry.log');

  Future<CarryRead>? _gathering;
  Future<CarryOutcome>? _copied;
  Future<CarryOutcome>? _settings;
  Future<CarryOutcome>? _secrets;

  /// The half before the first, where there is one ([files]): the Tauri app's files into this app's folder,
  /// before the core is opened on it. Done at once where there is none. Asked more than once in a launch, it runs
  /// once. It never throws.
  Future<CarryOutcome> copied() => _copied ??= _guarded('files', _carryFiles);

  /// The first half: `localStorage` into the preferences' store, and the team notes' documents into their files.
  /// Asked more than once in a launch, it runs once. It never throws. It waits for the files' half, and does
  /// nothing until that is done: the sync's cursors over half a library would read the missing notes as deleted.
  Future<CarryOutcome> settings() => _settings ??= _guarded('settings', () async {
        if (!(await copied()).done) return const CarryOutcome(ran: true, done: false, failed: ['files']);
        return _carrySettings();
      });

  /// The second half: the session, the keys and the plugins' secrets into the secure store. [core] is the loaded
  /// core, for raising each key to prove it (`key_restore`, `open`: neither needs the library open). It waits for
  /// the first half. It never throws.
  Future<CarryOutcome> secrets(CoreInvoke core) => _secrets ??= _guarded('secrets', () async {
        await settings();
        return _carrySecrets(core);
      });

  Future<CarryOutcome> _guarded(String half, Future<CarryOutcome> Function() run) async {
    try {
      return await run();
    } catch (failure) {
      // Nothing was deleted and nothing is marked: the next launch runs it again.
      await _log('$half: stopped by $failure');
      return const CarryOutcome(ran: true, done: false, failed: ['everything']);
    }
  }

  // --- the marker and the log ---------------------------------------------------------------------------------

  Future<Map<String, Object?>> _marker() async {
    try {
      if (!await _markerFile.exists()) return {};
      final read = jsonDecode(await _markerFile.readAsString());
      return read is Map ? read.cast<String, Object?>() : {};
    } catch (_) {
      // Cut short: as if never written, and the half runs again.
      return {};
    }
  }

  Future<void> _mark(String half, Map<String, Object?> what) async {
    final marker = await _marker();
    marker['v'] = 1;
    marker[half] = {'at': _now().toUtc().toIso8601String(), ...what};
    await _folder.create(recursive: true);
    final beside = File('${_markerFile.path}.new');
    await beside.writeAsString(const JsonEncoder.withIndent('  ').convert(marker), flush: true);
    await beside.rename(_markerFile.path);
  }

  Future<void> _log(String line) async {
    debugPrint('[carry] $line');
    try {
      await _folder.create(recursive: true);
      await _logFile.writeAsString('${_now().toUtc().toIso8601String()} $line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // A log that cannot be written stops nothing.
    }
  }

  // --- what the Tauri app left --------------------------------------------------------------------------------

  /// Whether a Tauri app ever kept anything here.
  Future<bool> _tauriWasHere() => source.wasHere();

  Future<CarryRead> _gather() => _gathering ??= source.read();

  // --- the files' half ----------------------------------------------------------------------------------------

  Future<CarryOutcome> _carryFiles() async {
    final half = files;
    if (half == null) return const CarryOutcome(ran: false, done: true);
    if ((await _marker())['files'] is Map) return const CarryOutcome(ran: false, done: true);
    if (!await _tauriWasHere()) {
      await _mark('files', {'found': false});
      return const CarryOutcome(ran: false, done: true);
    }
    final out = await half.copy();
    for (final note in out.notes) {
      await _log('files: $note');
    }
    await _log('files: ${out.counts.entries.map((entry) => '${entry.value} ${entry.key}').join(', ')}; ${out.failed} could not be copied');
    if (out.failed > 0) return CarryOutcome(ran: true, done: false, failed: ['${out.failed} files']);
    await _mark('files', {'found': true, 'counts': out.counts});
    return const CarryOutcome(ran: true, done: true);
  }

  // --- the first half -----------------------------------------------------------------------------------------

  Future<CarryOutcome> _carrySettings() async {
    if ((await _marker())['settings'] is Map) return const CarryOutcome(ran: false, done: true);
    if (!await _tauriWasHere()) {
      // A new install, or a phone this app was always the app on: nothing to carry, ever.
      await _mark('settings', {'found': false});
      await _mark('secrets', {'found': false});
      await _log('no Tauri app was here: nothing to carry');
      return const CarryOutcome(ran: false, done: true);
    }
    final all = await _gather();
    await _log(all.how ??
        (all.fromWebView
        ? 'read the web view at $tauriOrigin: ${all.local.length} keys of localStorage (${all.diskCount} in its files), databases ${all.web['databases']}'
        : 'no web view answered (${all.webFailure}): read localStorage from its files, ${all.local.length} keys'));
    final carried = <String>[], left = <String>[], failed = <String>[];
    final written = <String, String>{};
    for (final entry in all.local.entries) {
      final key = entry.key;
      if (!key.startsWith('glyph-') || key == carrySessionKey || key == carryGithubKey) continue;
      if (prefs.read(key) != null) {
        left.add(key);
        continue;
      }
      if (await prefs.write(key, entry.value)) {
        written[key] = entry.value;
      } else {
        failed.add(key);
      }
    }
    // Read back from where it is kept, not from what was just handed over.
    await prefs.reload();
    written.forEach((key, value) => (prefs.read(key) == value ? carried : failed).add(key));

    // The team notes' documents, for the account that is signed in.
    final accountId = _accountIdOf(all.local[carrySessionKey]);
    var documents = 0;
    final team = all.web['team'];
    if (team is List && team.isNotEmpty) {
      if (accountId == null) {
        await _log('${team.length} team documents with no session to say whose: left where they are');
      } else {
        for (final each in team) {
          final name = await _carryDocument(accountId, each);
          if (name == null) continue;
          documents += 1;
          (name.$2 ? carried : left).add('team/${name.$1}');
        }
      }
    }
    await _log('settings: carried ${carried.length} (${carried.where((name) => !name.startsWith('team/')).join(', ')}), $documents team documents, left ${left.length} this app already held (${left.join(', ')}), failed ${failed.length} (${failed.join(', ')})');
    if (failed.isNotEmpty) return CarryOutcome(ran: true, done: false, carried: carried, left: left, failed: failed);
    await _mark('settings', {'found': true, 'source': all.fromWebView ? 'webview' : 'files', 'carried': carried, 'left': left});
    return CarryOutcome(ran: true, done: true, carried: carried, left: left);
  }

  int? _accountIdOf(String? session) {
    if (session == null) return null;
    try {
      final read = jsonDecode(session);
      final id = read is Map ? read['accountId'] : null;
      return read is Map && read['token'] is String && read['handle'] is String && id is num ? id.toInt() : null;
    } catch (_) {
      return null;
    }
  }

  static final RegExp _plainId = RegExp(r'^[A-Za-z0-9_-]{1,62}$');
  static final RegExp _base64Url = RegExp(r'^[A-Za-z0-9_-]*$');

  /// One team document into `team/<account>/<note>.json`, in lib/team/docs.dart's own shape. Answers its name and
  /// whether it was written (false: this app already has one), or null for a record that is not a document.
  Future<(String, bool)?> _carryDocument(int accountId, Object? raw) async {
    if (raw is! Map) return null;
    final id = raw['id'], state = raw['state'], seq = raw['seq'], snapshotSeq = raw['snapshotSeq'], pending = raw['pending'];
    if (id is! String || !_plainId.hasMatch(id) || state is! String || !_base64Url.hasMatch(state) || seq is! num || snapshotSeq is! num || pending is! List) return null;
    if (pending.any((each) => each is! String || !_base64Url.hasMatch(each))) return null;
    final folder = Directory('$dataDir${Platform.pathSeparator}team${Platform.pathSeparator}$accountId');
    final file = File('${folder.path}${Platform.pathSeparator}$id.json');
    if (await file.exists()) return (id, false);
    await folder.create(recursive: true);
    final text = jsonEncode({'v': 1, 'state': state, 'seq': seq.toInt(), 'snapshotSeq': snapshotSeq.toInt(), 'pending': pending});
    final beside = File('${file.path}.new');
    await beside.writeAsString(text, flush: true);
    await beside.rename(file.path);
    if (await file.readAsString() != text) throw StateError('team document $id did not read back');
    return (id, true);
  }

  // --- the second half ----------------------------------------------------------------------------------------

  Future<CarryOutcome> _carrySecrets(CoreInvoke core) async {
    final marker = await _marker();
    if (marker['secrets'] is Map) return const CarryOutcome(ran: false, done: true);
    if (marker['settings'] is! Map) return const CarryOutcome(ran: true, done: false, failed: ['settings']);
    final all = await _gather();
    final want = <String, String>{};
    final notes = <String>[];

    final session = all.local[carrySessionKey];
    final signedIn = _accountIdOf(session) != null;
    if (signedIn) want[carrySessionKey] = session!;
    final github = all.local[carryGithubKey]?.trim();
    if (github != null && github.isNotEmpty) want[carryGithubKey] = github;
    want.addAll(await _slackWebhooks());
    final notion = await _notionAccount();
    if (notion != null) want[carryNotionKey] = notion;

    // The three keys, each proven before it is believed.
    final webKeys = all.web['keys'] is Map ? all.web['keys'] as Map : const {};
    final account = all.keys.account;
    if (account != null) {
      final probe = webKeys['account'] is Map ? (webKeys['account'] as Map)['probe'] : null;
      var proof = await _provesAccountKey(core, account.secret, probe is String ? probe : null);
      // With no page to seal a proof now, something the page sealed before is as good.
      if (proof == null && all.accountProbes.isNotEmpty) proof = await _opensOne(core, account.secret, all.accountProbes);
      if (proof == false) {
        notes.add('the account key read from the files did not open what the page sealed: not carried');
      } else {
        want['account'] = _b64(account.secret);
        notes.add(proof == true ? 'the account key opened what the page sealed' : (all.accountRead ?? 'the account key was read but no web view could seal a proof: carried as read'));
      }
    }
    for (final (name, kind, key) in [('device', 'device', all.keys.device), ('encryption', 'pair', all.keys.encryption)]) {
      if (key == null) continue;
      final said = webKeys[name] is Map ? (webKeys[name] as Map)['public'] : null;
      final public = await _publicOf(core, kind, key.secret);
      final beside = key.public == null ? null : _b64(key.public!);
      if (public == null || beside == null || public != beside || (said is String && said != public)) {
        notes.add('the $name key read from the files does not answer its public key: not carried');
      } else {
        want[name] = _b64(key.secret);
        notes.add('the $name key answers its public key${said is String ? ', the page\'s too' : ''}');
      }
    }
    if (signedIn && !want.containsKey('account')) {
      notes.add(all.keys.found ? 'signed in, but the account key could not be read: the password is asked once' : 'signed in, with no key database in the files: the password is asked once');
    }
    notes.addAll(all.notes);
    if (webKeys['account'] is Map && account == null) notes.add('the page holds an account key (${(webKeys['account'] as Map)['algorithm']}) that the files did not give (${all.idbDamaged} damaged)');

    final carried = <String>[], left = <String>[], failed = <String>[];
    for (final entry in want.entries) {
      if (await secure.read(entry.key) != null) {
        left.add(entry.key);
        continue;
      }
      try {
        await secure.write(entry.key, entry.value);
        (await secure.read(entry.key) == entry.value ? carried : failed).add(entry.key);
      } catch (_) {
        failed.add(entry.key);
      }
    }
    for (final note in notes) {
      await _log('secrets: $note');
    }
    await _log('secrets: carried ${carried.length} (${carried.join(', ')}), left ${left.length} this app already held (${left.join(', ')}), failed ${failed.length} (${failed.join(', ')})');
    if (failed.isNotEmpty) return CarryOutcome(ran: true, done: false, carried: carried, left: left, failed: failed);
    try {
      await device.forgetWork(carryStaleWork);
    } catch (failure) {
      await _log('secrets: the Tauri app\'s update check could not be let go of ($failure): it fails by itself');
    }
    await _mark('secrets', {'found': true, 'carried': carried, 'left': left, 'notes': notes});
    return CarryOutcome(ran: true, done: true, carried: carried, left: left);
  }

  static String _b64(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

  /// Whether the key opens the page's probe: true, false, or null when there was no probe to open.
  Future<bool?> _provesAccountKey(CoreInvoke core, Uint8List secret, String? probe) async {
    if (probe == null) return null;
    int? handle;
    try {
      handle = ((await core('key_restore', {'kind': 'account', 'raw': _b64(secret)})) as Map)['key'] as int;
      final text = await core('open', {'key': handle, 'context': carryProbeContext, 'blob': probe, 'as': 'text'});
      return text is String && jsonDecode(text) == 'ghost-carry';
    } catch (_) {
      return false;
    } finally {
      if (handle != null) await core('key_forget', {'key': handle}).catchError((Object _) => null);
    }
  }

  /// Whether the key opens any of what the page sealed under its account key ([CarryRead.accountProbes]).
  Future<bool> _opensOne(CoreInvoke core, Uint8List secret, List<({String context, String blob})> probes) async {
    int? handle;
    try {
      handle = ((await core('key_restore', {'kind': 'account', 'raw': _b64(secret)})) as Map)['key'] as int;
      for (final probe in probes.take(12)) {
        try {
          if (await core('open', {'key': handle, 'context': probe.context, 'blob': probe.blob, 'as': 'text'}) is String) return true;
        } catch (_) {
          // Not this one: an older row, or not this key.
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      if (handle != null) await core('key_forget', {'key': handle}).catchError((Object _) => null);
    }
  }

  /// The public half the core answers for a private key of [kind], or null for one it will not take.
  Future<String?> _publicOf(CoreInvoke core, String kind, Uint8List secret) async {
    try {
      final said = (await core('key_restore', {'kind': kind, 'raw': _b64(secret)})) as Map;
      final handle = said['key'];
      if (handle is int) await core('key_forget', {'key': handle}).catchError((Object _) => null);
      return said['public'] as String?;
    } catch (_) {
      return null;
    }
  }

  static final RegExp _slackId = RegExp(r'^[A-Za-z0-9-]{1,44}$');

  /// `slack.json`: each channel's webhook, by the name this app keeps it under.
  Future<Map<String, String>> _slackWebhooks() async {
    final read = await _jsonFile('slack.json');
    final channels = read is Map ? read['channels'] : null;
    if (channels is! Map) return const {};
    return {
      for (final entry in channels.entries)
        if (entry.key is String && _slackId.hasMatch(entry.key as String) && entry.value is String && (entry.value as String).startsWith('https://hooks.slack.com/')) '$carrySlackPrefix${entry.key}': entry.value as String,
    };
  }

  /// `notion.json`: the sign-in, in the shape lib/plugins/notion/client.dart keeps (the file's own names).
  Future<String?> _notionAccount() async {
    final read = await _jsonFile('notion.json');
    if (read is! Map) return null;
    final token = read['accessToken'];
    if (token is! String || token.isEmpty) return null;
    String? text(String name) => read[name] is String ? read[name] as String : null;
    return jsonEncode({'accessToken': token, 'refreshToken': text('refreshToken'), 'botId': text('botId'), 'workspaceId': text('workspaceId'), 'workspaceName': text('workspaceName'), 'workspaceIcon': text('workspaceIcon')});
  }

  Future<Object?> _jsonFile(String name) async {
    try {
      final file = File('${source.filesDir}${Platform.pathSeparator}$name');
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null;
    }
  }
}
