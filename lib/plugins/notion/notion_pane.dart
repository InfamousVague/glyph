/// The Notion plugin's page in Settings: signing in, and the boards Ghost.md can send tasks to. A port of
/// `src/app/plugins/notion/NotionPane.tsx`.
///
/// At its head, the setup's card (notion_setup.dart): Set up while signed out, Run setup again once signed in. Then one
/// card says whether Ghost.md is signed in and to which workspace, with Sign in or Sign out. Signing in opens
/// Notion in the browser, where the person picks the pages and boards Ghost.md may use; coming back to Ghost.md
/// collects the sign-in by itself. A second card lists the boards that were shared, so it is plain whether the
/// board a note should send to is one of them. Which note sends to which board is chosen on the note, from its cog.
///
/// What differs:
/// - The page's "Notion works in the app." (drawn in a browser) has no place in an app; a build that cannot reach
///   Notion says it needs the newest, as the page's app did.
/// - The page is a [PaneBody] where React returned a fragment, and the account is a [NotionAccountWatch] it makes
///   and disposes.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../art/art.dart';
import '../../settings/kit/settings_kit.dart';
import '../details_cache.dart' show failureWords;
import '../onboarding/setup_card.dart';
import '../onboarding/setup_flow.dart' show PluginSetup;
import 'client.dart';
import 'details.dart';
import 'notion_setup.dart';

class NotionPane extends StatefulWidget {
  const NotionPane({super.key, this.withSetup = true});

  /// The setup's card at the page's head (lib/plugins/onboarding/setup_card.dart). Left out only where the page is
  /// measured against the web page's (reference and measured tests), which never had one.
  final bool withSetup;

  @override
  State<NotionPane> createState() => _NotionPaneState();
}

class _NotionPaneState extends State<NotionPane> {
  late final NotionAccountWatch _watch = NotionAccountWatch()..addListener(_changed);
  late final PluginSetup _setup = notionSetup();
  bool? _available;
  bool _waiting = false;
  List<Board>? _boards;
  String? _trouble;
  bool _connected = false;

  /// Which asking of the boards an answer belongs to: one from before a sign-out is dropped.
  int _asking = 0;

  @override
  void initState() {
    super.initState();
    unawaited(notionAvailable().then((yes) {
      if (mounted) setState(() => _available = yes);
    }));
  }

  @override
  void dispose() {
    _watch
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final connected = _watch.account?.connected ?? false;
    final was = _connected;
    setState(() {
      _connected = connected;
      if (!connected) {
        _asking += 1;
        _boards = null;
      } else if (!was) {
        _waiting = false;
      }
    });
    if (connected && !was) unawaited(_look());
  }

  Future<void> _look() async {
    final asking = ++_asking;
    try {
      final found = await listBoards();
      if (mounted && asking == _asking) setState(() => _boards = found);
    } catch (failure) {
      if (mounted && asking == _asking) setState(() => _trouble = failureWords(failure));
    }
  }

  Future<void> _signIn() async {
    setState(() => _trouble = null);
    try {
      await startNotionSignIn();
      if (mounted) setState(() => _waiting = true);
    } catch (failure) {
      if (mounted) setState(() => _trouble = failureWords(failure));
    }
  }

  void _signOut() {
    forgetTaskDetails();
    unawaited(disconnectNotion().then((_) => _watch.refresh()));
  }

  @override
  Widget build(BuildContext context) {
    if (_available == false) {
      return const PaneBody(
        children: [
          SettingsEmpty(
            icon: AppIcon(Lucide.squareKanban, size: 22),
            title: 'Notion needs the newest Ghost.md.',
            body: Text('Install the latest version from Settings > Updates, then come back here to sign in.'),
          ),
        ],
      );
    }

    final account = _watch.account;
    final connected = account?.connected ?? false;
    final said = _watch.problem ?? _trouble;
    final boards = _boards;
    final workspace = account?.workspaceName;
    return PaneBody(
      children: [
        if (widget.withSetup) PluginSetupCard(setup: _setup),
        if (said != null && said.isNotEmpty) SettingsCallout(child: Text(said)),
        PaneSection(
          title: 'Account',
          description: const Text('Ghost.md sends list items to your Notion boards as tasks. Nothing else in your notes goes to Notion.'),
          children: [
            if (connected)
              SettingRow(
                label: 'Signed in to ${workspace != null && workspace.isNotEmpty ? workspace : 'Notion'}',
                hint: const Text('To give Ghost.md more boards, sign in again and pick them.'),
                control: RowAction(onPress: _signOut, child: const Text('Sign out')),
              )
            else
              SettingRow(
                label: _waiting ? 'Finish signing in on Notion' : 'Not signed in',
                hint: Text(_waiting ? 'Pick the boards Ghost.md can use, then come back here.' : 'Notion opens in your browser and asks which pages and boards Ghost.md may use.'),
                control: RowAction(onPress: () => unawaited(_signIn()), child: Text(_waiting ? 'Open again' : 'Sign in')),
              ),
          ],
        ),
        if (connected)
          PaneSection(
            title: 'Boards',
            description: const Text('The boards Notion let Ghost.md see. Link one to a note from the cog on that note.'),
            children: [
              if (boards == null)
                const SettingRow(label: 'Looking for boards…')
              else if (boards.isNotEmpty)
                for (final board in boards) SettingRow(key: ValueKey(board.id), icon: const AppIcon(Lucide.squareKanban, size: 16), label: board.title, hint: Text('Tasks are named by “${board.titleProperty}”.'))
              else
                const SettingRow(label: 'No boards shared yet', hint: Text("Sign in again and tick the boards you want on Notion's page.")),
            ],
          ),
        const SettingsFootnote(child: Text('Signing in goes through ghostmarkdown.com to finish the handshake with Notion. Your notes never do.')),
      ],
    );
  }
}
