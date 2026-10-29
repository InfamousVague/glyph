/// Todoist's setup (lib/plugins/onboarding/setup_flow.dart; Matt, 2026-10-29: "add the voiceover onboarding for the rest
/// of the plugins"). Todoist keeps nothing: its token is pasted into the import on the plugin's page, used for that one
/// import and let go (todoist.dart, lib/settings/panes/import_pane.dart). So there is no paste and no check here, which
/// would keep a token the plugin is made never to keep; the setup is where the token is, and where it goes, seen once
/// ([setupSeen]):
///
/// 1. **Bring Todoist in**: what an import makes, and that the token is not kept.
/// 2. **Copy your token**: Todoist › Settings › Integrations › Developer ([todoistTokenUrl], the page's own path;
///    the address was not opened while this was written, unverified).
/// 3. **Import it**: Import from Todoist on this page, or a project's CSV export.
library;

import '../../art/lucide.g.dart';
import '../onboarding/setup_flow.dart';

/// Todoist's Settings › Integrations › Developer, where the API token is (unverified).
const String todoistTokenUrl = 'https://app.todoist.com/app/settings/integrations/developer';

/// Todoist's setup (see the header). [memory] is where it was seen; the device's own where null.
PluginSetup todoistSetup({SetupMemory? memory}) => PluginSetup(
      id: 'todoist',
      name: 'Todoist',
      hues: const ['red', 'coral', 'orange'],
      tiles: const [Lucide.listChecks, Lucide.folderInput, Lucide.keyRound, Lucide.squareCheckBig],
      ready: setupSeen('todoist', memory),
      watch: setupWatchesNothing,
      about: 'Three short steps: what an import makes, where your token is, and where it goes.',
      again: 'The steps from the start: the import, and where the token is.',
      steps: const [
        SetupIntro(
          id: 'intro',
          title: 'Bring Todoist in',
          icon: Lucide.listChecks,
          mark: false,
          points: [
            (Lucide.folderInput, 'Each project a note, its sections headings and its tasks to-dos'),
            (Lucide.squareCheckBig, 'Dates, priorities, labels and sub-tasks with them'),
            (Lucide.lock, 'The token is used for the one import and not kept'),
          ],
        ),
        SetupOpen(id: 'key', title: 'Copy your token', icon: Lucide.keyRound, links: [SetupLink('Open Todoist', todoistTokenUrl, verified: false)]),
        SetupDone(id: 'done', title: 'Import it', icon: Lucide.folderInput),
      ],
    );
