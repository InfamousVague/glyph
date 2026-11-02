# Project tools as plugins

Matt, 2026-11-01: "Right now I think we have too many features by default, I'd like you to move the project
managment stuff like gantts and stuff into a suite of plugins that are disabled by default but when starting an org
it asks you which of the org based plugins you'd like to enable for gantts project managment and more".

And of the banner: "When a plugin is required for an org show a banner at the top with iconography asking the user to
enable them for the org".

This is the design he chose and what was built from it. The code is lib/plugins/projects/ (the suite, the scope, the
uses, the chips) and one manifest per plugin under lib/plugins/<id>/.

## 1. The suite

Seven plugins, all off by default, in their own category (`PluginCategory.projects`, "Project tools"); the Market
shows them together as one suite.

| Plugin | Id | Icon | What it holds | Needs |
| --- | --- | --- | --- | --- |
| Tickets | `tickets` | `ticket` | `type: ticket` notes and their panel; ticket notebooks (`key:`, `statuses:`, New ticket); `[[KEY-n]]` marks; My tickets and Triage; labels and components; bulk edit; sub-tickets and blockers; watchers; history; the digest (Settings › Notifications); duplicates and merge; the built-in Bug report and Feature templates and `ticketTemplates`; the query `from: tickets` source and the ticket query templates | |
| Planning | `planning` | `calendar-days` | cycles and sprints, estimates, burndown and velocity, epics, milestones and the roadmap view (lib/core/planning, core/query/planning.dart, ticket_planning.dart, plan_marks.dart) | Tickets |
| Gantt and timelines | `gantt` | `chart-gantt` | the ```` ```gantt ```` fence (core/gantt, editor/gantt), and the `show: gantt` and `show: timeline` query views | |
| Boards | `boards` | `square-kanban` | the ```` ```board ```` fence (core/boards*, editor/boards, band/board_actions.dart, board_note.dart, Settings › Examples' example board) and the `show: board` query view | |
| Automations | `automations` | `workflow` | the ```` ```rules ```` fence and its runs (book/rules*, root/root_ticket_rules.dart, the notebook's "Rules and GitHub…" sheet) | Tickets |
| Time tracking | `time-tracking` | `hourglass` | timers and time logs (book/timers, time_log, editor/tickets/ticket_work.dart, the palette's "Start timer on…", query card timers, the activity tray's timer jobs) | Tickets |
| Forms | `forms` | `text-cursor-input` | the ```` ```form ```` fence, the form inbox, admin and share rows (lib/forms, docs/FORMS.md) | Tickets |

GitHub's pull request links stay with the GitHub plugin, and need Tickets too: a PR is linked to a ticket.

What stays built in: tables, queries and their table, list, calendar, count and chart views, charts, buttons, rollups,
verified pages, templates other than the ticket ones, the to-do calendar, and the teamspace Home, Search and Updates
rows.

**The dependency.** Turning on a plugin that needs Tickets turns Tickets on too. Turning Tickets off warns, naming the
plugins that need it, and turns them off with it. A list that says a dependent without Tickets (written by hand, say)
reads the dependent as off: its features have nothing to stand on.

## 2. Where the switches are

**An organization's**: its `orgs/<Org>/Home.md` front matter, beside `docs:` and `pins:`:

    ---
    title: Home
    type: teamspace
    docs: edit
    plugins: [tickets, planning, gantt]
    icon: 🏠
    ---

read by `TeamspaceSettings.plugins` (lib/core/page_tree.dart) and written by `withProjectPlugins`, the pattern
`withDocsMode` set. So the whole team shares the list, it syncs as the team's notes do, and it stays markdown-first
(docs/MARKDOWN_FIRST.md): a clone of the Library folder has every organization's tools. No `plugins:` is none on.

**The person's own**: the plugin registry's switches (`glyph-plugins`), as every plugin has, made to travel between the
person's devices by naming the seven in `syncedSwitches` (lib/sync/connections.dart). Switched in the Market as any
plugin is.

**Which applies.** A note in an organization's space uses that organization's list; a personal note uses the
person's switches. The note's organization is the one its workspace is in (comments' `orgOfNote`), else the one whose
folder (`orgs/<Org>/`) its path is under. One check answers everywhere:

    projectPluginOn('gantt', noteId: id)       // the note's space
    projectPluginOn('tickets', orgId: org)      // an organization's
    projectPluginOn('tickets')                  // the person's own

`ProjectSuite` (lib/plugins/projects/suite.dart) is that check: a `Listenable`, told when the registry or any
organization's list changes, so a screen that asked follows a switch moved on another device or by a teammate.
`ProjectSuite.anywhere(id)` is on for the person or any of their organizations: what the app-wide rows (My tickets,
Triage, the digest, the palette's entries) ask.

## 3. Starting an organization

lib/orgs/ui/new_organization_sheet.dart has two steps. The name, then **"Which tools does this team use?"**: the
seven with their icons and one-line descriptions, all unchecked, then Create. Checking a plugin that needs Tickets
checks Tickets. Create makes the organization, then its `Home.md` there and then from `teamspaceHomeBody` with
`plugins:` set; the template's "Open tickets" query is written only when Tickets is on. The step is the same in
Simple mode and Advanced.

## 4. Existing use

Off for everyone, with no adopting migration: Matt's personal GHST notebook and HelloTrade's tickets go dark until
switched on. The banner and the chips are how the switch is found.

## 5. When a plugin is off

Plain text and a turn-on chip. The markdown shows as text or a code block, with a small chip (the plugin's icon and
"Turn on Gantt", or "Turn on Gantt for HelloTrade" in an organization's space). Nothing is rewritten or lost.

- A ticket's front matter is plain front matter, with the chip under it; `[[GHST-12]]` is a plain wiki link.
- Gantt, board, rules and form fences are code blocks with the chip under them.
- A query whose view or source needs an off plugin (`show: gantt`, `timeline`, `board`, `roadmap`, `burndown`,
  `velocity`; `from: tickets`) is its lines with the chip under them, in the query's place.
- Absent: the sidebar's My tickets and Triage, the palette's ticket and timer entries, the + and / rows for a ticket,
  a board and a gantt, the notebook's New ticket, Ticket key and Rules settings, timers, the digest and the form share
  rows.

## 6. The banner

When an organization's notes use a plugin its list does not have, a banner at the top of its space says so: on the
teamspace home, and at the top of any of its notes that uses one. Each missing plugin's icon and name, and one button,
"Turn on for <Org>", which adds them to Home.md's `plugins:` (Tickets with them where they need it; the home page is
made where there is none). Dismissing it is kept per device (`glyph-tool-banners`, by organization and the plugins it
named: a new one missing asks again). In Simple mode the banner is one line.

Usage is read cheaply from what a note's facts already keep (lib/core/note_facts.dart): its front matter (`type:
ticket`, a notebook's `key:` or `statuses:`, `cycle:`, `estimate:`, `epic:`, `milestone:`) and the names of its fences
(`gantt`, `board`, `rules`, `form`, and a `query`'s `show:` and `from:`). `NoteFacts.tools` is that set, worked out once
per body (lib/plugins/projects/uses.dart `toolsUsedIn`).

The teamspace home and the organization's settings sheet also have a **Tools** row: the suite with a switch each.

## 7. The in-app AI and the connector

The in-app AI's ticket tools (lib/claude/claude_books.dart `create_ticket` and its kin) answer, where Tickets is off for
the space, that it is off and how to turn it on, and make nothing. The MCP connector (mcp/) is left as it is, since
it only writes markdown; its ticket tools' descriptions say the app shows tickets only where the Tickets plugin is on.

## 8. Tests

Each plugin off (chips there, rows and entries absent, the markdown untouched) and on (as before); the dependency on
Tickets; the scope (an organization's list, the person's switches); the new organization's step writing `plugins:`;
the banner for a missing plugin and its button writing the list; the switches travelling. The existing tests build
their worlds with the suite on (`ProjectSuite.debugAllOn`, set for every test in test/flutter_test_config.dart), so
they go on testing the features; a test of the off state sets it back.

## 9. As built (2026-11-01)

Where each gate is, for whoever moves one:

- **The question**: lib/plugins/projects/suite.dart `projectPluginOn` / `ProjectSuite`; the root's suite is made in
  lib/root/ghost_root.dart (`_suite`) from lib/root/root_teamspaces.dart (a note's organization, a home page's list,
  writing it). What a note uses: lib/core/project_tools.dart `toolsUsedIn`, kept as `NoteFacts.tools`. A ticket whose
  front matter says `estimate:`, `cycle:`, `epic:` or `milestone:` uses Planning too, so its chip says "Turn on Tickets
  and Planning".
- **The editor** (lib/root/note_desk.dart): the board, the Gantt chart and the ticket panel are in a compartment
  (`_toolSlot`) reconfigured as the suite says the note's answer moved; the chips are lib/editor/tools/tool_chips.dart,
  drawn under a fence's closing run and before the line after a ticket's front matter. A query that needs an off tool
  is left as its lines (queries.dart `QueryOptions.held`); its switcher and builder offer only the views and kinds that
  are on (`offers`, `lists`), and a ticket's planning on a card and the cycle carry only with Planning (`planned`).
- **The + and /**: Make this a ticket, A board, A Gantt chart and the ready-made databases that need a tool
  (add_rows.dart `databaseRows`, `boardRows`, `AddConfig.queries`); the band's board actions; a notebook's New ticket,
  its ticket templates and New form; the blank page's Bug report and Feature cards (note_screen.dart).
- **Tickets everywhere else**: lib/root/library_reads.dart `ticketsOn` makes a ticket where Tickets is off no ticket
  at all, so My tickets, Triage, the palette's entries, `[[KEY-12]]`, the digest's words and the pull requests' moves
  read none; the digest's runner and Settings › Notifications' digest are there only where Tickets is on anywhere; a
  notebook's Ticket key and Rules and GitHub… rows (note_screen.dart).
- **Automations**: a notebook's rules run only where it is on (root_ticket_rules.dart, through `TicketRules.canEdit`).
- **Time tracking**: a ticket's timer in its panel and on a card, and the palette's Start timer on…; a timer already
  running can still be stopped.
- **Forms**: the share sheet's form rows (share_rows.dart); the form inbox is not read while Forms is off for
  everyone, so answers wait on the service and nothing is lost (account_wiring.dart).
- **The in-app AI**: create_ticket where Tickets is off makes nothing and says so, offering to turn it on; with the
  person's yes it is called again with `turn_on_tickets: true`. create_notebook with a key says Tickets is off.
- **The Market**: the seven on a shelf of their own, "Project tools"; adding one adds Tickets where it needs it;
  removing Tickets while tools that need it are on says which at the first press and takes them at the second.
- **Organizations**: the new organization's second step (new_organization_sheet.dart) hands the tools to the root,
  which writes `Home.md` there and then; the banner (tool_chip.dart `ToolBanner`) on the teamspace home and at the
  top of an organization's note; Tools (tool_switches.dart) on the teamspace home (behind More in Simple) and as a
  section of the organization's settings sheet.
