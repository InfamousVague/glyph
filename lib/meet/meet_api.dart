/// Ghost in a Google Meet, as the device asks the service (docs/MEET.md, "Routes"): every route in one place, so a
/// change on the service's side is a change here alone. Under the account's API base with the session's bearer, as
/// the mail routes are (lib/mail/mail_in.dart).
///
/// - `GET meet` → `{meetings: [Meeting]}`; `POST meet {url, title?}` → `{meeting}`; `DELETE meet/{id}` → `{meeting}`.
/// - `GET meet/takes` → `{takes: [{id, meeting, size, at, wrapped}]}`; `GET meet/takes/{id}` → the sealed take, raw;
///   `DELETE meet/takes/{id}` → 204.
///
/// A take is sealed as a mail is, with contexts of its own ([takeWrapContext], [takeSealContext]), and opened with
/// what the device already has ([openSealedTake]).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../account/api.dart';
import '../account/crypto_api.dart';
import '../core/bytes.dart';
import 'gmt.dart';

/// The context a take's key is wrapped in (server/src/meet.rs `take_wrap_context`).
String takeWrapContext(String id) => 'meet-take:$id';

/// The context a take is sealed in (`take_seal_context`).
String takeSealContext(String id) => 'meet:$id';

/// Take [id] opened: its key out of [wrapped] with the account's [pair], then the take out of [sealed].
Future<OpenedTake> openSealedTake(AccountCrypto crypto, EncryptionKey pair, {required String id, required String wrapped, required Uint8List sealed}) async {
  final raw = await crypto.unwrapWith(pair, wrapped, takeWrapContext(id));
  final key = await crypto.importSealKey(raw);
  return readTake(await crypto.openBytes(key, sealed, takeSealContext(id)));
}

/// Where a booking stands (`state`), as the service says it.
enum MeetState {
  booked,
  joining,
  inCall,
  leave,
  done,
  failed,
  skipped,
  cancelled,
  other;

  static MeetState of(Object? word) => switch (word) {
        'booked' => booked,
        'joining' => joining,
        'in_call' => inCall,
        'leave' => leave,
        'done' => done,
        'failed' => failed,
        'skipped' => skipped,
        'cancelled' => cancelled,
        _ => other,
      };

  /// Still to come or going on: Ghost can be told not to join, or to leave.
  bool get open => this == booked || this == joining || this == inCall;
}

/// One meeting Ghost is booked for, or was.
@immutable
class MeetBooking {
  const MeetBooking({required this.id, this.title, this.url, required this.startsAt, required this.endsAt, required this.state, this.detail});

  final String id;

  /// The invite's title; null where it had none, or once the service has forgotten it (an hour after it ended).
  final String? title;
  final String? url;
  final int startsAt;
  final int endsAt;
  final MeetState state;

  /// Why, for a meeting Ghost could not join: `signed_out`, `refused`, `not_admitted`, `busy`, `upload`, `missed`.
  final String? detail;

  static MeetBooking? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    String? text(String key) => raw[key] is String && (raw[key] as String).trim().isNotEmpty ? (raw[key] as String).trim() : null;
    int whole(String key) => raw[key] is num ? (raw[key] as num).toInt() : 0;
    return MeetBooking(id: raw['id'] as String, title: text('title'), url: text('url'), startsAt: whole('startsAt'), endsAt: whole('endsAt'), state: MeetState.of(raw['state']), detail: text('detail'));
  }
}

/// A recording waiting on the service for a device to take it.
@immutable
class WaitingTake {
  const WaitingTake({required this.id, required this.meeting, required this.size, required this.at, this.wrapped});
  final String id;
  final String meeting;
  final int size;

  /// When it arrived, in ms.
  final int at;

  /// Its key, wrapped to the account's encryption key.
  final String? wrapped;
}

/// Whether [failure] is a service with no such routes at all (an older one): the meeting routes are then quiet.
bool meetNoRoute(Object failure) => notYet(failure);

/// The meeting routes, over one [Api].
class MeetApi {
  const MeetApi(this.api);
  final Api api;

  /// How long a take may take to come: tens of megabytes on a phone's connection.
  static const Duration takeTimeout = Duration(minutes: 10);

  /// The account's meetings, soonest first; null from a service with no meeting routes.
  Future<List<MeetBooking>?> meetings(String token) async {
    final Map<String, Object?> said;
    try {
      said = await api.callMap('GET', 'meet', token: token);
    } catch (failure) {
      if (meetNoRoute(failure)) return null;
      rethrow;
    }
    final list = said['meetings'];
    return [if (list is List) for (final raw in list) ?MeetBooking.fromJson(raw)];
  }

  /// Ghost joins the Meet at [url] now.
  Future<MeetBooking?> book(String token, String url, {String? title}) async {
    final said = await api.callMap('POST', 'meet', token: token, body: {'url': url, if (title != null && title.trim().isNotEmpty) 'title': title.trim()});
    return MeetBooking.fromJson(said['meeting']);
  }

  /// Ghost does not join meeting [id], or leaves it now.
  Future<MeetBooking?> skip(String token, String id) async {
    final said = await api.callMap('DELETE', 'meet/${Uri.encodeComponent(id)}', token: token);
    return MeetBooking.fromJson(said['meeting']);
  }

  /// The recordings waiting, oldest first; null from a service with no meeting routes.
  Future<List<WaitingTake>?> takes(String token) async {
    final Map<String, Object?> said;
    try {
      said = await api.callMap('GET', 'meet/takes', token: token);
    } catch (failure) {
      if (meetNoRoute(failure)) return null;
      rethrow;
    }
    final list = said['takes'];
    return [
      if (list is List)
        for (final raw in list)
          if (raw is Map && raw['id'] is String)
            WaitingTake(
              id: raw['id'] as String,
              meeting: raw['meeting'] is String ? raw['meeting'] as String : '',
              size: raw['size'] is num ? (raw['size'] as num).toInt() : 0,
              at: raw['at'] is num ? (raw['at'] as num).toInt() : 0,
              wrapped: raw['wrapped'] is String ? raw['wrapped'] as String : null,
            ),
    ];
  }

  /// Take [id]'s sealed bytes and its wrapped key; null once it is not waiting (another device took it). The raw
  /// body is the service's answer; a JSON `{wrapped, blob}` (the blob base64url) is read too.
  Future<({String wrapped, Uint8List sealed})?> take(String token, WaitingTake take) async {
    final Uint8List bytes;
    try {
      bytes = (await api.callBytes('GET', 'meet/takes/${Uri.encodeComponent(take.id)}', token: token, timeout: takeTimeout)).bytes;
    } on ApiError catch (failure) {
      if (failure.status == 404) return null;
      rethrow;
    }
    if (bytes.isNotEmpty && bytes[0] == 0x7b) {
      try {
        final said = jsonDecode(utf8.decode(bytes));
        if (said is Map && said['blob'] is String) {
          final wrapped = said['wrapped'] is String ? said['wrapped'] as String : take.wrapped;
          if (wrapped != null) return (wrapped: wrapped, sealed: fromBase64Url(said['blob'] as String));
        }
      } on FormatException {
        // Sealed bytes that happen to start with a brace: read below.
      }
    }
    final wrapped = take.wrapped;
    if (wrapped == null) throw const ApiError(500, 'The service sent a meeting without its key.');
    return (wrapped: wrapped, sealed: bytes);
  }

  /// Take [id] is filed: the sealed copy goes from the service.
  Future<void> drop(String token, String id) => api.call('DELETE', 'meet/takes/${Uri.encodeComponent(id)}', token: token);
}
