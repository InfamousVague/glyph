/// Starting over: everything a person made or chose on this phone goes, and Ghost.md starts again on the welcome
/// guide. A port of `src/app/core/reset.ts`.
///
/// Developer settings, from where this is reached, stay on. The downloaded models stay unless asked to go too: they
/// are gigabytes a person waited for, and a reset to test the app is not a reason to fetch them again.
///
/// What the app keeps itself is every key named `glyph-` (lib/core/stored.dart) and every plugin's, switched on or
/// not, found by asking storage what it holds and not from a list; and, here, every secret a plugin named. The notes,
/// recordings, pictures, version files and models are files, and the native side's ([ResetNative]).
///
/// The ORDER is load-bearing, as on the page: the account is forgotten before anything is wiped ([forgetAccount]),
/// never after. The sync bookkeeping (`glyph-sync-<account>-<part>`) says which notes this device last saw on the
/// account, so a device whose notes were wiped under it would read every one as deleted here and send the deletions
/// to the account and so to every other device. Signing out first, waiting out a sync already running, and only then
/// wiping leaves nothing that could sync; a device that cannot be signed out is reset not at all.
///
/// A meeting being recorded is refused outright: the service has the microphone and a file growing under it. The
/// write-ups queued on the phone are cancelled before their files are removed.
///
/// In order, [resetLocalData] does:
/// 1. with a native side: refuses a binary older than [resetGeneration], and refuses while a meeting is recording;
/// 2. [forgetAccount]: signs the device out (the session and the three keys of lib/account/keystore.dart `KeyStore`,
///    by the sync engine's `signOutHere`), waits for a sync already running, throws if a sync signed it back in,
///    forgets whatever the [KeyStore] still holds, and removes every `glyph-sync-` key;
/// 3. with a native side: [ResetNative.cancelWriteUps], then [ResetNative.resetLocalData] (the library folder, the
///    recordings, the pictures, the secure store, and the models when asked); with none, [ResetGround.wipeHere];
/// 4. [clearPluginSecrets]: every secret a plugin named, forgotten in the secure store by name;
/// 5. [clearPageData]: every `glyph-` key and every plugin's key but the [spared];
/// 6. [ResetGround.restart].
///
/// What differs:
/// - The page's imports are one value, [ResetGround], which the app's root makes from the things it already holds
///   (the sync engine, the meeting's state, the native channel) and a test makes from fakes. `isTauri()` is whether
///   [ResetGround.native] was given.
/// - `window.location.reload()` is [ResetGround.restart]: the root starting again on the welcome guide with its
///   preferences and stores read afresh. Nothing here can restart a Flutter app.
/// - The browser's `deleteImages` (IndexedDB `glyph-images`) is [ResetGround.wipeHere], for a build whose library is
///   not the native one. Link previews (`glyph-link-previews`), the unsent versions (`glyph-versions-unsent`) and
///   every other kept cache are `glyph-` keys and go with step 5; the versions' files are in the library's folder
///   and go with step 3.
/// - **Plugin secrets are new.** The page kept GitHub's token in localStorage, where step 5 cleared it, and Notion's
///   and Slack's in Rust's files, which `reset_local_data` removed. Here they are in the secure store
///   (lib/account/device_keys.dart `SecureStore`), which can only read and write by name, so step 4 needs the names:
///   the manifest's own, and for a name ending in `:` (a prefix of several) the full names from whoever holds them
///   ([ResetGround.secretsUnder]), asked before step 5 clears the storage they are listed in. The native wipe of step
///   3 also empties the secure store wholesale; step 4 is what makes a reset complete where there is no native side,
///   and what clears the hosts' own memory of what they read ([usePluginGround]).
/// - [forgetAccount] also empties the [KeyStore] when one is given, after the sign-out, so a key left by a sign-in
///   that never finished does not outlive a reset. Signing out already empties it on the page and here.
/// - A secret that could not be forgotten does not stop the reset (the notes are gone by then, and a half-reset app
///   is worse): everything else is cleared, the app restarts, and the failure is thrown after, naming the secrets.
library;

