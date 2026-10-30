/// A form's standing on the service, for the share sheet's rows (lib/forms/ui/form_rows.dart; docs/FORMS.md): whether
/// it takes answers, how many came, wait and were filed, and the owner's three acts - open, pause or close it, and
/// delete the answers waiting. And saying a shared form is one ([FormAdmin.say]), at once, for a link just made, where
/// the sync pass would say it on its next run (lib/forms/form_inbox.dart `sayForms`).
library;

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/enc_key.dart';
import '../account/ui_state.dart' show AccountServices;

/// Open, paused or closed, as the service words them.
enum FormTaking { open, paused, closed }

/// A form as glyph-api lists it.
@immutable
class FormStanding {
  const FormStanding({required this.id, required this.state, this.org, this.received = 0, this.waiting = 0, this.filed = 0, this.mine = true});
  final String id;
  final FormTaking state;
  final String? org;
  final int received;
  final int waiting;
  final int filed;

  /// Whether it is this account's own; a teammate's form may be paused here, and is deleted by its owner alone.
  final bool mine;

  static FormStanding? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    int count(String key) => raw[key] is num ? (raw[key] as num).toInt() : 0;
    return FormStanding(
      id: raw['id'] as String,
      state: switch (raw['state']) { 'paused' => FormTaking.paused, 'closed' => FormTaking.closed, _ => FormTaking.open },
      org: raw['org'] is String ? raw['org'] as String : null,
      received: count('received'),
      waiting: count('waiting'),
      filed: count('filed'),
      mine: raw['mine'] != false,
    );
  }
}

/// What the line under a form's rows says: how many answers were filed, and how many wait.
String formCounts(FormStanding form) {
  String answers(int n) => n == 1 ? '1 answer' : '$n answers';
  if (form.received == 0) return 'No answers yet.';
  final filed = '${answers(form.filed)} filed as tickets';
  return form.waiting == 0 ? '$filed.' : '$filed, ${form.waiting} waiting for a device to file.';
}

class FormAdmin {
  FormAdmin({required this.api, required String? Function() token, required Future<void> Function() seeToKey})
      : _token = token,
        _seeToKey = seeToKey;

  /// Over the account [services] hold, its encryption key seen to as an incoming hook's is
  /// (lib/integrations/webhooks/incoming.dart `IncomingHooks.of`).
  factory FormAdmin.of(AccountServices services) {
    final account = services.account;
    return FormAdmin(
      api: account.api,
      token: () => account.session?.token,
      seeToKey: () async {
        final token = account.session?.token;
        final accountKey = await account.accountKey();
        if (token == null || accountKey == null) throw const ApiError(409, 'Sign in again on this device first: its key is not here.');
        await ensureEncryptionKey(EncryptionKeyContext(token: token, accountKey: accountKey, keys: account.keys, api: account.api, crypto: account.crypto));
      },
    );
  }

  final Api api;
  final String? Function() _token;
  final Future<void> Function() _seeToKey;

  String _signedIn() {
    final token = _token();
    if (token == null) throw const ApiError(401, 'Sign in under Settings › Account first.');
    return token;
  }

  /// The form shared as [shareId], or null where the service has not heard it is one; and null for a service with no
  /// forms yet.
  Future<FormStanding?> standing(String shareId) async {
    final Object? said;
    try {
      said = await api.call('GET', 'forms', token: _signedIn());
    } catch (failure) {
      if (notYet(failure)) return null;
      rethrow;
    }
    final forms = said is Map ? said['forms'] : null;
    for (final each in forms is List ? forms : const <Object?>[]) {
      final form = FormStanding.fromJson(each);
      if (form != null && form.id == shareId) return form;
    }
    return null;
  }

  /// The share [shareId] said to be a form: defined by [noteId], filed by [org]'s members or the account's own devices,
  /// taking a file or not. Its state stays as it is; a new one is open.
  Future<FormStanding?> say(String shareId, {required String noteId, required String? org, required bool files}) async {
    final token = _signedIn();
    if (org == null) await _seeToKey();
    final said = await api.call('PUT', 'forms/${Uri.encodeComponent(shareId)}', token: token, body: {'org': org, 'note': noteId, 'files': files});
    return FormStanding.fromJson(said);
  }

  /// Open, paused or closed from now on.
  Future<FormStanding?> setState(String shareId, FormTaking state) async {
    final said = await api.call('POST', 'forms/${Uri.encodeComponent(shareId)}/state', token: _signedIn(), body: {'state': state.name});
    return FormStanding.fromJson(said);
  }

  /// Every answer waiting deleted, unfiled. Answers how many.
  Future<int> deleteWaiting(String shareId) async {
    final said = await api.call('DELETE', 'forms/${Uri.encodeComponent(shareId)}/answers', token: _signedIn());
    return said is Map && said['deleted'] is num ? (said['deleted'] as num).toInt() : 0;
  }
}
