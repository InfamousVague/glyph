/// Keys and connections kept the same on every device of the account (Matt, 2026-10-26: "Also make it so things
/// like the Claude tokens and other stuff is kept in sync across all instances of ghost logged in to my account").
/// The port's own: the web app kept each of these per device.
///
/// What it is for: that morning a meeting's summary stuck on the Mac, because Claude's key was kept per device and
/// only the Fold had one (lib/ai/summary_handoff.dart). Now the key, the Claude switch, the model and the spending
/// limit, the Slack and Discord channels with their webhooks, where meetings post, and the GitHub token follow the
/// account (lib/sync/connections.dart has the list, and says why each thing that stays on a device stays).
///
/// HOW THEY TRAVEL: in the synced settings (lib/sync/prefs.dart), under one key, [sealedKeysKey], so nothing new is
/// asked of the service, and **each value is sealed again on its own** before it goes in, under the account key with
/// `key:<name>` as its associated data. The settings blob is sealed as a whole already, so the service reads none of
/// it either way; the second seal is for the device itself: the settings are kept in the device's ordinary storage
/// (`glyph-preferences`, and the copy of what the account holds, `glyph-sync-<id>-prefs-held`), and a key must not
/// sit there readable. What the settings hold of a key is its name, when it last changed and on which device, and a
/// sealed string: `{name: {at, by, sealed}}`, or `{at, by, gone: true}` for one taken away. And the `key:<name>` the
/// seal is made under means an entry moved to another name will not open.
///
/// WHERE THE VALUES LIVE stays where the code reads them today: Claude's in the device's secure store
/// (lib/claude/claude_settings.dart), a plugin's secrets in its host's secure store and its settings in its storage
/// (lib/plugins/host.dart), the plugins' switches in the registry. A [SyncedItem] is one of them, read and written
/// through the door its owner already uses, so the code that reads a key does not know it travelled.
///
/// A PASS (lib/sync/engine.dart, the Preferences step) is three moves:
/// 1. **[SealedKeys.gather]**: each item is read here and compared with what the settings hold of it, opened. One that
///    differs, and whose entry this device has already taken, was changed here: it is sealed into a new entry, at
///    now (and never at or before the entry it replaces), by this device. One whose entry arrived and has not been
///    taken yet is left to the third move.
/// 2. The settings' own pass sends them, or takes another device's, merging [sealedKeysKey] an entry at a time
///    ([mergedSealedKeys]).
/// 3. **[SealedKeys.apply]**: each entry this device has not taken yet is opened and written into its item, values
///    before removals (a Slack channel's webhook is there before its name lists it, and its name is gone before its
///    webhook is), and the owner reads it again (Claude's settings, the plugin's page), so the next request uses the
///    new key. Which entries this device has taken is kept per account, `glyph-sync-<id>-keys`, as `{name: at}`:
///    times, never a value.
///
/// THE RULES, each a test (test/sync/sealed_keys_test.dart):
/// - **The last change wins, an item at a time.** Two devices that changed the same key between syncs: the entry
///   made later stands on both. A tie goes to the device id that sorts last, so both pick the same one.
/// - **A removal is a change too.** A key taken away on one device leaves a tombstone, `gone`, which takes it away on
///   every other at its next sync; a tombstone is kept, so a device that was away a long time does not bring the key
///   back.
/// - **A device's first sync takes the account's**, as the settings do: a key the account has replaces this device's,
///   and a key only this device has is sent (lib/sync/prefs.dart keeps such an entry unseen, so it goes).
/// - **The switch** (Settings › Account › Keep keys and connections in sync, [keysInSync], this device's own and on
///   unless turned off): off, nothing of this device's goes into the settings and nothing that arrives is written
///   here; each device keeps the copy it has. The entries already in the account stay there, sealed, and other
///   devices go on with them.
/// - **The account's own, never a team's.** The settings are the account's, sealed under its key; an organization's
///   key never sees them, and a teammate's device never has them.
/// - **Not on an iPhone what is not on an iPhone** (lib/core/iphone_app.dart `notOnIPhone`): an item the device does
///   not offer is not in its list, so its entry is carried in the settings untouched. Claude's key goes to an iPhone.
/// - **An older build carries the entries untouched**: it does not sync [sealedKeysKey], so it keeps the key among the
///   blob's unknown ones and writes it back as it came (lib/sync/prefs.dart `PrefsContext.carried`). An item name this
///   build does not know is carried the same way, inside the map.
/// - **Nothing is logged.** A failure says what it was, never what it held.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../account/crypto_api.dart';
import '../core/preferences.dart';
import '../core/stored.dart';

