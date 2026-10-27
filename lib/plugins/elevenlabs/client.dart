/// ElevenLabs' API as the plugin asks it, at `api.elevenlabs.io`, with the person's own key in an `xi-api-key` header
/// (Matt, 2026-10-27: "allow creating voice overs of notes using elevenlabs with several voices to choose from").
/// What it was written against is ElevenLabs' own reference as read on 2026-10-27 (elevenlabs.io/docs: models,
/// text-to-speech/convert, user/get, errors), and tauri/scripts/voice-tests/make_audio.py, which already talked to it.
///
/// - **Three calls.** `GET /v1/user` says whose key it is and how many characters are used of the month's
///   ([ElevenAccount]), which is also the cheap call that checks a key before it is kept. `GET /v1/voices` lists the
///   person's voices. `POST /v1/text-to-speech/{voice_id}?output_format=mp3_44100_128` reads words aloud and answers
///   an MP3, which both of the app's players play (Android's MediaPlayer, the Mac's AVAudioPlayer).
/// - **Failures are sentences.** ElevenLabs answers an error as `{"detail": {"code", "message", …}}`, or in its older
///   shape `{"detail": {"status", "message"}}`, and a 422 as a list; [ElevenFailure] reads all three. The ones a person
///   can act on get this app's own words: a key refused (`invalid_api_key`, 401), credits run out
///   (`insufficient_credits` 402, or the older `quota_exceeded`), words past a model's limit (`text_too_long`,
///   `max_character_limit_exceeded`), a voice that is not the key's to use (`voice_not_found`), and a model the key
///   may not use (`model_access_denied`, `unsupported_model`), which the voice-over answers by reading with
///   Multilingual v2 instead (voice_over.dart).
/// - **Busy is waited out.** A 429 (`rate_limit_exceeded`, `concurrent_limit_exceeded`, `system_busy`) is asked
///   again after `Retry-After`, or a few seconds, twice; a 5xx once.
/// - **ElevenLabs bills by the character**, so nothing here is asked twice that could be charged twice: a read that
///   timed out is not asked again, it is said.
///
/// The wait is a seam ([ElevenLabsClient.sleep]), so a test runs the retries in no time.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../account/api.dart' show FetchRequest, FetchResponse;
import '../types.dart';
import 'manifest.dart' as eleven;

/// Where the API is.
const String elevenBase = 'https://api.elevenlabs.io';

/// What a voice-over is made as: MP3 at 44.1 kHz, 128 kb/s, ElevenLabs' default and on every plan.
const String elevenOutput = 'mp3_44100_128';

/// How long one read may take: a chunk of a few thousand characters is read in well under a minute, but a busy
/// ElevenLabs is slower.
const Duration elevenSpeakTimeout = Duration(minutes: 3);

/// What is said when ElevenLabs could not be reached, or did not answer in time.
const String elevenUnreachable = 'ElevenLabs couldn’t be reached. Check the connection and try again.';
const String elevenNoAnswer = 'ElevenLabs took too long to answer. Try again in a moment.';

/// What ElevenLabs refused, or what went wrong asking it, in a sentence a person can act on.
class ElevenFailure implements Exception {
  const ElevenFailure(this.message, {this.status, this.code});
  final String message;

  /// The HTTP status, where the failure was one.
  final int? status;

  /// ElevenLabs' own code (`invalid_api_key`, `insufficient_credits`), or its older `status` where it said that.
  final String? code;

  /// The key itself was refused: not one ElevenLabs knows. A key that only lacks a permission (`missing_permissions`)
  /// is still a key, and so is one whose credits are spent (the older `quota_exceeded` came as a 401).
  bool get badKey => status == 401 && !missingPermission && !spent;

  /// The key is good but may not do this: ElevenLabs' restricted keys name what they may.
  /// Said by its code, or, where ElevenLabs words it otherwise, by a 401 whose message names a permission.
  bool get missingPermission => code == 'missing_permissions' || (status == 401 && message.toLowerCase().contains('permission'));

  /// The month's characters, or the account's credits, are spent.
  bool get spent => status == 402 || code == 'quota_exceeded' || code == 'insufficient_credits';

  /// Too many words for one read.
  bool get tooLong => code == 'text_too_long' || code == 'max_character_limit_exceeded';

  /// The model is not one this key may read with.
  bool get modelRefused => code == 'model_access_denied' || code == 'unsupported_model' || code == 'model_not_found';

  /// The voice is not one this key may read with.
  bool get voiceRefused => code == 'voice_not_found' || code == 'invalid_voice_id' || status == 404;

  /// ElevenLabs is asking for less: worth asking again after a wait.
  bool get busy => status == 429 || code == 'system_busy' || code == 'concurrent_limit_exceeded' || code == 'rate_limit_exceeded';

  @override
  String toString() => message;
}

/// Whose key it is: their plan, and the month's characters used and allowed, where ElevenLabs says.
class ElevenAccount {
  const ElevenAccount({this.tier, this.used, this.limit, this.resets});
  final String? tier;
  final int? used;
  final int? limit;