import 'dart:async';

import '../account/device_keys.dart' show MemorySecureStore, SecureStore;
import '../account/keystore.dart' show KeyStore;
import '../capture/meeting.dart' show stopTheMeeting;
import '../plugins/host.dart' show pluginGround, usePluginGround;
import '../plugins/registry.dart' show plugins;
import 'stored.dart';

export '../capture/meeting.dart' show stopTheMeeting;

/// The binary generation that has `reset_local_data` (`RESET_GENERATION`).
const int resetGeneration = 11;

/// What a reset leaves behind (`SPARED`): developer mode, and the two smoke overrides a developer sets from its
/// bench or by hand (lib/art/wisp_settings.dart). Every other key goes, so a key added later is cleared without
/// anybody remembering to list it; one that should survive has to be named here, on purpose.
const Set<String> spared = {'glyph-developer', 'glyph-wip-assistant', 'glyph-wisp-draw', 'glyph-wisp-head'};

/// The name of the channel [ChannelResetNative] would speak on, for whoever writes the Kotlin side. See
/// [ResetNative] for what each method must do.
const String resetChannelName = 'ghost.md/reset';

/// The native half of a reset: what only the phone's own code can reach. The Dart side asks; the native side does.
///
/// What the native side must do, exactly:
/// - [resetLocalData]`(models)`: the web app's Rust `reset_local_data` (src-tauri/src/reset.rs). Close the library's
///   store, then remove the library folder (every note's Markdown file, the version files beside them, the trash),
///   the recordings and their tapes, the pictures and videos, the summaries and write-ups kept as files, Notion's and
///   Slack's old files if any are there, and every entry of the Kotlin secure store (the account's wrapped keys and
///   every plugin's secret: wholesale, not by name). With `models` true, the downloaded model files as well (Whisper
///   and the language models); with it false they stay. Leave the app's own folder ready for a first start: the
///   library opens empty and the starter notes are written by the next launch. A failure partway throws, with words
///   a person can read; whatever was removed stays removed.
/// - [cancelWriteUps]: cancel the write-ups queued on the phone's work queue (WorkManager), before their files go
///   (`GlyphHost.cancelWriteUps`). Synchronous on the page; here it may be asked and not waited for.
/// - [recording]: whether the meeting service is recording now (`meetingStateNow()?.recording`,
///   lib/capture/meeting_live.dart). A reset is refused while it is.
/// - [hasGeneration]: `hasNativeGeneration` (lib/ai/backend.dart): whether this binary is [resetGeneration] or newer.
abstract interface class ResetNative {
  Future<bool> hasGeneration(int wanted);
  bool recording();
  void cancelWriteUps();
  Future<void> resetLocalData({required bool models});
}

/// A [ResetNative] made of callbacks: the root's, from the holders it already has, and a test's.
class ResetNativeOf implements ResetNative {
  ResetNativeOf({Future<bool> Function(int wanted)? hasGeneration, bool Function()? recording, void Function()? cancelWriteUps, required Future<void> Function({required bool models}) resetLocalData})
      : _hasGeneration = hasGeneration,
        _recording = recording,
        _cancelWriteUps = cancelWriteUps,
        _resetLocalData = resetLocalData;

  final Future<bool> Function(int wanted)? _hasGeneration;
  final bool Function()? _recording;
  final void Function()? _cancelWriteUps;
  final Future<void> Function({required bool models}) _resetLocalData;

  @override
  Future<bool> hasGeneration(int wanted) async => await _hasGeneration?.call(wanted) ?? true;

  @override
  bool recording() => _recording?.call() ?? false;

  @override
  void cancelWriteUps() => _cancelWriteUps?.call();

  @override
  Future<void> resetLocalData({required bool models}) => _resetLocalData(models: models);
}

