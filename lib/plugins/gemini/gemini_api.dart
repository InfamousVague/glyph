/// Google's Gemini API (generativelanguage.googleapis.com) with the person's own API key (docs/AI_PROVIDERS.md,
/// "Gemini"; Matt, 2026-10-29: "Add support for aster 6 and other Ai models as plugins in addition to claude like openAI
/// google gemini etc"). One request streamed (`POST /v1beta/models/{model}:streamGenerateContent?alt=sse`), with
/// function declarations for the app's tools, and one small read (`GET /v1beta/models`) that lists the models and
/// says whether a key works. The key goes only to Google, in the `x-goog-api-key` header (never in the address, where
/// a log might keep it), from this device: no Ghost.md server between.
///
/// **Translated both ways** (lib/assistant/provider.dart): the run's request, in the Messages API's shape, becomes
/// Gemini's ([geminiBody]): the system prompt its `systemInstruction`; each turn a `content` of `role` `user` or
/// `model` with its `parts`, words a `text` part, a `tool_use` block a `functionCall` part, a `tool_result` block a
/// `functionResponse` part named by the call it answers; Claude's thinking blocks, `thinking` and `output_config`
/// dropped. The tools are one `functionDeclarations` list, their schemas cut to what Gemini's schema knows
/// ([geminiSchema]: types, descriptions, properties, required, items, enums and bounds). Its stream becomes the
/// Messages API's events ([GeminiTranslator]): the first chunk a `message_start` (named by its `modelVersion`); each
/// `text` part a text block's words (a `thought` part a thinking block's); each `functionCall` part a whole `tool_use`
/// block, its `args` as one `input_json_delta`; `finishReason` the stop (`MAX_TOKENS` → `max_tokens`, `SAFETY` and the
/// other blocks → `refusal`, any call made → `tool_use`); `usageMetadata` the counts (the prompt less what was read
/// from its cache as input, that as cache reads, the answer and its thoughts as output).
///
/// **Thought signatures.** A thinking model hands each function call back with a `thoughtSignature`, and refuses the
/// next turn when the call goes back without it. The run keeps a tool call's id, not its parts; so the signature rides
/// in the id ([geminiToolId]) and is put back on the call as the conversation goes out again.
///
/// **The errors** ([geminiErrorOf]): Google answers a wrong key with a 400 that says `API_KEY_INVALID`, read as a
/// refused key; 403 a key whose project may not use the API; 429 `RESOURCE_EXHAUSTED`, the key's quota used (the free
/// tier's is daily) or too many requests; 404 no such model; 5xx Google's trouble; no answer the connection.
library;

import 'dart:convert';
import 'dart:io';

import '../../assistant/http_stream.dart';
import '../../assistant/provider.dart';
import '../../assistant/provider_settings.dart';
import '../openai/chat_api.dart' show noToolsNotice;

/// The API's address.
const String geminiBase = 'https://generativelanguage.googleapis.com/v1beta';

/// The words of a failed answer.
AiError geminiErrorOf(int status, String body) {
  String? message, state, reason;
  try {
    final json = jsonDecode(body);
    final error = json is List && json.isNotEmpty ? (json.first is Map ? (json.first as Map)['error'] : null) : (json is Map ? json['error'] : null);
    if (error is Map) {
      message = error['message']?.toString();
      state = error['status']?.toString();
      final details = error['details'];
      if (details is List) {
        for (final detail in details) {
          if (detail is Map && detail['reason'] is String) reason ??= detail['reason'] as String;
        }
      }
    }
  } catch (_) {
    // Not JSON: the status says it.
  }
  final said = (message ?? '').toLowerCase();
  if (status == 401 || reason == 'API_KEY_INVALID' || said.contains('api key not valid') || said.contains('api_key_invalid')) {
    return AiError('The API key was refused. Check it in Settings › Gemini.', status: status, type: 'authentication_error');
  }
  if (status == 403 || state == 'PERMISSION_DENIED') {
    return AiError('This key may not use the Gemini API. ${message ?? ''}'.trim(), status: status, type: 'permission_error');
  }
  if (status == 429 || state == 'RESOURCE_EXHAUSTED') {
    final quota = said.contains('quota');
    return AiError(
      quota ? 'This key has used its quota for now: the free tier’s is daily. Try again later, or turn on billing for its Google Cloud project.' : 'Too many requests for this key just now. Try again in a moment.',
      status: status,
      type: 'rate_limit_error',
    );
  }
  if (status == 404) return AiError(message ?? 'Gemini has no such model. Check the model in Settings › Gemini.', status: status, type: 'not_found_error');
  if (status >= 500) return AiError('Gemini is having trouble just now. Try again in a moment.', status: status, type: status == 503 ? 'overloaded_error' : 'api_error');
  return AiError(message ?? 'Gemini answered $status.', status: status, type: status == 400 ? 'invalid_request_error' : null);
}