/// The synced settings' key the entries are kept under, in [Preferences.more].
const String sealedKeysKey = 'sealedKeys';

/// The associated data a value is sealed under: its own name, so an entry moved to another name will not open.
String sealedKeyContext(String name) => 'key:$name';

/// Settings › Account › Keep keys and connections in sync: this device's own, on unless turned off (Matt's ask).
final DeviceFlag keysInSync = DeviceFlag('glyph-keys-sync', fallback: () => true);

/// One entry: when it was made, by which device, and the value sealed, or none for a key taken away.
@immutable
class SealedEntry {
  const SealedEntry({required this.at, required this.by, this.sealed});

  final int at;
  final String by;

  /// The value, sealed under the account key with [sealedKeyContext]; null for a tombstone.
  final String? sealed;

  bool get gone => sealed == null;

  /// One entry as the settings hold it; null for anything else.
  static SealedEntry? fromJson(Object? raw) {
    if (raw is! Map || raw['at'] is! num) return null;
    final by = raw['by'], sealed = raw['sealed'];
    if (sealed is! String && raw['gone'] != true) return null;
    return SealedEntry(at: (raw['at'] as num).toInt(), by: by is String ? by : '', sealed: sealed is String ? sealed : null);
  }

  Map<String, Object?> toJson() => {'at': at, 'by': by, if (sealed != null) 'sealed': sealed else 'gone': true};
}

/// The entries the settings hold, by name, as JSON.
Map<String, Object?> sealedEntriesOf(Preferences prefs) {
  final raw = prefs.more[sealedKeysKey];
  return raw is Map ? raw.cast<String, Object?>() : const {};
}

/// [prefs] holding [entries].
Preferences withSealedEntries(Preferences prefs, Map<String, Object?> entries) => prefs.copyWith(more: {...prefs.more, sealedKeysKey: entries});

/// [prefs] holding no entries: for signing out, so another account signed in to here is never sent this one's.
Preferences withoutSealedEntries(Preferences prefs) {
  if (!prefs.more.containsKey(sealedKeysKey)) return prefs;
  return prefs.copyWith(more: {...prefs.more}..remove(sealedKeysKey));
}

int _atOf(Object? raw) => raw is Map && raw['at'] is num ? (raw['at'] as num).toInt() : -1;
String _byOf(Object? raw) => raw is Map && raw['by'] is String ? raw['by'] as String : '';

/// Whether entry [a] was made after entry [b]: by its time, then by the device id, so two devices agree on a tie.
bool _later(Object? a, Object? b) {
  final at = _atOf(a), bt = _atOf(b);
  if (at != bt) return at > bt;
  return _byOf(a).compareTo(_byOf(b)) > 0;
}

String _said(Map<String, Object?> map, String key) => map.containsKey(key) ? jsonEncode(map[key]) : '\u0000';

/// This device's entries and another's, both changed since [base] (lib/sync/prefs.dart `merged`): an entry only one
/// of them changed is that one's, and one both changed is the later one's ([_later]). An entry is never dropped by the
/// merge: a removal is a tombstone, which is an entry.
Map<String, Object?> mergedSealedKeys(Map<String, Object?> base, Map<String, Object?> mine, Map<String, Object?> theirs) {
  final out = <String, Object?>{};
  for (final name in {...theirs.keys, ...mine.keys}) {
    final Object? pick;
    if (_said(mine, name) == _said(base, name)) {
      pick = theirs.containsKey(name) ? theirs[name] : mine[name];
    } else if (_said(theirs, name) == _said(base, name) || !theirs.containsKey(name)) {
      pick = mine[name];
    } else if (!mine.containsKey(name)) {
      pick = theirs[name];
    } else {
      pick = _later(theirs[name], mine[name]) ? theirs[name] : mine[name];
    }
    if (pick != null) out[name] = pick;
  }
  return out;
}

