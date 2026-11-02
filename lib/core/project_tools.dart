/// The project tools: seven plugins that are off until a person or a team turns them on (docs/PM_PLUGINS.md; Matt,
/// 2026-11-01: "Right now I think we have too many features by default, I'd like you to move the project managment
/// stuff like gantts and stuff into a suite of plugins that are disabled by default but when starting an org it asks
/// you which of the org based plugins you'd like to enable for gantts project managment and more").
///
/// This file is what the core needs of them and nothing that draws: their ids in the suite's order, which of them
/// stand on Tickets, and which of them a note's words use ([toolsUsedIn]), read from its front matter and the names
/// of its fences, so a note's facts (note_facts.dart `NoteFacts.tools`) can keep the answer and an organization's
/// banner can ask it of every note at no cost. The switches themselves, and the question "is it on here", are
/// lib/plugins/projects/suite.dart's.
library;

import 'front_matter.dart';
import 'properties.dart' show isTicketType;
import 'query/read.dart' show PlanView, QueryKind, ShowAs, readQuery;

/// Tickets: `type: ticket` notes, ticket notebooks, `[[KEY-n]]`, My tickets and Triage, and the rest of their kin.
const String ticketsTool = 'tickets';

/// Cycles, estimates, burndown, velocity, epics, milestones and the roadmap.
const String planningTool = 'planning';

/// The ```gantt fence, and the gantt and timeline views of a query.
const String ganttTool = 'gantt';

/// The ```board fence, and the board view of a query.
const String boardsTool = 'boards';

/// The ```rules fence and its runs.
const String automationsTool = 'automations';

/// Timers and time logs.
const String timeTrackingTool = 'time-tracking';

/// The ```form fence, its inbox and its share rows.
const String formsTool = 'forms';

/// The suite, in its order: the order the Market, the new organization's step and the Tools row list them in, and
/// the order a home page's `plugins:` is written in.
const List<String> projectTools = [ticketsTool, planningTool, ganttTool, boardsTool, automationsTool, timeTrackingTool, formsTool];

/// The tools that stand on Tickets: turning one on turns Tickets on, and Tickets off turns them off.
const Set<String> needTickets = {planningTool, automationsTool, timeTrackingTool, formsTool};

/// Whether [id] is one of the suite.
bool isProjectTool(String id) => projectTools.contains(id);

/// [ids] with what they need: Tickets added where any of them stands on it, the ones that are not tools left out, in
/// the suite's order.
List<String> withNeeds(Iterable<String> ids) {
  final asked = {for (final id in ids) id.trim().toLowerCase()};
  if (asked.any(needTickets.contains)) asked.add(ticketsTool);
  return [for (final id in projectTools) if (asked.contains(id)) id];
}

/// What a list as written turns on: its tools in the suite's order, a tool that needs Tickets left out where Tickets
/// is not in it (its features have nothing to stand on), a word that is no tool's left out.
Set<String> toolsOn(Iterable<String> listed) {
  final said = {for (final id in listed) id.trim().toLowerCase()};
  final tickets = said.contains(ticketsTool);
  return {
    for (final id in projectTools)
      if (said.contains(id) && (tickets || !needTickets.contains(id))) id,
  };
}

/// The tools among [on] that would go with Tickets: what turning it off warns of.
List<String> dependentsOf(Iterable<String> on) => [for (final id in projectTools) if (needTickets.contains(id) && on.contains(id)) id];

// ---- what a note uses ----------------------------------------------------------------------------------------------

/// A fence's opening line and the word after its run: ```gantt, ~~~board height=8, ```query.
final RegExp _opening = RegExp(r'^[ \t]*(?:`{3,}|~{3,})[ \t]*(gantt|board|rules|form|query)\b[^\n]*$', caseSensitive: false, multiLine: true);

/// A notebook's workflow, written on its line or as a list under it.
final RegExp _statuses = RegExp(r'^statuses[ \t]*:', multiLine: true, caseSensitive: false);

/// The planning keys a ticket's front matter may say.
const List<String> _planningKeys = ['cycle', 'sprint', 'estimate', 'epic', 'milestone'];

/// The tools a query's [body] needs: Tickets for `from: tickets`, Boards for `show: board`, Gantt for `show: gantt` and
/// `show: timeline`, Planning for a burndown, velocity and the roadmap. Nothing for a query that does not read: it is
/// drawn as its problem, whatever is on.
Set<String> toolsOfQuery(String body) {
  final query = readQuery(body).query;
  if (query == null) return const {};
  return {
    if (query.kind == QueryKind.tickets) ticketsTool,
    if (query.plan != null) ...{planningTool, ticketsTool},
    if (query.show == ShowAs.board) boardsTool,
    if (query.plan != PlanView.roadmap && (query.show == ShowAs.gantt || query.show == ShowAs.timeline)) ganttTool,
  };
}

/// The tools [body] uses, read from its front matter (`type: ticket`, a notebook's `key:` or `statuses:`, a ticket's
/// `cycle:`, `estimate:`, `epic:` or `milestone:`, a ticket's `spent:`) and the names of its fences (`gantt`,
/// `board`, `rules`, `form`, and what a `query` says). [span] where the caller has it already. Pure, and cheap for a
/// note with neither: one look for a fence's mark.
Set<String> toolsUsedIn(String body, [FrontMatterSpan? span]) {
  final front = span ?? frontMatterSpan(body);
  final out = <String>{};
  if (!front.isEmpty) {
    String? said(String key) {
      final value = frontMatterValueIn(body, front, key)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    final ticket = isTicketType(said('type'));
    if (ticket) out.add(ticketsTool);
    if (said('book') != null && (said('key') != null || _statuses.hasMatch(body.substring(0, front.closing)))) out.add(ticketsTool);
    if (ticket && _planningKeys.any((key) => said(key) != null)) out.add(planningTool);
    if (ticket && said('spent') != null) out.add(timeTrackingTool);
  }
  if (!body.contains('```') && !body.contains('~~~')) return out;
  final lines = body.split('\n');
  for (final match in _opening.allMatches(body)) {
    final word = match.group(1)!.toLowerCase();
    switch (word) {
      case 'gantt':
        out.add(ganttTool);
      case 'board':
        out.add(boardsTool);
      case 'rules':
        out.add(automationsTool);
      case 'form':
        out.add(formsTool);
      case 'query':
        // The query's words, to its closing run.
        final first = '\n'.allMatches(body.substring(0, match.start)).length + 1;
        final fence = lines[first - 1].trimLeft().substring(0, 3);
        final words = <String>[];
        for (var at = first; at < lines.length; at += 1) {
          if (lines[at].trimLeft().startsWith(fence)) break;
          words.add(lines[at]);
        }
        out.addAll(toolsOfQuery(words.join('\n')));
    }
  }
  return out;
}
