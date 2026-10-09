/// Starting over, for the app put together: the [ResetGround] lib/core/reset.dart stands on, made from what the
/// root already holds. What `src/app/core/reset.ts` got by importing the sync engine, the meeting's state, the
/// plugins and Tauri's `invoke`.
///
/// - **The account** is the sync engine's own sign-out and its wait for a sync already running; a build with no
///   account has none to forget.
/// - **The phone's half** is [PhoneReset] (lib/core/reset_native.dart): the core's `reset_local_data`, the write-ups
///   cancelled, the secure store emptied, and a meeting being recorded refused, by what the app last heard and by
///   the service's own answer. And the team notes' documents after it ([teamDocsIn], `<dataDir>/team`): they are
///   this port's own files, which the core's reset does not know of, and were left behind by Reset everything on
///   the emulator, signed in.
/// - **The plugins' secrets by name**: the manifests' own, and Slack's webhooks, one to a channel, named by
///   [slackSecretNames] from the channels kept now, before the storage that lists them is cleared.
/// - **The restart** is the root's: the preferences read again, and the whole app built anew on an empty library.
library;

import '../account/ui_state.dart';
import '../core/native/core.dart';
import '../core/preferences.dart';
import '../core/reset.dart';
import '../core/reset_native.dart';
import '../core/stored.dart';
import '../plugins/slack/channels.dart' show channels;
import '../plugins/slack/manifest.dart' show webhookPrefix;
import '../team/docs.dart' show FileDocs;

/// The full names Slack's webhooks are kept under in the secure store, one to a channel on this device: what a
/// reset forgets by name, since the store cannot list what it holds.
List<String> slackSecretNames() => [for (final channel in channels()) '$webhookPrefix${channel.id}'];

/// The names kept under [prefix] (`ResetGround.secretsUnder`): Slack's is the only prefix a plugin names.
Iterable<String> secretsUnder(String prefix) => prefix == webhookPrefix ? slackSecretNames() : const <String>[];

/// The ground a reset stands on in this app. [recordingNow] is the meeting's state as the app last heard it;
/// [restart] builds the app anew. With no [invoke] (a test, a picture) there is no phone half, and the reset is the
/// account, the plugins' secrets and the device's memory.
ResetGround resetGroundFor({CoreInvoke? invoke, AccountServices? services, bool Function()? recordingNow, Stored Function()? kept, PreferencesStore? prefs, void Function()? restart, String? teamDocsIn}) {
  final phone = invoke == null ? null : PhoneReset(invoke: invoke, recordingNow: recordingNow);
  final engine = services?.engine;
  return ResetGround(
    kept: kept,
    account: services == null
        ? null
        : ResetAccount(
            signedIn: () => services.signedIn,
            signOutHere: () async => engine == null ? services.account.signOut() : engine.signOutHere(),
            syncSettled: () async => engine?.syncSettled(),
          ),
    native: phone == null
        ? null
        : ResetNativeOf(
            hasGeneration: phone.hasGeneration,
            recording: phone.recording,
            cancelWriteUps: phone.cancelWriteUps,
            resetLocalData: ({required bool models}) async {
              await phone.resetLocalData(models: models);
              // The team notes' documents go with the notes: the data directory the account's were kept in.
              if (teamDocsIn != null) await FileDocs.forgetAll(teamDocsIn);
            },
          ),
    secretsUnder: secretsUnder,
    restart: () {
      (prefs ?? preferences).reload();
      restart?.call();
    },
  );
}
