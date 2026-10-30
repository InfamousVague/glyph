/// Forms from a share link as glyph-api keeps them (server/src/forms.rs, docs/FORMS.md), for the fake service
/// (test/support/fake_service.dart, which hands its signed-in `forms/…` requests here): which shares are forms, and the
/// answers waiting, sealed, with the claim that keeps each to one device and the ack that files it once.
///
/// What a visitor's browser sends is played by [FakeForms.answer], which seals as tauri/src/read/form.ts seals, with
/// the crypto it is handed (the fake one, as every device under test has). What it does NOT do: the public routes'
/// rate limits, the hidden field and the ticket, which are the service's own tests' (server/src/forms_tests.rs).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/forms/form_inbox.dart' show formSealContext, formWrapContext;

/// A form as the service keeps it.
class FakeForm {
  FakeForm({required this.id, this.org, this.note, this.state = 'open', this.files = false});
  final String id;
  String? org;
  String? note;
  String state;
  bool files;
  int received = 0;
  int filed = 0;
}

/// An answer waiting, sealed, and who holds a claim on it until when (ms).
class FakeAnswer {
  FakeAnswer({required this.id, required this.form, required this.wraps, required this.blob, required this.at});
  final String id;
  final String form;
  final List<Map<String, String>> wraps;
  final String blob;
  final int at;
  String? claimedBy;
  int claimedUntil = 0;
}

class FakeForms {
  final Map<String, FakeForm> forms = {};
  final List<FakeAnswer> inbox = [];

  /// How long a claim holds, in ms (server/src/forms.rs `CLAIM_FOR`).
  int claimFor = 120000;

  /// Every claim made, as `<answer> by <device>`, and every ack: what a test asserts.
  final List<String> claims = [];
  final List<String> acks = [];

  /// Plays the service from before forms: every route answers `no such route`.
  bool routes = true;

  void clear() {
    forms.clear();
    inbox.clear();
    claims.clear();
    acks.clear();
  }

  /// An answer to [form], sealed as the visitor's browser seals one: [payload] under a fresh key, that key wrapped to
  /// each of [keys], in the form's and the answer's contexts.
  Future<void> answer(AccountCrypto crypto, {required String form, required String id, required List<String> keys, required Map<String, Object?> payload, required int at}) async {
    final raw = crypto.randomBytes(32);
    final key = await crypto.importSealKey(raw);
    final blob = toBase64Url(await crypto.sealBytes(key, Uint8List.fromList(utf8.encode(jsonEncode(payload))), formSealContext(form, id)));
    final wraps = [
      for (final to in keys) {'to': to, 'wrap': await crypto.wrapFor(to, raw, formWrapContext(form, id))},
    ];
    inbox.add(FakeAnswer(id: id, form: form, wraps: wraps, blob: blob, at: at));
    forms[form]?.received += 1;
  }

  /// A signed-in request to `forms…`, answered; null for any other path. [shared] says whether a share of the
  /// account's has that id, [keyed] whether the account has registered its encryption key.
  FetchResponse? route(String method, String path, Map<String, Object?> body, Map<String, String> query, {required int now, required bool Function(String id) shared, required bool keyed}) {
    if (path != 'forms' && !path.startsWith('forms/')) return null;
    if (!routes) return FetchResponse.json(404, {'error': noSuchRoute});
    Map<String, Object?> json(FakeForm f) => {'id': f.id, 'org': f.org, 'note': f.note, 'state': f.state, 'files': f.files, 'received': f.received, 'waiting': inbox.where((a) => a.form == f.id).length, 'filed': f.filed, 'mine': true};
    if (path == 'forms' && method == 'GET') return FetchResponse.json(200, {'forms': [for (final f in forms.values) json(f)]});
    if (path == 'forms/inbox' && method == 'GET') {
      final after = query['after'];
      final from = after == null ? 0 : inbox.indexWhere((a) => a.id == after) + 1;
      return FetchResponse.json(200, [
        for (final a in inbox.skip(from < 0 ? 0 : from).take(100))
          {'id': a.id, 'form': a.form, 'note': forms[a.form]?.note, 'at': a.at, 'wraps': a.wraps, 'blob': a.blob, 'claimed': a.claimedUntil > now},
      ]);
    }
    final claim = RegExp(r'^forms/inbox/([^/]+)/claim$').firstMatch(path);
    if (claim != null && method == 'POST') {
      final id = Uri.decodeComponent(claim[1]!);
      final device = body['device'];
      if (device is! String || device.isEmpty) return FetchResponse.json(400, {'error': 'A claim names the device making it.'});
      final found = inbox.where((a) => a.id == id).firstOrNull;
      if (found == null) return FetchResponse.json(404, {'error': 'That answer is not waiting: it was filed, or it is gone.'});
      if (found.claimedUntil > now && found.claimedBy != device) return FetchResponse.json(409, {'error': 'Another device is filing that answer.'});
      found
        ..claimedBy = device
        ..claimedUntil = now + claimFor;
      claims.add('$id by $device');
      return FetchResponse.json(200, {'id': id, 'until': found.claimedUntil});
    }
    final ack = RegExp(r'^forms/inbox/([^/]+)$').firstMatch(path);
    if (ack != null && method == 'DELETE') {
      final id = Uri.decodeComponent(ack[1]!);
      final found = inbox.where((a) => a.id == id).firstOrNull;
      if (found != null) {
        inbox.remove(found);
        forms[found.form]?.filed += 1;
        acks.add(id);
      }
      return FetchResponse(204);
    }
    final state = RegExp(r'^forms/([^/]+)/state$').firstMatch(path);
    if (state != null && method == 'POST') {
      final f = forms[Uri.decodeComponent(state[1]!)];
      if (f == null) return FetchResponse.json(404, {'error': 'There is no form of yours at that link.'});
      f.state = '${body['state']}';
      return FetchResponse.json(200, json(f));
    }
    final answers = RegExp(r'^forms/([^/]+)/answers$').firstMatch(path);
    if (answers != null && method == 'DELETE') {
      final id = Uri.decodeComponent(answers[1]!);
      final before = inbox.length;
      inbox.removeWhere((a) => a.form == id);
      return FetchResponse.json(200, {'deleted': before - inbox.length});
    }
    final one = RegExp(r'^forms/([^/]+)$').firstMatch(path);
    if (one != null && method == 'PUT') {
      final id = Uri.decodeComponent(one[1]!);
      if (!shared(id)) return FetchResponse.json(404, {'error': 'There is no share of yours at that link. Share the form first.'});
      final org = body['org'] is String && (body['org'] as String).isNotEmpty ? body['org'] as String : null;
      if (org == null && !keyed) return FetchResponse.json(409, {'error': 'This account has no encryption key yet.'});
      final f = forms.putIfAbsent(id, () => FakeForm(id: id));
      f
        ..org = org
        ..note = body['note'] is String ? body['note'] as String : f.note
        ..files = body['files'] == true;
      if (body['state'] is String) f.state = body['state'] as String;
      return FetchResponse.json(200, json(f));
    }
    if (one != null && method == 'DELETE') {
      final id = Uri.decodeComponent(one[1]!);
      forms.remove(id);
      inbox.removeWhere((a) => a.form == id);
      return FetchResponse(204);
    }
    return FetchResponse.json(404, {'error': noSuchRoute});
  }
}
