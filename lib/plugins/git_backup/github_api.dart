/// What the plugin asks GitHub's API, through its host (the one host the manifest names): what a token may do, so
/// the GitHub plugin's token is reused only when it may write to repositories, and "Create the repository for me",
/// a private repository under the person's account.
///
/// A classic token answers `X-OAuth-Scopes` on any call; a fine-grained one (`github_pat_…`) answers no scopes, and
/// whether it may write a repository's contents can only be learnt by trying, so [tokenScopes] says `unknown` for one
/// and the setup takes the person's word, the first push being the check.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../account/api.dart' show FetchRequest;
import '../types.dart' show Permission, PluginHost;
import 'manifest.dart' as git;

/// What a token may do, as GitHub says it.
class TokenScopes {
  const TokenScopes({required this.login, required this.scopes, required this.fineGrained});

  /// Whose the token is.
  final String login;

  /// The classic scopes, or empty for a fine-grained token.
  final Set<String> scopes;
  final bool fineGrained;

  /// Whether it may push: the classic `repo` scope (or `public_repo`, for public repositories alone); a fine-grained
  /// token's cannot be read, so null: unknown.
  bool? get mayPush => fineGrained ? null : (scopes.contains('repo') || scopes.contains('public_repo'));
}

class GitHubRefusal implements Exception {
  const GitHubRefusal(this.message, {this.status});
  final String message;
  final int? status;

  @override
  String toString() => message;
}

class GitHubApi {
  const GitHubApi({PluginHost? via}) : _via = via;
  final PluginHost? _via;
  PluginHost get host => _via ?? git.host;

  Future<Map<String, Object?>> _call(String method, String path, String token, {Object? body}) async {
    host.need(Permission.network);
    final answer = await host.fetch(FetchRequest(
      method: method,
      url: Uri.parse('https://api.github.com$path'),
      headers: {'Accept': 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'Authorization': 'Bearer $token', if (body != null) 'Content-Type': 'application/json'},
      body: body == null ? null : Uint8List.fromList(utf8.encode(jsonEncode(body))),
    ));
    if (!answer.ok) {
      String said;
      try {
        final parsed = jsonDecode(answer.text);
        said = parsed is Map && parsed['message'] is String ? parsed['message'] as String : answer.text;
      } catch (_) {
        said = answer.text;
      }
      throw GitHubRefusal(switch (answer.status) {
        401 => 'GitHub didn’t accept the token.',
        403 => 'GitHub refused: ${said.isEmpty ? 'the token may not do that' : said}',
        404 => 'GitHub found no such repository.',
        422 => 'GitHub refused: ${said.isEmpty ? 'that name is taken or not allowed' : said}',
        _ => 'GitHub answered ${answer.status}: $said',
      }, status: answer.status);
    }
    final parsed = jsonDecode(answer.text);
    final scopes = answer.headers['x-oauth-scopes'];
    return {...(parsed is Map ? parsed.cast<String, Object?>() : const <String, Object?>{}), '__scopes': scopes};
  }

  /// Whose [token] is and what it may do (`GET /user`).
  Future<TokenScopes> tokenScopes(String token) async {
    final user = await _call('GET', '/user', token);
    final raw = user['__scopes'];
    final fineGrained = token.startsWith('github_pat_') || raw == null;
    final scopes = raw is String ? {for (final s in raw.split(',')) if (s.trim().isNotEmpty) s.trim()} : <String>{};
    return TokenScopes(login: user['login'] is String ? user['login'] as String : '', scopes: scopes, fineGrained: fineGrained);
  }

  /// A private repository named [name] under the person's account (`POST /user/repos`); its HTTPS clone address.
  Future<String> createRepository(String token, {required String name, bool private = true, String description = 'My Ghost.md notes'}) async {
    final made = await _call('POST', '/user/repos', token, body: {'name': name, 'private': private, 'description': description, 'auto_init': false, 'has_issues': false, 'has_wiki': false, 'has_projects': false});
    final url = made['clone_url'];
    if (url is String && url.isNotEmpty) return url;
    final full = made['full_name'];
    return 'https://github.com/$full.git';
  }
}

/// What is wrong with a repository name for GitHub, or null.
String? repositoryNameShape(String text) {
  final name = text.trim();
  if (name.isEmpty) return 'Give the repository a name, like notes.';
  if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) return 'GitHub takes letters, numbers, dots, dashes and underscores in a name.';
  if (name.length > 100) return 'That name is too long for GitHub.';
  return null;
}
