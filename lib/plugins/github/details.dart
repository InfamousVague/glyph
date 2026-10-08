/// A linked item's issue, read back from GitHub: whether it is open, who has it, what it is labelled, for the pill
/// on the item and the card a tap opens (lib/plugins/mark_details.dart). A port of
/// `src/app/plugins/github/details.ts`.
///
/// The stage is the plain thing GitHub says: open is to do, closed is done. That is what makes the tick work both
/// ways: the actions here are called `done` and `reopen`, so ticking the box in the note closes the issue, and an
/// issue closed on GitHub ticks the box the next time the note is read.
///
/// The plugins' shared cache (lib/plugins/details_cache.dart, which has the numbers) paces the reads, keeps an
/// answer fresh long enough that scrolling a list doesn't re-read it, and keeps the last answers under
/// `glyph-github-issues`, so a note opened offline still shows the state its issues last had, with when it was read
/// on the card. Here an issue is kept under [issueKey], and a read is one call for the issue.
///
/// What differs: the provider is a class ([GithubDetails]); [forgetIssues] is for the tests, whose grounds change
/// under the one cache.
library;

import '../details_cache.dart';
import '../types.dart';
import 'issues.dart';
import 'manifest.dart';
import 'repos.dart' show githubNow;

/// The key an issue is kept under: its repo and number (`issueKey`).
String? issueKey(String url) {
  final at = issueAt(url);
  return at == null ? null : '${at.owner}/${at.repo}#${at.number}';
}

/// What the card and the pill show for an issue (`detailsOf`).
MarkDetails detailsOf(Issue issue, [int? readAt]) => MarkDetails(
      url: issue.url,
      title: issue.title,
      status: MarkStatus(issueState(issue), issue.open ? Stage.todo : Stage.done),
      brief: issueBrief(issue),
      fields: issueFields(issue),
      editedAt: issue.updatedAt,
      readAt: readAt ?? githubNow(),
    );

final DetailsCache _issues = DetailsCache(host: host, storageKey: 'glyph-github-issues', read: (key, url) async => detailsOf(await readIssue(url)), now: () => githubNow());

/// Puts an issue into what is known without reading it: what `createIssue` just made (`rememberIssue`).
void rememberIssue(Issue issue) => _issues.keep('${issue.owner}/${issue.repo}#${issue.number}', detailsOf(issue));

/// For the tests: every answer forgotten, kept or not.
void forgetIssues() => _issues.forget();

/// `githubDetails`: what the plugin's marks, and plain links to an issue, read back.
class GithubDetails extends MarkDetailsProvider {
  const GithubDetails();

  @override
  MarkEntry? peek(String url) {
    final key = issueKey(url);
    return key == null ? null : _issues.peek(key);
  }

  @override
  void want(String url, {bool fresh = false}) {
    final key = issueKey(url);
    if (key != null) _issues.want(key, url, fresh: fresh);
  }

  @override
  Future<void> open(String url) => host.openUrl(url);

  // A GitHub issue pasted into a sentence reads the same as one Ghost.md sent.
  @override
  bool reads(String url) => isIssueUrl(url);

  @override
  List<MarkAction> actions(String url, String words) {
    final key = issueKey(url);
    final details = key == null ? null : _issues.details(key);
    if (key == null || details == null || !canWriteIssues()) return const [];
    final closed = details.status?.stage == Stage.done;
    return [
      MarkAction(
        id: closed ? 'reopen' : 'done',
        label: closed ? 'Open again' : 'Close issue',
        icon: closed ? MarkActionIcon.reopen : MarkActionIcon.done,
        busyLabel: closed ? 'Opening…' : 'Closing…',
        run: () async {
          final issue = await setIssueOpen(url, open: closed);
          _issues.keep(key, detailsOf(issue));
          return closed ? '#${issue.number} is open again.' : '#${issue.number} is closed.';
        },
      ),
    ];
  }
}

const GithubDetails githubDetails = GithubDetails();

/// Turns GitHub's answer into what a card shows, without a request: for the tests (`detailsFromRaw`).
MarkDetails detailsFromRaw(Map<String, Object?> raw, String owner, String repo) => detailsOf(asIssue(raw, owner, repo));
