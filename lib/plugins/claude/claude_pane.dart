/// Settings › Claude: Claude on your notes, through the MCP server. What it is, the address Claude connects to with
/// a Copy, the instructions drawer ([ClaudeGuide]) for either way in, what Claude can do once it is connected, and
/// where the key lives - said here because it is the one thing a person should know before they sign in on the
/// page Claude opens. A port of `src/app/plugins/claude/ClaudePane.tsx`.
///
/// What differs: [handle] is handed in (claude.dart asks the app for it), where the page read the account itself;
/// the page is a [PaneBody] where React returned a fragment. And the plugin is the app's own Claude too
/// (docs/CLAUDE_APP.md): handed [inApp], the page is in two parts, "In the app" (the key, the model, the Ask Claude
/// note: claude_in_app.dart) and "From Claude’s own app" (the connector, the web's page as it is), each under a
/// heading of its own. Without it the page is the web's alone, as its measurements hold it
/// (test/plugins/claude/reference_test.dart).
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../settings/kit/settings_kit.dart';
import '../../settings/kit/settings_type.dart' show pageText;
import 'claude_guide.dart';
import 'steps.dart';

class ClaudePane extends StatefulWidget {
  const ClaudePane({super.key, this.handle, this.inApp, this.setup});

  /// The handle this device is signed in with, for the footnote and the sign-in command; null when it is not.
  final String? handle;

  /// The app's own Claude's cards ([ClaudeInApp]), drawn first under "In the app"; null draws the connector's page
  /// alone.
  final Widget? inApp;

  /// Set up, or Run setup again (lib/plugins/onboarding/setup_card.dart, claude_setup.dart), under the page's head;
  /// none where null, as the web's page has none.
  final Widget? setup;

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
    final inApp = widget.inApp;
    return PaneBody(
      children: [
        PaneSection(
          children: [
            PaneHero(
              glyph: const AppIcon(Lucide.bot, size: 22),
              title: 'Claude, on your notes',
              meta: Text(
                inApp == null
                    ? 'Read, add to and change your notes from Claude, on any device you use it from. A note it makes or changes arrives here at the next sync, as one typed on a phone would.'
                    : 'Ask Claude here, with your own API key, and watch it type into your notes. Or reach them from Claude’s own app, on any device you use it from: a note it makes or changes there arrives here at the next sync.',
              ),
            ),
          ],
        ),
        ?widget.setup,
        if (inApp != null) ...[
          const ClaudePartHeading(title: 'In the app', words: 'Claude on every page’s dock and in the command bar, answering with your own Anthropic API key.'),
          inApp,
          const ClaudePartHeading(title: 'From Claude’s own app', words: 'claude.ai, Claude Desktop or Claude Code, reaching your notes through Ghost.md’s MCP server. Nothing here runs it; it is connected in Claude.'),
        ],
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
                'Claude sees the words of the notes it reads, as it sees anything you paste into it. It cannot delete a note: it can archive one, which you can undo here. '
                '${inApp == null ? 'This plugin’s switch shows or hides this page; connecting and disconnecting Claude is done in Claude.' : 'Switched off, this plugin takes Claude off every dock and leaves the Ask Claude note alone; Claude’s own app is connected and disconnected in Claude.'}'
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

/// The head of one of the page's two parts: its name in the page's text, a line under it, in from the edge as a
/// card's title is. Not a card: the cards under it are the part.
class ClaudePartHeading extends StatelessWidget {
  const ClaudePartHeading({super.key, required this.title, required this.words});

  final String title;
  final String words;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(left: t.space(2), right: t.space(2), top: t.space(2)),
      child: Semantics(
        header: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: t.space(1),
          children: [
            Text(title, style: pageText(t, t.fontSize('md'), weight: 'semibold', color: t.color('app-ink'))),
            Text(words, style: pageText(t, t.fontSize('sm'), height: t.len('glacier-leading-sm'), color: t.color('app-ink-2'))),
          ],
        ),
      ),
    );
  }
}
