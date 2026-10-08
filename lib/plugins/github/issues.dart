/// Issues on a linked repo: a note's list items sent to GitHub, and what comes back about them. A port of
/// `src/app/plugins/github/issues.ts`.
///
/// Matt: "a GitHub issues plugin that allows us to sync list items with GitHub project issues". A list item sent
/// becomes an issue, and its words become a link to that issue, the same shape the Notion plugin writes
/// (`- [ ] Ship the page [github](https://github.com/o/r/issues/12)`). From then on the item and the issue are the
/// same thing: the item's box ticked in the note closes the issue, and an issue closed on GitHub ticks the box.
///
/// Reading is the REST API. Writing needs a token, kept on this phone only (the repos side already asks for one for
/// private repos): without it the note says so rather than failing quietly. Everything here is the plugin's own
/// network permission, through its host.
///
/// What differs: the request goes through `host.fetch`, held to `api.github.com`; an [Issue] is a class; a failure
/// is a [GithubFailure] carrying the sentence the page threw as an `Error`.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../account/api.dart' show FetchRequest, FetchResponse;
import '../types.dart';
import 'manifest.dart';
import 'repos.dart' show githubToken;

const String _api = 'https://api.github.com';

/// An issue as the plugin reads it (`Issue`).
@immutable
class Issue {
  const Issue({
    required this.owner,
    required this.repo,
    required this.number,
    required this.title,
    required this.url,
    required this.open,
    this.reason,
    this.labels = const [],
    this.assignees = const [],
    this.milestone,
    this.updatedAt,
  });

  final String owner;
  final String repo;
  final int number;
  final String title;
  final String url;

  /// `state === 'open'`; closed otherwise.
  final bool open;

  /// "completed" or "not_planned" on a closed issue, where GitHub says.
  final String? reason;
  final List<String> labels;
  final List<String> assignees;
  final String? milestone;

  /// When it last changed, in milliseconds.
  final int? updatedAt;

  /// 'open' | 'closed', as the page names it.
  String get state => open ? 'open' : 'closed';
}

final RegExp _githubHost = RegExp(r'(^|\.)github\.com$', caseSensitive: false);
final RegExp _issuePath = RegExp(r'^\/([A-Za-z0-9_.-]+)\/([A-Za-z0-9_.-]+)\/issues\/(\d+)');

/// The repo and number in an issue's address: "https://github.com/owner/repo/issues/12" (`issueAt`).
({String owner, String repo, int number})? issueAt(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || !parsed.hasScheme || !_githubHost.hasMatch(parsed.host)) return null;
  final match = _issuePath.firstMatch(parsed.path);
  if (match == null) return null;
  final number = int.tryParse(match[3]!);
  return number == null ? null : (owner: match[1]!, repo: match[2]!, number: number);
}

/// Whether a link is an issue on GitHub, so its details are read even when it was pasted rather than sent
/// (`isIssueUrl`).
bool isIssueUrl(String url) => issueAt(url) != null;

/// What GitHub answered, as an issue (`asIssue`).
Issue asIssue(Map<String, Object?> raw, String owner, String repo) {
  final number = raw['number'] is num ? (raw['number'] as num).toInt() : 0;
  final title = raw['title'] is String ? (raw['title'] as String).trim() : '';
  final milestone = raw['milestone'];
  final updated = raw['updated_at'];
  return Issue(
    owner: owner,
    repo: repo,
    number: number,
    title: title.isEmpty ? 'Issue #$number' : title,
    url: raw['html_url'] is String ? raw['html_url'] as String : 'https://github.com/$owner/$repo/issues/$number',
    open: raw['state'] != 'closed',
    reason: raw['state_reason'] is String ? raw['state_reason'] as String : null,
    labels: [
      for (final label in raw['labels'] as List? ?? const [])
        if (label is String && label.isNotEmpty) label else if (label is Map && label['name'] is String && (label['name'] as String).isNotEmpty) label['name'] as String,
    ],
    assignees: [
      for (final who in raw['assignees'] as List? ?? const [])
        if (who is Map && who['login'] is String && (who['login'] as String).isNotEmpty) who['login'] as String,
    ],
    milestone: milestone is Map && milestone['title'] is String ? milestone['title'] as String : null,
    updatedAt: updated is String && updated.isNotEmpty ? DateTime.tryParse(updated)?.millisecondsSinceEpoch : null,
  );
}

/// Whether the phone can make and close issues: reading needs nothing, writing needs a token (`canWriteIssues`).
bool canWriteIssues() => githubToken().trim().isNotEmpty;

/// `NEEDS_TOKEN`.
const String needsToken = 'Add a GitHub token in Settings > Plugins > GitHub to send items as issues.';