/// The account, as far as a reset can see it: `accountState().session`, `signOutHere` and `syncSettled`
/// (lib/sync/engine.dart `SyncEngine`).
class ResetAccount {
  const ResetAccount({required this.signedIn, required this.signOutHere, required this.syncSettled});

  /// A device with no account service at all: never signed in, and no sync to wait for.
  ResetAccount.none()
      : signedIn = _no,
        signOutHere = _nothing,
        syncSettled = _nothing;

  final bool Function() signedIn;
  final Future<void> Function() signOutHere;
  final Future<void> Function() syncSettled;

  static bool _no() => false;
  static Future<void> _nothing() async {}
}

/// What a reset stands on: the page's imports, as one value (see the header).
class ResetGround {
  ResetGround({
    Stored Function()? kept,
    ResetAccount? account,
    this.keys,
    this.native,
    this.wipeHere,
    List<String> Function()? pluginKeys,
    List<String> Function()? pluginSecrets,
    this.secretsUnder,
    SecureStore Function()? secrets,
    this.restart,
  })  : _kept = kept,
        account = account ?? ResetAccount.none(),
        _pluginKeys = pluginKeys,
        _pluginSecrets = pluginSecrets,
        _secrets = secrets;

  final Stored Function()? _kept;
  final List<String> Function()? _pluginKeys;
  final List<String> Function()? _pluginSecrets;
  final SecureStore Function()? _secrets;

  /// The device's memory: the app's own ([stored]) unless given.
  Stored get kept => _kept?.call() ?? stored;

  final ResetAccount account;

  /// Where the session and the keys are kept, emptied after the sign-out; null and only the sign-out empties it.
  final KeyStore? keys;

  /// The phone's own half; null where the page's `isTauri()` is false.
  final ResetNative? native;

  /// What a build with no native side wipes itself (the browser's `deleteImages`): its pictures and its notes, where
  /// those are not `glyph-` keys.
  final Future<void> Function()? wipeHere;

  /// Every key any plugin owns (`plugins.storageKeys()`): the app's registry unless given.
  List<String> pluginKeys() => _pluginKeys?.call() ?? plugins.storageKeys();

  /// Every secret any plugin names (`plugins.secretNames()`); one ending in `:` is the prefix of several.
  List<String> pluginSecrets() => _pluginSecrets?.call() ?? plugins.secretNames();

  /// The full names kept under a prefix (`slack-webhook:` gives `slack-webhook:<channel id>` for each channel),
  /// answered by whoever holds them, from what is kept NOW: it is asked before the storage is cleared.
  final Iterable<String> Function(String prefix)? secretsUnder;

  /// The secure store: the plugins' own ground ([pluginGround]) unless given.
  SecureStore get secrets => _secrets?.call() ?? pluginGround.secrets;

  /// The app starting again on the welcome guide (`window.location.reload()`).
  final void Function()? restart;
}

/// A reset finished, but these secrets could not be forgotten: said after everything else has gone.
class SecretsLeft implements Exception {
  const SecretsLeft(this.names);
  final List<String> names;

  @override
  String toString() => 'Everything else was reset, but ${names.length == 1 ? 'a kept sign-in' : '${names.length} kept sign-ins'} could not be forgotten (${names.join(', ')}).';
}

String _why(Object failure) {
  final text = failure.toString();
  for (final lead in const ['Exception: ', 'Error: ', 'Bad state: ']) {
    if (text.startsWith(lead)) return text.substring(lead.length);
  }
  return text;
}

