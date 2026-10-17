# Claude in the app, with your own key

Matt, 2026-10-17: "add the ability to add a anthropic API key to the app so ask Claude works in real time and note
creation and editing happens in real time when we ask Claude it should open up to the note it's editing and we
follow along with a stream from Claude". Then: "move the Claude chip to a icon on the home page dock and make it
match claudes brand colors"; "If we follow Claude I also want to see a cursor where Claude last typed and scroll the
screen to there after navigating us to the note"; "Make the ask Claude and other agents open a chat when we go to talk
to them". Of the two ways in offered, both: a chat to ask in, and the "Ask Claude" note done as requests are written.
The Flutter app first; the Tauri app has none of it.

docs/CLAUDE_LIVE.md is Claude reaching the account from outside, through the connector. This is the other way round:
the app asks Claude itself, with the person's Anthropic API key, and so sees Claude's words as the model writes them.
The connector can only type a tool call's words once the call is whole; here a note fills in token by token.

## What a person sees

1. **Claude on the dock.** The home page's dock has Claude at its head: a ring in Claude's orange (`#d97757`, the
   landing page's `.brand-claude`) with its mark in ivory. It turns slowly while Claude works in the app, and wears a
   small ivory dot while an AI is online through the connector. The top bar's Claude chip is gone; its menu (what each
   AI online is doing, Follow, Open) is in the chat.
2. **The chat.** A tap on the dock, the command bar's Ask Claude, the bar's Reply, or Chat on an AI's row of an
   organization's page opens a chat: over the whole window on a phone, a panel down the right on a wide one, closed by
   its back arrow or the back gesture. The person's words on the right, Claude's on the left as they arrive, each tool
   as a quiet line that opens its note, the field over the keyboard, Send (Stop while Claude works), New chat.
3. **Following along.** When Claude starts writing in a note, the chat makes way and the note opens; Claude's words
   are typed into it at Claude's caret, labelled Claude, and the page is kept scrolled to it. A bar under the top bar
   says what Claude is doing or the words it is saying, with Stop following and Stop; when it ends, Claude's answer in
   a line with Reply and Close. A press or a key in the note stops the following (the bar then offers Watch), never
   the typing: Claude's words go in where it was, moved along by anything typed above them.
4. **Where Claude last typed.** Between one tool call and the next, Claude's caret stays where it last typed. Watch
   (in the bar or the chat) opens the note Claude is in, puts its caret there and scrolls to it, even in an editor made
   again for the note. The carets go when the run ends. Follow for an AI through the connector does the same: the
   app keeps where each AI's caret was last seen in each note, and a note followed into after the AI has stopped
   typing shows Claude's caret there and scrolls to it.
5. **The "Ask Claude" note.** With a key and the switch on (Settings › Ask Claude), a `- [ ]` request written in the
   account's own note titled "Ask Claude" is done about four seconds after it last changed, never while the caret is
   on its line: Claude does it while it is watched, then the app writes one line under it, indented, and ticks it,
   unless it could not be done (mcp/prompts.ts's own format, so the connector's routine and the app agree). Without a
   key, what is written in the chat goes into that note as a request, for the connector's agents to work through.

## The key

Settings › Ask Claude (lib/settings/panes/claude_key_pane.dart): the key, checked before it is kept (one read of
`GET /v1/models`), shown only as its start and last four, with Check and Forget (asked twice); the model (Sonnet 5.5
by default, Opus 5.5, Haiku 5.5); the inbox switch. The key is kept in the device's secure storage
(lib/account/device_keys.dart: the Android Keystore, the Keychain on a Mac and an iPhone), never in the preferences,
never synced, never in the library folder a backup copies; each device is given its own. Off a phone and a Mac it is
memory only. What is asked, and the notes Claude reads to answer, go from the device to `api.anthropic.com` and
nowhere else; Anthropic bills the key.

## The stream

