/// Ghost in a Google Meet, as the device asks the service (docs/MEET.md, "Routes"): every route in one place, so a
/// change on the service's side is a change here alone. Under the account's API base with the session's bearer, as
/// the mail routes are (lib/mail/mail_in.dart).
///
/// - `GET meet?limit=20` → `{meetings: [Meeting], series: [Series], next}`: every meeting to come, then the first
///   twenty over, the latest first ([MeetPage]); `GET meet?before=<next>` → `{meetings, next}`, the page after
///   (Matt, 2026-10-24: "show recurring meetings in the meetings UI and paginate the meeting history"). A service from
///   before pages reads no query and answers `{meetings}` alone: the list as it always was, with no series and no
///   next ([MeetPage.pages] false).
/// - `POST meet {url, title?}` → `{meeting}`; `DELETE meet/{id}` → `{meeting}`; `DELETE meet/series/{id}` →
///   `{series, meetings}`, a series stopped ([MeetApi.stopSeries]).
/// - `GET meet/takes` → `{takes: [{id, meeting, size, at, wrapped}]}`; `GET meet/takes/{id}` → the sealed take, raw;
///   `DELETE meet/takes/{id}` → 204.
/// - `PUT meet/kinds {meet?, zoom?}` → `{meet, zoom}`: which kinds Ghost is booked into, the plugins' switches
///   (meet_kinds.dart, which sends them). Each meeting and series says its `kind`, kept by the service once its link
///   is blanked, so each plugin's page lists its own ([MeetBooking.kind]).
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
  const MeetBooking({required this.id, this.title, this.url, this.service, required this.startsAt, required this.endsAt, required this.state, this.detail, this.series, String? kind}) : _kind = kind;

  final String id;

  /// The invite's title; null where it had none, or once the service has forgotten it (an hour after it ended).
  final String? title;
  final String? url;

  /// The service the meeting is on, Google Meet or Zoom (the list's `kind`, else read from [url]); null once the
  /// service has forgotten the link and its kind, when the row says no service, and for a kind that is neither
  /// (Discord's calls).
  final MeetService? service;

  final String? _kind;

  /// Which kind of meeting it is, and so which plugin's page lists it (meet_kinds.dart; Matt, 2026-10-26: "each zoom,
  /// Google meets and discord handle their own meetings"): the service's word (`meet`, `zoom`, `discord`), else the
  /// service read from its link, else `meet`, the one kind there was before the service kept them.
  String get kind => _kind ?? service?.name ?? 'meet';
  final int startsAt;
  final int endsAt;
  final MeetState state;

  /// Why, for a meeting Ghost could not join: `signed_out`, `refused`, `not_admitted`, `busy`, `upload`, `missed`; and a
  /// Zoom's own (`captcha`, `sign_in_required`, `no_browser_join`, `passcode_needed`, ...; [meetDetailWords]).
  final String? detail;

  /// The id of the recurring meeting this is an occurrence of ([MeetSeries.id]), as the list says it; null for a
  /// meeting of its own, and in the answers to a skip or a booking, which do not say.
  final String? series;

  static MeetBooking? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    String? text(String key) => raw[key] is String && (raw[key] as String).trim().isNotEmpty ? (raw[key] as String).trim() : null;
    int whole(String key) => raw[key] is num ? (raw[key] as num).toInt() : 0;
    final url = text('url');
    final kind = text('kind');
    return MeetBooking(
      id: raw['id'] as String,
      title: text('title'),
      url: url,
      service: switch (kind) {
        'meet' || 'zoom' => MeetService.of(kind),
        String() => null,
        null => url == null ? null : MeetService.of(null, url: url),
      },
      startsAt: whole('startsAt'),
      endsAt: whole('endsAt'),
      state: MeetState.of(raw['state']),
      detail: text('detail'),
      series: text('series'),
      kind: kind,
    );
  }

  /// This booking as [next] says it now, keeping which series it is of where [next] does not say.
  MeetBooking followedBy(MeetBooking next) => next.series != null || series == null
      ? next
      : MeetBooking(id: next.id, title: next.title, url: next.url, service: next.service, startsAt: next.startsAt, endsAt: next.endsAt, state: next.state, detail: next.detail, series: series, kind: next._kind ?? _kind);
}

/// A recurring meeting Ghost joins every time (server/src/meet.rs `series_json`): its rule in words made on the
/// service ("Every weekday at 9:30", "Monthly on the 2nd Tuesday at 11:00", or "Repeats"), the time of day on its own
/// clock and that clock's zone, the next occurrence, and how it ends.
@immutable
class MeetSeries {
  const MeetSeries({required this.id, this.title, required this.rule, this.zone, this.offset = 0, this.next, this.until, this.count, this.kind = 'meet'});