/// A tool call's id, carrying its thought signature where it had one (see the header).
String geminiToolId(int n, String? signature) => signature == null || signature.isEmpty ? 'gemini_$n' : 'gemini_$n~$signature';

/// The thought signature a tool call's id carries, or null.
String? geminiSignatureOf(Object? id) {
  if (id is! String) return null;
  final at = id.indexOf('~');
  return at < 0 ? null : id.substring(at + 1);
}

/// The keys of a JSON schema Gemini's own schema knows; the rest are left out.
const Set<String> _schemaKeys = {'type', 'format', 'description', 'nullable', 'enum', 'items', 'properties', 'required', 'minimum', 'maximum', 'minItems', 'maxItems'};

/// [schema] cut to what Gemini's schema knows (see the header).
Object? geminiSchema(Object? schema) {
  if (schema is! Map) return schema;
  final out = <String, Object?>{};
  for (final MapEntry(:key, :value) in schema.entries) {
    if (!_schemaKeys.contains(key)) continue;
    if (key == 'properties' && value is Map) {
      out[key] = {for (final MapEntry(key: name, value: inner) in value.entries) '$name': geminiSchema(inner)};
    } else if (key == 'items') {
      out[key] = geminiSchema(value);
    } else if (key == 'required' && value is List && value.isEmpty) {
      continue;
    } else {
      out['$key'] = value;
    }
  }
  return out;
}

/// The model's id as a request's address takes it: without the listing's `models/`.
String geminiModelId(String id) => id.startsWith('models/') ? id.substring('models/'.length) : id;

/// Gemini's request for one in the Messages API's shape (see the header); [tools] false leaves the tools out.
Map<String, Object?> geminiBody(Map<String, Object?> body, {bool tools = true}) {
  final system = body['system'];
  final said = system is String ? system : aiContentText(system);
  final given = body['tools'];
  final max = body['max_tokens'];
  final declared = [
    if (tools && given is List)
      for (final tool in given)
        if (tool is Map && tool['name'] is String)
          {
            'name': tool['name'],
            if (tool['description'] is String) 'description': tool['description'],
            if (tool['input_schema'] is Map && ((tool['input_schema'] as Map)['properties'] as Map?)?.isNotEmpty == true) 'parameters': geminiSchema(tool['input_schema']),
          },
  ];
  return {
    if (said.trim().isNotEmpty)
      'systemInstruction': {
        'parts': [
          {'text': said},
        ],
      },
    'contents': geminiContents(body),
    if (declared.isNotEmpty)
      'tools': [
        {'functionDeclarations': declared},
      ],
    if (max is num) 'generationConfig': {'maxOutputTokens': max.toInt()},
  };
}

/// The conversation as Gemini's `contents` (see the header).
List<Map<String, Object?>> geminiContents(Map<String, Object?> body) {
  final out = <Map<String, Object?>>[];
  final names = <String, String>{};
  final messages = body['messages'];
  if (messages is! List) return out;
  for (final message in messages) {
    if (message is! Map) continue;
    final role = message['role'] == 'assistant' ? 'model' : 'user';
    final content = message['content'];
    final parts = <Map<String, Object?>>[];
    if (content is String) {
      if (content.isNotEmpty) parts.add({'text': content});
    } else if (content is List) {
      for (final block in content) {
        if (block is! Map) continue;
        switch (block['type']) {
          case 'text':
            final text = block['text'];
            if (text is String && text.isNotEmpty) parts.add({'text': text});
          case 'tool_use':
            final id = block['id'], name = block['name'] as String? ?? '';
            if (id is String) names[id] = name;
            final signature = geminiSignatureOf(id);
            parts.add({
              'functionCall': {'name': name, 'args': block['input'] ?? const <String, Object?>{}},
              'thoughtSignature': ?signature,
            });
          case 'tool_result':
            final text = aiToolResultText(block['content']);
            parts.add({
              'functionResponse': {
                'name': names[block['tool_use_id']] ?? '',
                'response': block['is_error'] == true ? {'error': text} : {'result': text},
              },
            });
        }
      }
    }
    if (parts.isEmpty) continue;
    out.add({'role': role, 'parts': parts});
  }
  return out;
}

/// Gemini's stream as the Messages API's events (see the header).
class GeminiTranslator extends AiTranslator {
  GeminiTranslator({required this.model});

  final String model;

  bool _started = false;
  int _next = 0;
  int _calls = 0;
  int? _text;
  int? _thought;
  bool _called = false;
  String? _finish;
  Map<String, Object?>? _usage;
  bool _ended = false;

