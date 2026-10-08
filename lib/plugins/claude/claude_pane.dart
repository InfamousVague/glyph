/// Settings › Claude: Claude on your notes, through the MCP server. What it is, the address Claude connects to with
/// a Copy, the instructions drawer ([ClaudeGuide]) for either way in, what Claude can do once it is connected, and
/// where the key lives - said here because it is the one thing a person should know before they sign in on the
/// page Claude opens. A port of `src/app/plugins/claude/ClaudePane.tsx`.
///
/// What differs: [handle] is handed in (claude.dart asks the app for it), where the page read the account itself;
/// the page is a [PaneBody] where React returned a fragment.
library;

import 'package:flutter/widgets.dart';

import '../../art/art.dart';
import '../../settings/kit/settings_kit.dart';
import 'claude_guide.dart';
import 'steps.dart';

class ClaudePane extends StatefulWidget {
  const ClaudePane({super.key, this.handle});

  /// The handle this device is signed in with, for the footnote and the sign-in command; null when it is not.
  final String? handle;

  @override
  State<ClaudePane> createState() => _ClaudePaneState();
}

class _ClaudePaneState extends State<ClaudePane> {
  Way? _guide;
  late final Copied _address = Copied(mcpUrl)..addListener(_redraw);

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _address
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handle = widget.handle;
    final address = mcpUrl;
    _address.text = address;
    return PaneBody(
      children: [
        const PaneSection(
          children: [
            PaneHero(
              glyph: AppIcon(Lucide.bot, size: 22),
              title: 'Claude, on your notes',
              meta: Text('Read, add to and change your notes from Claude, on any device you use it from. A note it makes or changes arrives here at the next sync, as one typed on a phone would.'),
            ),
          ],
        ),
        PaneSection(
          title: 'Connect',
          description: const Text('Two ways in: hosted, with nothing to install; or a file on your own computer, which keeps your key there.'),
          children: [
            SettingRow(
              icon: const AppIcon(Lucide.bookOpen, size: 16),
              label: 'How to connect',
              hint: const Text('The steps, for claude.ai, Claude Desktop and Claude Code.'),
              onPress: () => setState(() => _guide = Way.hosted),
            ),
            SettingRow(
              icon: const AppIcon(Lucide.link2, size: 16),
              label: 'Server address',
              // One line, as the page has it: an address has nowhere a page will break it, and at a phone's width its
              // last letters run under the Copy.
              hint: Text(address, softWrap: false, overflow: TextOverflow.visible),
              control: RowAction(onPress: _address.copy, child: Text(_address.value ? 'Copied' : 'Copy')),
            ),
            SettingRow(
              icon: const AppIcon(Lucide.laptop, size: 16),
              label: 'On your own computer',
              hint: const Text('One file, run with Node. Your key never leaves the machine.'),
              onPress: () => setState(() => _guide = Way.local),
            ),
          ],
        ),
        PaneSection(
          title: 'What Claude can do',
          description: const Text("Ask in words. Behind them are the connector's tools, and every one reads your notes fresh before it acts, so Claude sees what your phone last wrote."),
          children: [for (final tool in canDo) SettingRow(key: ValueKey(tool.name), label: tool.name, hint: Text(tool.words))],
        ),
        const PaneSection(
          title: 'Your key',
          children: [
            SettingsCallout(
              icon: AppIcon(Lucide.keyRound, size: 18),
              child: Text(
                'Your notes are end-to-end encrypted, so whatever reads them holds your account key. Hosted, Ghost.md’s server holds it while Claude is connected, in memory, and on disk only sealed so that nothing but Claude’s connection opens it, and forgets it when you disconnect or after a week unused. On your own computer, it never leaves the machine.',
              ),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsFootnote(
              child: Text(
                'Claude sees the words of the notes it reads, as it sees anything you paste into it. It cannot delete a note: it can archive one, which you can undo here. This plugin’s switch shows or hides this page; connecting and disconnecting Claude is done in Claude.'
                '${handle != null && handle.isNotEmpty ? ' Signed in here as $handle; the same handle and password sign Claude in.' : ' Sign in to an account first: Claude connects to the same one.'}',
              ),
            ),
            // Drawn over the page, not in it: it takes no room here, and so stands with the footnote, not after it.
            ClaudeGuide(way: _guide, handle: handle, onClose: () => setState(() => _guide = null)),
          ],
        ),
      ],
    );
  }
}