  /// The series' own id, for "Stop joining" ([MeetApi.stopSeries]).
  final String id;
  final String? title;

  /// The rule in words, the time in it on the series' own clock.
  final String rule;

  /// The invite's name for that clock's zone (`America/New_York`); null for UTC.
  final String? zone;

  /// How many minutes the series' clock is ahead of UTC at the next occurrence: beside this device's own then, it
  /// says whether the zone needs naming ([meetSeriesRule]).
  final int offset;

  /// The next occurrence not yet over; null where the service said none.
  final MeetSeriesNext? next;

  /// The rule's last day (UNTIL, ms), or how many meetings it makes (COUNT), where it ends.
  final int? until;
  final int? count;

  /// Its kind ([MeetBooking.kind]): which plugin's page lists it.
  final String kind;

  static MeetSeries? fromJson(Object? raw) {
    if (raw is! Map || raw['id'] is! String) return null;
    String? text(String key) => raw[key] is String && (raw[key] as String).trim().isNotEmpty ? (raw[key] as String).trim() : null;
    int? whole(String key) => raw[key] is num ? (raw[key] as num).toInt() : null;
    return MeetSeries(
      id: raw['id'] as String,
      title: text('title'),
      rule: text('rule') ?? 'Repeats',
      zone: text('zone'),
      offset: whole('offset') ?? 0,
      next: MeetSeriesNext.fromJson(raw['next']),
      until: whole('until'),
      count: whole('count'),
      kind: text('kind') ?? 'meet',
    );
  }
}

/// A series' next occurrence: the booking's id (null while the series waits for room), when, and whether Ghost will
/// join it (false once it is skipped or called off).
@immutable
class MeetSeriesNext {
  const MeetSeriesNext({this.id, required this.startsAt, required this.endsAt, required this.state, required this.joins});
  final String? id;
  final int startsAt;
  final int endsAt;
  final MeetState state;
  final bool joins;

  static MeetSeriesNext? fromJson(Object? raw) {
    if (raw is! Map || raw['startsAt'] is! num) return null;
    return MeetSeriesNext(
      id: raw['id'] is String ? raw['id'] as String : null,
      startsAt: (raw['startsAt'] as num).toInt(),
      endsAt: raw['endsAt'] is num ? (raw['endsAt'] as num).toInt() : (raw['startsAt'] as num).toInt(),
      state: MeetState.of(raw['state']),
      joins: raw['joins'] == true,
    );
  }
}

/// One answer of the meetings' list: its meetings; the series, on the first page of a service that lists them (null
/// from one before series); and the cursor for the page after, null on the last. [pages] says whether the service
/// pages at all: one from before answers its one list, and there is nothing after it.
@immutable
class MeetPage {
  const MeetPage({required this.meetings, this.series, this.next, this.pages = false});
  final List<MeetBooking> meetings;
  final List<MeetSeries>? series;
  final String? next;
  final bool pages;
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

  /// How many meetings over a page holds.
  static const int pageSize = 20;

  /// The account's meetings as the list's first page has them (every one to come, soonest first, then the first
  /// [pageSize] over), or the page after [before]; null from a service with no meeting routes.
  Future<MeetPage?> page(String token, {String? before, int limit = pageSize}) async {
    final Map<String, Object?> said;
    try {
      said = await api.callMap('GET', 'meet?limit=$limit${before == null ? '' : '&before=${Uri.encodeQueryComponent(before)}'}', token: token);
    } catch (failure) {
      if (meetNoRoute(failure)) return null;
      rethrow;
    }
    final list = said['meetings'];
    final series = said['series'];
    return MeetPage(
      meetings: [if (list is List) for (final raw in list) ?MeetBooking.fromJson(raw)],
      series: series is List ? [for (final raw in series) ?MeetSeries.fromJson(raw)] : null,
      next: said['next'] is String && (said['next'] as String).isNotEmpty ? said['next'] as String : null,
      pages: said.containsKey('next'),
    );
  }

  /// The account's meetings, the first page's; null from a service with no meeting routes.
  Future<List<MeetBooking>?> meetings(String token) async => (await page(token))?.meetings;

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

  /// Ghost stops joining the series [id]: what is to come called off, the one Ghost is in left, the past kept.
  /// Answers the occurrences that changed.
  Future<List<MeetBooking>> stopSeries(String token, String id) async {
    final said = await api.callMap('DELETE', 'meet/series/${Uri.encodeComponent(id)}', token: token);
    final list = said['meetings'];
    return [if (list is List) for (final raw in list) ?MeetBooking.fromJson(raw)];
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
