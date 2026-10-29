/// Notion's setup (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-29: "add the voiceover onboarding for the rest
/// of the plugins"). Four steps, in Notion's orange, over the plugin's own sign-in (client.dart), which its page uses
/// too (notion_pane.dart):
///
/// 1. **Your lists, as Notion tasks**: what it does, and that only the items sent go to Notion.
/// 2. **Sign in with Notion**: [startNotionSignIn], which opens Notion's consent page in the browser through
///    ghostmarkdown.com, where the person picks the pages and boards Ghost.md may use.
/// 3. **Check it worked**: the sign-in collected ([collectNotionSignIn]) if the page's own watch has not collected it
///    already, the account read ([notionAccount]), and the boards listed ([listBoards], Notion's `POST /search`,
///    which changes nothing). Said in plain words ([notionSetupResult]): still on Notion's page, refused, signed in
///    with no boards shared (a warning: signed in, and the way to share some is to sign in again), or signed in with
///    how many boards.
/// 4. **Try it**: a note linked to a board from its cog, and a list item swiped left.
library;

import '../../art/lucide.g.dart';
import '../details_cache.dart' show failureWords;
import '../host.dart' show onPluginStorage;
import '../onboarding/setup_flow.dart';
import 'client.dart';
import 'manifest.dart' show host;

/// The check's answer (see the header). Never throws.
Future<SetupResult> notionSetupResult() async {
  String? refused;
  try {
    final collected = await collectNotionSignIn();
    if (collected is NotionPending) return const SetupResult.failed('Notion is still waiting for you. Pick the boards Ghost.md may use on Notion’s page, press Allow, then check again.');
  } catch (failure) {
    refused = failureWords(failure);
  }
  // Collected already by the plugin's page as the app came back, or kept from before.
  final account = await notionAccount();
  if (!account.connected) return SetupResult.failed(refused ?? 'Ghost.md isn’t signed in to Notion yet. Sign in first.', pasteAgain: true);
  final name = account.workspaceName;
  final where = name != null && name.isNotEmpty ? name : 'Notion';
  try {
    final boards = await listBoards();
    if (boards.isEmpty) return SetupResult.warn('Signed in to $where, but no boards were shared. Sign in again and tick the boards you want on Notion’s page.');
    return SetupResult.ok('Signed in to $where, with ${boards.length == 1 ? '1 board' : '${boards.length} boards'} to send tasks to.');
  } catch (failure) {
    return SetupResult.warn('Signed in to $where. The boards couldn’t be read just now: ${failureWords(failure)}');
  }
}

/// Notion's setup (see the header).
PluginSetup notionSetup() => PluginSetup(
      id: 'notion',
      name: 'Notion',
      hues: const ['orange', 'amber', 'coral'],
      tiles: const [Lucide.squareKanban, Lucide.listChecks, Lucide.send, Lucide.link],
      ready: () => notionAccountNow().connected,
      watch: onPluginStorage,
      prepare: host.secrets.warm,
      about: 'A few short steps: sign in with Notion, pick the boards Ghost.md may use, and a check that it worked.',
      again: 'The steps from the start: signing in with Notion, and a check that it worked.',
      steps: [
        const SetupIntro(
          id: 'intro',
          title: 'Your lists, as Notion tasks',
          icon: Lucide.squareKanban,
          points: [
            (Lucide.link, 'Link a note to a Notion board, from the cog on the note'),
            (Lucide.send, 'Swipe a list item left, or send the whole list, and each becomes a task'),
            (Lucide.listChecks, 'Each item’s words become a link to its task'),
            (Lucide.lock, 'Only the items you send go to Notion; the rest of the note stays here'),
          ],
        ),
        SetupAct(
          id: 'signin',
          title: 'Sign in with Notion',
          icon: Lucide.link,
          label: 'Sign in with Notion',
          again: 'Sign in again',
          run: () async {
            try {
              await startNotionSignIn();
              return null;
            } catch (failure) {
              return failureWords(failure);
            }
          },
        ),
        const SetupCheck(id: 'check', title: 'Check it worked', icon: Lucide.shieldCheck, checking: 'Asking Notion…', run: notionSetupResult),
        const SetupDone(id: 'done', title: 'Try it', icon: Lucide.wandSparkles),
      ],
    );