/// One thing that travels, read and written where its owner keeps it (lib/sync/connections.dart).
@immutable
class SyncedItem {
  const SyncedItem({required this.name, required this.read, required this.write, this.peek, this.order = 0});

  /// Its name in the settings: the secure store's or the storage's own name for it, or `plugin:<id>` for a switch.
  final String name;

  /// What this device holds, as text; null for nothing.
  final Future<String?> Function() read;

  /// Keeps [value] here, or takes it away for null, and has the owner read it again.
  final Future<void> Function(String? value) write;

  /// What the owner holds of it now, with no wait, for noticing a change made here: compared, never kept or said.
  final Object? Function()? peek;

  /// Written in this order on arrival, lowest first: a secret 0, a setting that names it 1, a switch 2.
  final int order;
}

/// What a gather or an apply works with: the account key and the crypto, and whose bookkeeping it is.
@immutable
class KeysContext {
  const KeysContext({required this.key, required this.crypto, required this.accountId});

  final SealKey key;
  final AccountCrypto crypto;
  final int accountId;
}

/// The device's side of the sealed keys (see the header), made once by the app's account and handed to the sync
/// engine, which runs [gather] and [apply] around the settings' pass and syncs soon after [changes].
class SealedKeys {
  /// [items] answers the items this device offers, given the names the settings already hold (a Slack channel's
  /// webhook is listed by its name there too). [heard] is what the items' owners tell of a change (Claude's settings,
  /// the plugins' storage and switches); [device] is this device's id ([SummaryDevice]); [on] is the switch,
  /// [keysInSync] unless a test gives its own.
  SealedKeys({required this.items, required this.prefs, required this.device, this.heard, ValueListenable<bool>? on, Stored? kept, int Function()? now})
      : on = on ?? keysInSync,
        _kept = kept,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final List<SyncedItem> Function(Set<String> named) items;
  final PreferencesStore prefs;
  final String Function() device;
  final Listenable? heard;
  final ValueListenable<bool> on;
  final Stored? _kept;
  final int Function() _now;

  Stored get _device => _kept ?? stored;

  final ValueNotifier<int> _changes = ValueNotifier<int>(0);

  /// Told when something here changed that should go: the engine syncs soon after.
  Listenable get changes => _changes;

  /// Whether [apply] is writing: what that changes is the account's, not the person's.
  bool _applying = false;

  /// What the items' peeks said last, as one number, for telling a change from a word that changed nothing.
  int? _signature;
  bool _started = false;

  /// Values opened, by name, with the sealed string they came from: a gather does not open every entry again.
  final Map<String, ({String sealed, String value})> _opened = {};

  static String _stateKey(int accountId) => 'glyph-sync-$accountId-keys';

  Map<String, int> _applied(int accountId) => _device.read<Map<String, int>>(
        _stateKey(accountId),
        <String, int>{},
        (raw) => raw is Map ? {for (final MapEntry(:key, :value) in raw.entries) if (key is String && value is num) key: value.toInt()} : null,
      );

  void _keepApplied(int accountId, Map<String, int> applied) => _device.write(_stateKey(accountId), applied.isEmpty ? null : applied);

  List<SyncedItem> _itemsNow() {
    try {
      return items(sealedEntriesOf(prefs.value).keys.toSet());
    } catch (failure) {
      debugPrint('[sync] the keys to sync could not be listed: ${failure.runtimeType}');
      return const [];
    }
  }

  int _peeked() => Object.hashAll([for (final item in _itemsNow()) Object.hash(item.name, item.peek?.call())]);

  void _heard() {
    if (_applying) return;
    final now = _peeked();
    if (now == _signature) return;
    _signature = now;
    if (on.value) _changes.value += 1;
  }

  void _switched() {
    // Turned back on: what changed meanwhile goes, and what arrived is taken.
    if (on.value) _changes.value += 1;
  }

  /// Starts listening for changes made here. Once.
  void start() {
    if (_started) return;
    _started = true;
    _signature = _peeked();
    heard?.addListener(_heard);
    on.addListener(_switched);
  }