lib/claude/messages_api.dart posts `/v1/messages` with `stream: true` over `dart:io` and reads the server-sent events
(lib/claude/sse.dart). Every writing tool is declared with `eager_input_streaming: true`, so its input arrives as
Claude writes it, unbuffered; lib/claude/partial_json.dart reads the top level of that object from pieces cut
anywhere (in a key, a word, an escape, a surrogate pair) and says when each string field starts, each run of its
letters, and when it ends. The whole input is still parsed once its block closes; input that is not JSON is answered
`{"INVALID_JSON": ...}` with `is_error`, as the API's docs ask.

## A run

lib/claude/claude_run.dart: the request, Claude's words as they come, each tool answered once its input is whole, and
the next request with the answers, up to 24 requests, until Claude stops calling tools, is stopped, or fails. The
system prompt (lib/claude/claude_tools.dart `claudeSystem`) is who Claude is here, today's date, how to write into a
note being watched, and the account's "Claude rules" note. One run at a time (lib/claude/claude_runner.dart); an ask
while one works waits for it. The chat's conversation is kept until New chat or the app closes, and written nowhere.

## Tools

`list_notes`, `search_notes`, `read_note`, `open_note`; and the four that write and stream: `create_note` (`body`),
`append_to_note` (`id`, `text`), `replace_in_note` (`id`, `old_text` found exactly once, `new_text`), `rewrite_note`
(`id`, `body`). Nothing deletes, trashes, moves or shares. A note made is the account's own, in no workspace.

## Typing as Claude writes

When a writing tool's words start, the note is made or found, opened (lib/root/root_claude.dart `_RootClaudeDesk`),
and its editor handed to a typer (lib/claude/live_typing.dart). The old passage is taken out (replace, rewrite) and
the words go in at Claude's caret a few letters a frame, faster the further behind they are, never half a letter. The
editor stays the note's one writer: what is typed is the editor's own change (`userEvent: 'claude.type'`), saved by
the note's saving, carried to its live document where it is bound, undone by the person's undo, and risen out of smoke
where Ghostly typing is on and the note draws arrivals. Where the note cannot be shown, or is closed under Claude, the
rest is written behind it through the screen or the library (`ClaudeDesk.change`).

Every note's editor has `claudeTyping` (lib/root/note_desk.dart): the caret's field, which rides every change, and an
observer of the person's presses and keys.

## Honest limits

- An agent working through the connector cannot be messaged while it works: it is a tool call away, in Claude's own
  app. Its chat says so; with a key the app's own Claude answers, and without one the words go to the "Ask Claude"
  note.
- Words typed by the app's Claude reach another device only where the note is live there (docs/LIVE.md); that device
  sees the words arrive but no caret, since the app's Claude says nothing in the presence rooms.
- Not built in this cloud session's checkout: it could not fetch Flutter or the packages (pub.dev and Google's storage
  are refused here). `flutter analyze` and the tests below are to be run on the Mac before it is merged and shipped.

## Ownership

| Part | Where |
| --- | --- |
| The stream, the input reader, the tools, a run, the runner, the inbox | lib/claude/ |
| Typing and Claude's caret in an editor | lib/claude/live_typing.dart, in lib/root/note_desk.dart's extensions |
| The chat, the bar, the dock's Claude, the mark | lib/claude/claude_chat.dart, claude_bar.dart, claude_dock.dart, claude_mark.dart |
| The key's page | lib/settings/panes/claude_key_pane.dart, lib/settings/settings_sections.dart (`ask-claude`) |
| The library and the screen as Claude reaches them, the chat's part, the inbox's note | lib/root/root_claude.dart, ghost_root.dart, root_parts.dart |
| The dock's slot | lib/home/home_screen.dart (`HomeScreen.claude`) |
| Chat on an AI's row | lib/orgs/ui/organization_screen.dart (`onChat`) |
| Where a connector AI last typed, for Follow | lib/live/follow.dart |
| Ask Claude in the command bar | lib/commands/palette.dart, app_commands.dart |
| Tests | test/claude/, test/root/wiring_test.dart, test/settings/settings_sheet_test.dart |