Future<Map<String, Object?>> _call(String method, String path, [Map<String, Object?>? body]) async {
  host.need(Permission.network);
  final token = githubToken().trim();
  final answer = await host.fetch(
    FetchRequest(
      method: method,
      url: Uri.parse('$_api$path'),
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        if (body != null) 'Content-Type': 'application/json',
      },
      body: body == null ? null : Uint8List.fromList(utf8.encode(jsonEncode(body))),
    ),
  );
  if (!answer.ok) throw GithubFailure(_trouble(answer, method));
  return (jsonDecode(answer.text) as Map).cast<String, Object?>();
}

final RegExp _rateLimit = RegExp('rate limit', caseSensitive: false);

/// GitHub's own words for what went wrong, said the way a person can act on (`trouble`).
String _trouble(FetchResponse answer, String method) {
  var said = '';
  try {
    final Object? body = jsonDecode(answer.text);
    if (body is Map && body['message'] is String) said = body['message'] as String;
  } catch (_) {
    // Not JSON: GitHub said nothing this can read.
  }
  if (answer.status == 401) return 'GitHub didn’t accept that token. Check it in Settings > Plugins > GitHub.';
  if (answer.status == 403 && _rateLimit.hasMatch(said)) return 'GitHub is rate limiting this phone. Try again in a few minutes.';
  if (answer.status == 403 || answer.status == 404) {
    return method == 'GET' ? 'That issue isn’t readable with this token.' : 'That repo doesn’t allow this token to write issues.';
  }
  if (answer.status == 410) return 'Issues are switched off for that repo.';
  return said.isNotEmpty ? 'GitHub: $said' : 'GitHub answered ${answer.status}.';
}

/// Makes an issue on [owner]/[repo] with [title], and answers it (`createIssue`).
Future<Issue> createIssue({required String owner, required String repo, required String title, String? body}) async {
  if (!canWriteIssues()) throw const GithubFailure(needsToken);
  final raw = await _call('POST', '/repos/$owner/$repo/issues', {
    'title': title.length <= 250 ? title : title.substring(0, 250),
    if (body != null && body.isNotEmpty) 'body': body,
  });
  return asIssue(raw, owner, repo);
}

/// Reads one issue (`readIssue`).
Future<Issue> readIssue(String url) async {
  final at = issueAt(url);
  if (at == null) throw const GithubFailure('That isn’t a GitHub issue.');
  final raw = await _call('GET', '/repos/${at.owner}/${at.repo}/issues/${at.number}');
  return asIssue(raw, at.owner, at.repo);
}

/// Closes an issue as done, or opens it again (`setIssueOpen`).
Future<Issue> setIssueOpen(String url, {required bool open}) async {
  final at = issueAt(url);
  if (at == null) throw const GithubFailure('That isn’t a GitHub issue.');
  if (!canWriteIssues()) throw const GithubFailure(needsToken);
  final raw = await _call('PATCH', '/repos/${at.owner}/${at.repo}/issues/${at.number}', {
    'state': open ? 'open' : 'closed',
    if (!open) 'state_reason': 'completed',
  });
  return asIssue(raw, at.owner, at.repo);
}

/// The short facts for an issue's pill, most telling first: who it's on, its labels, its milestone (`issueBrief`).
List<String> issueBrief(Issue issue) => [
      if (issue.assignees.isNotEmpty) '@${issue.assignees.first}',
      if (issue.labels.isNotEmpty) issue.labels.first,
      if (issue.milestone != null && issue.milestone!.isNotEmpty) issue.milestone!,
    ].take(2).toList();

/// Everything worth listing on an issue's card (`issueFields`).
List<MarkField> issueFields(Issue issue) => [
      MarkField('Repo', '${issue.owner}/${issue.repo}'),
      MarkField('Number', '#${issue.number}'),
      MarkField('State', issueState(issue)),
      if (issue.assignees.isNotEmpty) MarkField(issue.assignees.length == 1 ? 'Assignee' : 'Assignees', issue.assignees.map((who) => '@$who').join(', ')),
      if (issue.labels.isNotEmpty) MarkField(issue.labels.length == 1 ? 'Label' : 'Labels', issue.labels.join(', ')),
      if (issue.milestone != null && issue.milestone!.isNotEmpty) MarkField('Milestone', issue.milestone!),
    ];

/// The word for where an issue is: "Open", "Closed", "Closed as not planned" (`issueState`).
String issueState(Issue issue) {
  if (issue.open) return 'Open';
  return issue.reason == 'not_planned' ? 'Closed as not planned' : 'Closed';
}