  List<SseEvent> _close(int? index) => index == null ? const [] : [aiEvent('content_block_stop', {'index': index})];

  @override
  Iterable<SseEvent> take(SseEvent raw) sync* {
    final data = raw.data.trim();
    if (data.isEmpty) return;
    final json = aiJson(data);
    final error = json['error'];
    if (error is Map) {
      final refused = geminiErrorOf((error['code'] as num?)?.toInt() ?? 500, jsonEncode(json));
      yield aiEvent('error', {
        'error': {'type': refused.type ?? 'api_error', 'message': refused.message},
      });
      return;
    }
    if (!_started) {
      _started = true;
      final version = json['modelVersion'];
      yield aiEvent('message_start', {
        'message': {'model': version is String && version.isNotEmpty ? version : model, 'usage': const <String, Object?>{}},
      });
    }
    final usage = json['usageMetadata'];
    if (usage is Map) _usage = usage.cast<String, Object?>();
    final feedback = json['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] is String) _finish = 'SAFETY';
    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty || candidates.first is! Map) return;
    final candidate = candidates.first as Map;
    final content = candidate['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is List) {
      for (final part in parts) {
        if (part is! Map) continue;
        final text = part['text'];
        final call = part['functionCall'];
        if (call is Map) {
          yield* _close(_text);
          yield* _close(_thought);
          _text = _thought = null;
          _called = true;
          final index = _next++;
          final signature = part['thoughtSignature'];
          yield aiEvent('content_block_start', {
            'index': index,
            'content_block': {'type': 'tool_use', 'id': geminiToolId(++_calls, signature is String ? signature : null), 'name': call['name']?.toString() ?? '', 'input': const <String, Object?>{}},
          });
          yield aiEvent('content_block_delta', {
            'index': index,
            'delta': {'type': 'input_json_delta', 'partial_json': jsonEncode(call['args'] ?? const <String, Object?>{})},
          });
          yield* _close(index);
        } else if (text is String && text.isNotEmpty) {
          if (part['thought'] == true) {
            if (_thought == null) {
              yield* _close(_text);
              _text = null;
              _thought = _next++;
              yield aiEvent('content_block_start', {
                'index': _thought,
                'content_block': {'type': 'thinking', 'thinking': ''},
              });
            }
            yield aiEvent('content_block_delta', {
              'index': _thought,
              'delta': {'type': 'thinking_delta', 'thinking': text},
            });
          } else {
            if (_text == null) {
              yield* _close(_thought);
              _thought = null;
              _text = _next++;
              yield aiEvent('content_block_start', {
                'index': _text,
                'content_block': {'type': 'text', 'text': ''},
              });
            }
            yield aiEvent('content_block_delta', {
              'index': _text,
              'delta': {'type': 'text_delta', 'text': text},
            });
          }
        }
      }
    }
    final finish = candidate['finishReason'];
    if (finish is String && finish.isNotEmpty) _finish = finish;
  }

  @override
  Iterable<SseEvent> end() sync* {
    if (_ended) return;
    _ended = true;
    if (!_started) {
      yield aiEvent('message_start', {
        'message': {'model': model, 'usage': const <String, Object?>{}},
      });
    }
    yield* _close(_thought);
    yield* _close(_text);
    final stop = _called
        ? 'tool_use'
        : switch (_finish) {
            'MAX_TOKENS' => 'max_tokens',
            'SAFETY' || 'RECITATION' || 'BLOCKLIST' || 'PROHIBITED_CONTENT' || 'SPII' || 'IMAGE_SAFETY' => 'refusal',
            _ => 'end_turn',
          };
    final usage = _usage;
    int count(Object? value) => value is num ? value.toInt() : 0;
    final cached = count(usage?['cachedContentTokenCount']);
    yield aiEvent('message_delta', {
      'delta': {'stop_reason': stop},
      if (usage != null) 'usage': {'input_tokens': (count(usage['promptTokenCount']) - cached).clamp(0, 1 << 40), 'output_tokens': count(usage['candidatesTokenCount']) + count(usage['thoughtsTokenCount']), 'cache_read_input_tokens': cached},
    });
    yield aiEvent('message_stop', const {});
  }
}

/// The Gemini API with one key.
class GeminiApi implements AiProvider {
  GeminiApi({required this.key, this.base = geminiBase, this.settings, HttpClient Function()? client}) : _client = client ?? HttpClient.new;

  final String key;
  final String base;

  /// Where a model that refused tools is remembered, so it is said once.
  final AiProviderSettings? settings;
  final HttpClient Function() _client;

  Map<String, String> get _headers => {'x-goog-api-key': key};