  /// When the month's characters begin again.
  final DateTime? resets;

  /// What is left of the month's, where both are known.
  int? get left => used == null || limit == null ? null : (limit! - used!).clamp(0, limit!);
}

/// One of the person's own voices, as ElevenLabs lists it.
class ElevenVoice {
  const ElevenVoice({required this.id, required this.name, this.line = '', this.category});
  final String id;
  final String name;

  /// A few words on it: its description, or its labels ("British, calm, narration").
  final String line;

  /// `premade`, `cloned`, `generated`, `professional`, …
  final String? category;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'line': line, 'category': ?category};

  static ElevenVoice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], name = raw['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final line = raw['line'], category = raw['category'];
    return ElevenVoice(id: id, name: name, line: line is String ? line : '', category: category is String ? category : null);
  }
}

/// The key the plugin holds now, or null where none is (read [eleven.host]'s secrets warm).
String? elevenKey([PluginHost? via]) {
  final key = (via ?? eleven.host).secrets.held(eleven.apiKeySecret)?.trim() ?? '';
  return key.isEmpty ? null : key;
}

/// Whether a key is kept.
bool hasElevenKey([PluginHost? via]) => elevenKey(via) != null;

/// Whether [bytes] read as an MP3: an ID3 tag, or an MPEG audio frame's sync.
bool looksLikeMp3(Uint8List bytes) {
  if (bytes.length < 4) return false;
  if (bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) return true;
  return bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
}

/// The person's ElevenLabs, with their key.
class ElevenLabsClient {
  ElevenLabsClient({required this.apiKey, PluginHost? via, Future<void> Function(Duration wait)? sleep})
      : _host = via,
        sleep = sleep ?? _wait;

  /// The client with the kept key, or null where there is none.
  static ElevenLabsClient? kept({PluginHost? via, Future<void> Function(Duration wait)? sleep}) {
    final key = elevenKey(via);
    return key == null ? null : ElevenLabsClient(apiKey: key, via: via, sleep: sleep);
  }

  final String apiKey;
  final PluginHost? _host;
  final Future<void> Function(Duration wait) sleep;

  PluginHost get _on => _host ?? eleven.host;

  static Future<void> _wait(Duration wait) => Future<void>.delayed(wait);

  /// One call, asked again where ElevenLabs is busy, and answered as it came: an error is thrown as an
  /// [ElevenFailure].
  Future<FetchResponse> _call(String method, String path, {Map<String, String>? query, Object? json, Duration timeout = const Duration(seconds: 30), String accept = 'application/json'}) async {
    _on.need(Permission.network);
    final url = Uri.parse('$elevenBase$path').replace(queryParameters: query);
    final body = json == null ? null : Uint8List.fromList(utf8.encode(jsonEncode(json)));
    final headers = {'xi-api-key': apiKey, 'Accept': accept, if (json != null) 'Content-Type': 'application/json'};
    for (var attempt = 0;; attempt += 1) {
      FetchResponse answer;
      try {
        answer = await _on.fetch(FetchRequest(method: method, url: url, headers: headers, body: body, timeout: timeout));
      } on TimeoutException {
        // Never asked again: a read that took too long may still have been made, and billed.
        throw const ElevenFailure(elevenNoAnswer);
      } on ElevenFailure {
        rethrow;
      } catch (failure) {
        if (failure is Error) rethrow;
        throw const ElevenFailure(elevenUnreachable);
      }
      if (answer.ok) return answer;
      final failure = elevenTrouble(answer);
      final again = (failure.busy && attempt < 2) || (answer.status >= 500 && attempt < 1);
      if (!again) throw failure;
      await sleep(_retryAfter(answer) ?? Duration(seconds: 2 * (attempt + 1)));
    }
  }

  /// `Retry-After` in seconds, at most a minute.
  static Duration? _retryAfter(FetchResponse answer) {
    final seconds = int.tryParse(answer.headers['retry-after']?.trim() ?? '');
    return seconds == null ? null : Duration(seconds: seconds.clamp(1, 60));
  }

  Future<Map<String, Object?>> _json(String method, String path, {Map<String, String>? query, Object? json}) async {
    final answer = await _call(method, path, query: query, json: json);
    try {
      final decoded = jsonDecode(answer.text);
      return decoded is Map ? decoded.cast<String, Object?>() : const {};
    } catch (_) {
      throw ElevenFailure('ElevenLabs answered something this app can’t read.', status: answer.status);
    }
  }

  /// The key's account: `GET /v1/user`, which changes nothing and spends nothing.
  Future<ElevenAccount> account() async {
    final user = await _json('GET', '/v1/user');
    final sub = user['subscription'];
    if (sub is! Map) return const ElevenAccount();
    int? whole(Object? value) => value is num ? value.toInt() : null;
    final resets = whole(sub['next_character_count_reset_unix']);
    return ElevenAccount(
      tier: sub['tier'] is String ? sub['tier'] as String : null,
      used: whole(sub['character_count']),
      limit: whole(sub['character_limit']),
      resets: resets == null ? null : DateTime.fromMillisecondsSinceEpoch(resets * 1000, isUtc: true),
    );
  }