/// The first step of a reset, before anything is wiped (`forgetAccount`): this device signed out, a sync already
/// running finished, and every account's sync bookkeeping gone, so there is neither a session to sync with nor a
/// record that could read a wiped note as a deleted one. A device still signed in afterwards is reset not at all: it
/// throws with nothing wiped, and the notes and the bookkeeping still agree.
Future<void> forgetAccount(ResetGround ground) async {
  final account = ground.account;
  if (account.signedIn()) {
    try {
      await account.signOutHere();
    } catch (failure) {
      throw StateError('Could not sign out, so nothing was reset: ${_why(failure)}');
    }
  }
  await account.syncSettled();
  // A sync that renewed the session while it ran has signed the device back in.
  if (account.signedIn()) throw StateError('Could not sign out, so nothing was reset.');
  final keys = ground.keys;
  if (keys != null) {
    try {
      await keys.setSession(null);
      await keys.setAccountKey(null);
      await keys.setDeviceKey(null);
      await keys.setEncryptionKey(null);
    } catch (failure) {
      throw StateError('Could not sign out, so nothing was reset: ${_why(failure)}');
    }
  }
  final kept = ground.kept;
  for (final key in kept.keys()) {
    if (key.startsWith('glyph-sync-')) kept.write(key, null);
  }
}

/// Everything the app keeps itself in its memory, gone: every stored key but the [spared] (`clearPageData`). The
/// last step, once the account is forgotten and the notes are wiped. Not the notes' store, which is the native
/// side's, and no restart: [resetLocalData] does both.
void clearPageData(ResetGround ground) {
  final kept = ground.kept;
  final owned = ground.pluginKeys().toSet();
  for (final key in kept.keys()) {
    if ((key.startsWith('glyph-') || owned.contains(key)) && !spared.contains(key)) kept.write(key, null);
  }
}

/// Every plugin secret a reset can name: the manifests' own, the full names under each prefix from whoever holds
/// them, and whatever a store that can list itself holds under a named name or prefix.
List<String> pluginSecretNames(ResetGround ground) {
  final named = ground.pluginSecrets();
  final names = <String>{};
  final store = ground.secrets;
  final listed = store is MemorySecureStore ? store.held.keys.toList() : const <String>[];
  for (final name in named) {
    if (!name.endsWith(':')) {
      names.add(name);
      continue;
    }
    for (final full in ground.secretsUnder?.call(name) ?? const <String>[]) {
      if (full.startsWith(name) && full.length > name.length) names.add(full);
    }
    names.addAll(listed.where((full) => full.startsWith(name) && full.length > name.length));
  }
  return names.toList();
}

/// Forgets every plugin secret in the secure store, and what the plugins' hosts remember having read. Answers the
/// names that could not be forgotten. Call it before [clearPageData], which clears the storage the prefixed names
/// are listed in.
Future<List<String>> clearPluginSecrets(ResetGround ground) async {
  final store = ground.secrets;
  final left = <String>[];
  for (final name in pluginSecretNames(ground)) {
    try {
      await store.write(name, null);
      // Written and read back: a store that says nothing and keeps the value has not forgotten it.
      if (await store.read(name) != null) left.add(name);
    } catch (_) {
      left.add(name);
    }
  }
  // The hosts keep what they last read, by name, for their synchronous door (`PluginSecrets.held`): putting the
  // ground back in place is how that memory is cleared, and it tells whatever draws from a secret to read again.
  if (identical(store, pluginGround.secrets)) usePluginGround(pluginGround);
  return left;
}

/// The reset itself (`resetLocalData`): see the header for its steps and why they are in this order.
Future<void> resetLocalData(ResetGround ground, {required bool models}) async {
  final native = ground.native;
  if (native != null) {
    if (!(await native.hasGeneration(resetGeneration))) throw StateError('Resetting needs the newest Ghost.md. Install it from Settings > Updates.');
    if (native.recording()) throw StateError(stopTheMeeting);
  }
  await forgetAccount(ground);
  if (native != null) {
    native.cancelWriteUps();
    await native.resetLocalData(models: models);
  } else {
    await ground.wipeHere?.call();
  }
  final left = await clearPluginSecrets(ground);
  clearPageData(ground);
  ground.restart?.call();
  if (left.isNotEmpty) throw SecretsLeft(left);
}
