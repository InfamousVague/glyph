/// The words of Settings › Claude and its instructions drawer (claude_pane.dart, claude_guide.dart): where Claude
/// connects, the two ways in, and what it can do once it is. The same facts as the web app's docs/MCP.md, said for
/// a phone. A port of `src/app/plugins/claude/steps.ts`, word for word.
///
/// The addresses follow the sync service this build talks to, so a staging or local build points Claude at its own
/// server rather than the real one.
///
/// What differs: the page read its service's base from its build (`API_BASE`, core/account/api.ts, which falls back
/// to ghostmarkdown.com). An app here has no base unless it is given one (lib/account/api.dart), so the base these
/// words are written round is [claudeApiBase]: the real service's until the app's root sets the one its account
/// uses. Nothing is asked of it from here; it is only shown, to be copied. `MCP_URL` and `LOCAL_FILE_URL` are
/// [mcpUrl] and [localFileUrl], read each time.
library;

/// The sync service's base, with no slash at its end: `https://ghostmarkdown.com/api`.
String claudeApiBase = 'https://ghostmarkdown.com/api';

/// Where Claude connects: the hosted MCP server, reached through the sync service (`MCP_URL`).
String get mcpUrl => '$claudeApiBase/mcp';

/// The one-file server for a person's own computer, published beside the app (`LOCAL_FILE_URL`).
String get localFileUrl => claudeApiBase.replaceFirst(RegExp(r'/api$'), '/mcp/glyph-mcp.mjs');

/// The two ways in (`Way`).
enum Way { hosted, local }

class GuideStep {
  const GuideStep({required this.title, required this.body, this.snippets = const []});
  final String title;
  final String body;

  /// Things to copy, each shown as a block with a Copy: an address, a command, a piece of a config file.
  final List<String> snippets;
}

class Guide {
  const Guide({required this.way, required this.label, required this.lead, required this.steps});
  final Way way;
  final String label;

  /// One line on what this way is, above the steps.
  final String lead;
  final List<GuideStep> steps;
}

/// The steps, one way at a time. [handle] fills the local sign-in command with the person's own handle when this
/// device is signed in, so it can be copied and run as it is.
List<Guide> guides(String? handle) {
  final who = handle ?? '<your handle>';
  final mcp = mcpUrl;
  return [
    Guide(
      way: Way.hosted,
      label: 'Hosted',
      lead: 'Nothing to install. Claude connects to Ghost.md’s server, and you sign in on a page once.',
      steps: [
        GuideStep(
          title: 'Add the server to Claude',
          body: 'In claude.ai or Claude Desktop: Settings › Connectors › Add custom connector, with this address. In Claude Code, one line in a terminal.',
          snippets: [mcp, 'claude mcp add --transport http glyph $mcp'],
        ),
        const GuideStep(
          title: 'Sign in on the page that opens',
          body:
              'Claude opens a Ghost.md page in your browser. Sign in with your handle and password, and you are back in Claude with the tools ready. Your password stays in the browser; your account key goes to Ghost.md’s server, which holds it while the connection lasts: in memory, and on disk only sealed, so that nothing but Claude’s connection opens it.',
        ),
        const GuideStep(
          title: 'Ask in words',
          body: '“What’s in my Groceries note?” “Add ‘book the ferry’ as a task to my Trip plan.” “Make a note called Standup with these three points.” “Which notes mention the cabin?”',
        ),
        const GuideStep(
          title: 'To end it',
          body: 'Disconnect the server in Claude. A week without using it ends it too, and the key with it.',
        ),
      ],
    ),
    Guide(
      way: Way.local,
      label: 'On your computer',
      lead: 'One file you run with Node. Your account key stays on your machine, and Ghost.md’s server never sees it.',
      steps: [
        GuideStep(
          title: 'Get the file',
          body: 'You need Node.js 20 or newer (node --version). Then the server, as one file:',
          snippets: ['curl -fsSL $localFileUrl -o ~/glyph-mcp.mjs'],
        ),
        GuideStep(
          title: 'Sign in once',
          body: 'The password is typed at the prompt and is not stored; what is kept is what a signed-in phone keeps, readable by you alone.',
          snippets: ['node ~/glyph-mcp.mjs login $who'],
        ),
        const GuideStep(
          title: 'Tell Claude where it is',
          body: 'In Claude Code, one line. In Claude Desktop: Settings › Developer › Edit Config, and add the server (with the full path to the file, not ~), then restart it.',
          snippets: [
            'claude mcp add glyph -- node ~/glyph-mcp.mjs',
            '{\n  "mcpServers": {\n    "glyph": { "command": "node", "args": ["/Users/you/glyph-mcp.mjs"] }\n  }\n}',
          ],
        ),
        const GuideStep(
          title: 'To end it',
          body: 'Forget the session on that computer, and remove the server from Claude.',
          snippets: ['node ~/glyph-mcp.mjs logout'],
        ),
      ],
    ),
  ];
}

/// What Claude can do once connected: the tools (the web app's mcp/server.ts), in words (`CAN_DO`).
const List<({String name, String words})> canDo = [
  (name: 'Read a note', words: 'One note in full, by its title.'),
  (name: 'List your notes', words: 'Newest change first, with a line of each.'),
  (name: 'Search', words: 'Notes whose words contain something, with the line around it.'),
  (name: 'Make a note', words: 'From markdown, with a title. Every Ghost.md mark works: lists, to-dos, tables, boards.'),
  (name: 'Add to a note', words: 'A task or an item joins the note’s list in its own style; a paragraph goes on the end.'),
  (name: 'Rewrite a note', words: 'The whole body replaced, never over a change another device made in between.'),
  (name: 'Pin or archive', words: 'Either, and undo either.'),
  (name: 'Delete a note', words: 'Into the Trash, as deleting here does, and back out of it. Emptying the Trash is yours alone.'),
  (name: 'Say which account', words: 'Whose notes these are, and how many.'),
];