  /// Whether the key works: null when it does, the failure when not. A key that may not read the account
  /// (`missing_permissions`) still works for reading aloud, and is answered as that failure for the page to say.
  Future<ElevenFailure?> check() async {
    try {
      await account();
      return null;
    } on ElevenFailure catch (failure) {
      return failure;
    }
  }

  /// The person's voices, the ones ElevenLabs ships first left out (voices.dart offers its own choice of those):
  /// cloned, designed, and the ones saved from the library.
  Future<List<ElevenVoice>> voices() async {
    final listed = await _json('GET', '/v1/voices');
    final all = listed['voices'];
    if (all is! List) return const [];
    final found = <ElevenVoice>[];
    for (final voice in all) {
      if (voice is! Map) continue;
      final id = voice['voice_id'], name = voice['name'];
      if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) continue;
      final category = voice['category'] is String ? voice['category'] as String : null;
      if (category == 'premade') continue;
      found.add(ElevenVoice(id: id, name: name.trim(), line: voiceLine(voice), category: category));
    }
    return found;
  }

  /// [text] read aloud by [voiceId] with [modelId]: the MP3's bytes. Throws an [ElevenFailure].
  Future<Uint8List> speak(String text, {required String voiceId, required String modelId}) async {
    if (!RegExp(r'^[A-Za-z0-9]{1,64}$').hasMatch(voiceId)) throw const ElevenFailure('That isn’t a voice ElevenLabs knows.');
    final answer = await _call(
      'POST',
      '/v1/text-to-speech/$voiceId',
      query: const {'output_format': elevenOutput},
      json: {
        'text': text,
        'model_id': modelId,
        // Eleven v4 reads only these two of the voice's settings (its page: "Style and Speed sliders are not available
        // in Eleven v4"); the older models take them too.
        'voice_settings': {'stability': 0.5, 'similarity_boost': 0.75},
      },
      timeout: elevenSpeakTimeout,
      accept: 'audio/mpeg',
    );
    if (!looksLikeMp3(answer.bytes)) throw ElevenFailure('ElevenLabs answered something that isn’t a sound this app plays.', status: answer.status);
    return answer.bytes;
  }
}

/// A listed voice's few words: its description, else its labels (accent, age, use) joined.
String voiceLine(Map<Object?, Object?> voice) {
  final description = voice['description'];
  if (description is String && description.trim().isNotEmpty) return description.trim();
  final labels = voice['labels'];
  if (labels is Map) {
    final words = [for (final value in labels.values) if (value is String && value.trim().isNotEmpty) value.trim()];
    if (words.isNotEmpty) return words.join(', ');
  }
  return '';
}

/// What ElevenLabs' error answer means, as the person should hear it.
ElevenFailure elevenTrouble(FetchResponse answer) {
  final status = answer.status;
  String? code;
  var said = '';
  try {
    final Object? body = jsonDecode(answer.text);
    final detail = body is Map ? body['detail'] : null;
    if (detail is Map) {
      final named = detail['code'] ?? detail['status'];
      if (named is String && named.isNotEmpty) code = named;
      final message = detail['message'];
      if (message is String) said = message.trim();
    } else if (detail is String) {
      said = detail.trim();
    } else if (detail is List && detail.isNotEmpty && detail.first is Map) {
      final message = (detail.first as Map)['msg'];
      if (message is String) said = message.trim();
    }
  } catch (_) {
    // Not JSON: ElevenLabs said nothing this can read.
  }
  final failure = ElevenFailure(said, status: status, code: code);
  String words;
  if (failure.badKey) {
    words = 'ElevenLabs didn’t accept this key. Copy it again from your ElevenLabs profile, under API Keys.';
  } else if (failure.missingPermission) {
    words = 'This ElevenLabs key isn’t allowed to do that. Give it Text to Speech and Voices (read) in ElevenLabs, or make one that has them.';
  } else if (failure.spent) {
    words = 'Your ElevenLabs credits are used up for now. More come with your plan’s next month, or with a bigger plan.';
  } else if (failure.tooLong) {
    words = 'That was more than ElevenLabs reads at once.';
  } else if (failure.voiceRefused) {
    words = 'ElevenLabs doesn’t have that voice for this key. Pick another in Settings › ElevenLabs.';
  } else if (failure.modelRefused) {
    words = 'This ElevenLabs key can’t use that model.';
  } else if (failure.busy) {
    words = 'ElevenLabs is busy with other reads for this key. Try again in a minute.';
  } else if (said.isNotEmpty) {
    words = 'ElevenLabs said: $said';
  } else {
    words = 'ElevenLabs answered $status.';
  }
  // Kept by its code, whatever words ElevenLabs used for it.
  return ElevenFailure(words, status: status, code: failure.missingPermission ? 'missing_permissions' : code);
}

/// The client the voice-over and the page ask: the one with the kept key, unless a test gives its own.
ElevenLabsClient? Function() elevenLabsClient = () => ElevenLabsClient.kept();