  void dispose() {
    if (_started) {
      heard?.removeListener(_heard);
      on.removeListener(_switched);
    }
    _changes.dispose();
  }

  Future<String> _open(KeysContext ctx, String name, String sealed) async {
    final known = _opened[name];
    if (known != null && known.sealed == sealed) return known.value;
    final opened = await ctx.crypto.open(ctx.key, sealed, sealedKeyContext(name));
    final value = opened is Map ? opened['v'] : null;
    if (value is! String) throw const FormatException('Not a sealed key.');
    _opened[name] = (sealed: sealed, value: value);
    return value;
  }

  /// This device's changes, sealed into the settings (see the header, move 1). Answers how many items changed.
  Future<int> gather(KeysContext ctx) async {
    if (!on.value) return 0;
    final entries = {...sealedEntriesOf(prefs.value)};
    final applied = _applied(ctx.accountId);
    var changed = 0;
    for (final item in _itemsNow()) {
      final name = item.name;
      final entry = SealedEntry.fromJson(entries[name]);
      // Arrived and not taken yet: the apply's.
      if (entry != null && applied[name] != entry.at) continue;
      try {
        final here = await item.read();
        final there = entry == null || entry.gone ? null : await _open(ctx, name, entry.sealed!);
        if (here == there) continue;
        final at = math.max(_now(), (entry?.at ?? -1) + 1);
        final sealed = here == null ? null : await ctx.crypto.seal(ctx.key, {'v': here}, sealedKeyContext(name));
        if (sealed != null) _opened[name] = (sealed: sealed, value: here!);
        entries[name] = SealedEntry(at: at, by: device(), sealed: sealed).toJson();
        applied[name] = at;
        changed += 1;
      } catch (failure) {
        // This item stays as it was, and is looked at again next time; what it held is not said.
        debugPrint('[sync] the key “$name” was not gathered: ${failure.runtimeType}');
      }
    }
    if (changed > 0) {
      prefs.update((now) => withSealedEntries(now, entries));
      _keepApplied(ctx.accountId, applied);
    }
    return changed;
  }

  /// What other devices changed, written here (see the header, move 3). Answers how many items were written.
  Future<int> apply(KeysContext ctx) async {
    if (!on.value) return 0;
    final entries = sealedEntriesOf(prefs.value);
    final applied = _applied(ctx.accountId);
    final due = <({SyncedItem item, String? value, int at})>[];
    var kept = false;
    for (final item in _itemsNow()) {
      final entry = SealedEntry.fromJson(entries[item.name]);
      if (entry == null || applied[item.name] == entry.at) continue;
      try {
        due.add((item: item, value: entry.gone ? null : await _open(ctx, item.name, entry.sealed!), at: entry.at));
      } catch (failure) {
        // An entry that will not open is no entry: taken as seen, so this device's own goes over it next time.
        debugPrint('[sync] the key “${item.name}” did not open: ${failure.runtimeType}');
        applied[item.name] = entry.at;
        kept = true;
      }
    }
    // Values first, then removals, each in the items' order (see the header).
    due.sort((a, b) {
      final gone = (a.value == null ? 1 : 0) - (b.value == null ? 1 : 0);
      return gone != 0 ? gone : a.item.order - b.item.order;
    });
    var wrote = 0;
    _applying = true;
    try {
      for (final each in due) {
        try {
          if (await each.item.read() != each.value) {
            await each.item.write(each.value);
            wrote += 1;
          }
          applied[each.item.name] = each.at;
          kept = true;
        } catch (failure) {
          // Not written: tried again at the next pass.
          debugPrint('[sync] the key “${each.item.name}” was not written here: ${failure.runtimeType}');
        }
      }
    } finally {
      _applying = false;
      // What was written is what the owners hold now: not a change made here.
      _signature = _peeked();
    }
    if (kept) _keepApplied(ctx.accountId, applied);
    return wrote;
  }

  /// Forgets what this device took of [accountId]'s keys, and the entries from the settings here: for signing out.
  /// The values stay where they are kept, as the notes stay.
  void forget(int accountId) {
    _device.write(_stateKey(accountId), null);
    _opened.clear();
    prefs.update(withoutSealedEntries);
  }
}