  static const String _unreachable = 'Gemini could not be reached. Check the connection.';

  @override
  AiCall stream(Map<String, Object?> body) {
    final model = geminiModelId(body['model'] as String? ?? '');
    final known = settings?.toolsRefused(model) ?? false;
    AiRequest request({required bool tools}) => AiRequest(
          url: Uri.parse('$base/models/$model:streamGenerateContent?alt=sse'),
          headers: _headers,
          body: geminiBody(body, tools: tools && !known),
          translator: () => GeminiTranslator(model: model),
        );
    final first = request(tools: true);
    final offered = first.body.containsKey('tools');
    return aiPostStream(
      client: _client,
      first: first,
      errorOf: geminiErrorOf,
      unreachable: _unreachable,
      retry: (refused) {
        if (!offered || !aiRefusedTools(refused)) return null;
        final news = settings?.refuseTools(model) ?? true;
        return (request: request(tools: false), notice: news ? noToolsNotice(model) : null);
      },
    );
  }

  @override
  Future<AiError?> check() async {
    try {
      final answer = await aiGetJson(client: _client, url: Uri.parse('$base/models?pageSize=1'), headers: _headers, unreachable: _unreachable, slow: 'Gemini took too long to answer.');
      return answer.status == 200 ? null : geminiErrorOf(answer.status, answer.body);
    } on AiError catch (error) {
      return error;
    }
  }

  @override
  Future<List<AiModelInfo>> models() async {
    final found = <AiModelInfo>[];
    String? page;
    for (var pages = 0; pages < 4; pages++) {
      final url = Uri.parse('$base/models?pageSize=1000${page == null ? '' : '&pageToken=${Uri.encodeQueryComponent(page)}'}');
      final answer = await aiGetJson(client: _client, url: url, headers: _headers, unreachable: _unreachable, slow: 'Gemini took too long to answer.');
      if (answer.status != 200) throw geminiErrorOf(answer.status, answer.body);
      final listed = geminiModelsOf(answer.body);
      found.addAll(listed.models);
      page = listed.next;
      if (page == null || page.isEmpty) break;
    }
    final best = geminiDefault([for (final m in found) m.id]);
    found.sort((a, b) => a.id == best ? -1 : (b.id == best ? 1 : 0));
    return found;
  }
}

/// Words in a model's id that say it does not chat: embeddings, pictures, video, speech, the live API's.
final RegExp _notChat = RegExp(r'embed|aqa|imagen|veo|image|tts|live|native-audio|robotics');

/// The models one page of `GET /models` lists that write text (`generateContent`), and the next page's token.
({List<AiModelInfo> models, String? next}) geminiModelsOf(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return (models: const [], next: null);
  }
  if (json is! Map) return (models: const [], next: null);
  final found = <AiModelInfo>[];
  final models = json['models'];
  if (models is List) {
    for (final model in models) {
      if (model is! Map || model['name'] is! String) continue;
      final id = geminiModelId(model['name'] as String);
      final methods = model['supportedGenerationMethods'];
      if (methods is List && !methods.contains('generateContent')) continue;
      if (!id.startsWith('gemini') || _notChat.hasMatch(id)) continue;
      found.add(AiModelInfo(id, name: model['displayName'] as String?, about: model['description'] as String? ?? ''));
    }
  }
  final next = json['nextPageToken'];
  return (models: found, next: next is String ? next : null);
}

/// A Gemini model's version, read from its id: `gemini-2.5-pro` 2.5; 0 for none.
double _version(String id) {
  final match = RegExp(r'^gemini-(\d+(?:\.\d+)?)').firstMatch(id);
  return match == null ? 0 : double.parse(match.group(1)!);
}

/// The default among [ids]: the newest stable Pro (no `preview`, `exp` or date after it), else the newest stable
/// Flash, else the newest Pro or Flash at all, else the first; null for none. Read from the list, never written here.
String? geminiDefault(List<String> ids) {
  String? newest(bool Function(String id) fits) {
    String? best;
    for (final id in ids.where(fits)) {
      if (best == null || _version(id) > _version(best)) best = id;
    }
    return best;
  }

  bool stable(String id) => !RegExp(r'preview|exp|latest|-\d{3,}').hasMatch(id);
  return newest((id) => stable(id) && RegExp(r'^gemini-\d+(?:\.\d+)?-pro$').hasMatch(id)) ??
      newest((id) => stable(id) && RegExp(r'^gemini-\d+(?:\.\d+)?-flash$').hasMatch(id)) ??
      newest((id) => RegExp(r'^gemini-\d+(?:\.\d+)?-(pro|flash)').hasMatch(id)) ??
      ids.firstOrNull;
}
