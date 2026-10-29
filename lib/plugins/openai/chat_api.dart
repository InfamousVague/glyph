/// OpenAI's Chat Completions API, and every endpoint that speaks it (docs/AI_PROVIDERS.md, "OpenAI" and "Custom AI
/// model"; Matt, 2026-10-29: "Add support for aster 6 and other Ai models as plugins in addition to claude like openAI
/// google gemini etc"). One request streamed (`POST {base}/chat/completions`, `stream: true`), with function calling
/// for the app's tools, and one small read (`GET {base}/models`) that lists the models and says whether a key works.
/// The key goes only to [OpenAiChatApi.base], in an `Authorization: Bearer` header, from this device: no Ghost.md
/// server between.
///
/// **Chat Completions, not the Responses API**, on purpose: it is the one shape that OpenRouter, Mistral, Groq,
/// DeepSeek, LM Studio, Ollama and most others answer as well (the custom endpoint, lib/plugins/custom_ai/), so one
/// translator serves them all, and it streams tool calls and usage as the run needs them.
///
/// **Translated both ways** (lib/assistant/provider.dart): the run's request, in the Messages API's shape, becomes
/// Chat Completions' ([openAiBody]): the system prompt a `system` message; a user turn's `tool_result` blocks each a
/// `tool` message, in order, before any words of the turn; an assistant turn's `tool_use` blocks its `tool_calls`, their
/// input as JSON text; Claude's thinking blocks, `thinking` and `output_config` dropped. The tools are `{type:
/// function, function: {name, description, parameters}}`, their schemas as they are. Its stream becomes the Messages
/// API's events ([OpenAiTranslator]): the first chunk a `message_start`; `delta.content` a text block;
/// `delta.reasoning_content` or `delta.reasoning` (DeepSeek's, OpenRouter's) a thinking block, shown as Claude's
/// thinking is; each `delta.tool_calls[i]` a `tool_use` block, opened once its name is known and fed its arguments as
/// `input_json_delta`s, however the provider cut them; `finish_reason` the stop (`tool_calls` → `tool_use`, `length` →
/// `max_tokens`, `content_filter` → `refusal`, and `stop` with tool calls made → `tool_use`, as some local servers
/// say); the last chunk's `usage` the counts (`prompt_tokens` less its `cached_tokens` as input, those as cache reads,
/// `completion_tokens` as output).
///
/// **The errors** ([openAiErrorOf]): 401 the key refused; 429 with `insufficient_quota` an account with no credit
/// (OpenAI says that rather than 402); 429 otherwise too many requests; 403 a key not allowed the model or the API; 404
/// no such model; 5xx the provider's trouble; no answer the connection. Each in a sentence, with the Messages API's
/// error type, so the setup and the meetings' queue read them as Claude's.
///
/// **A model without tools** (lib/assistant/http_stream.dart [aiRefusedTools]): a 400 that says the model takes no
/// tools is asked again at once without them, and the chat says so once ([AiProviderSettings.refuseTools]); later asks
/// of that model go without them.
library;

import 'dart:convert';
import 'dart:io';

import '../../assistant/http_stream.dart';
import '../../assistant/provider.dart';
import '../../assistant/provider_settings.dart';

/// OpenAI's own API.
const String openAiBase = 'https://api.openai.com/v1';

/// What the chat says once when a model refused the tools.
String noToolsNotice(String model) => '$model can’t use Ghost.md’s tools, so it answers here without them: it can’t read or change your notes in this chat.';

/// The words of a failed answer, by [who] ("OpenAI"), whose page is [place].
AiError openAiErrorOf(int status, String body, {String who = 'OpenAI', String place = 'Settings › OpenAI'}) {
  String? message, type, code;
  try {
    final json = jsonDecode(body);
    final error = json is Map ? (json['error'] is Map ? json['error'] as Map : json) : null;
    if (error != null) {
      message = (error['message'] ?? error['detail'] ?? error['msg'])?.toString();
      type = error['type']?.toString();
      code = error['code']?.toString();
    }
    if (json is Map && json['error'] is String) message ??= json['error'] as String;
  } catch (_) {
    // Not JSON: the status says it.
  }
  final quota = code == 'insufficient_quota' || type == 'insufficient_quota' || (message ?? '').toLowerCase().contains('quota');
  if (status == 401) return AiError('The API key was refused. Check it in $place.', status: status, type: 'authentication_error');
  if (status == 402 || (status == 429 && quota)) return AiError('The key works, but the account has no credit left. Add some to its billing, then try again.', status: status, type: 'billing_error');
  if (status == 429) return AiError('Too many requests for this key just now. Try again in a moment.', status: status, type: 'rate_limit_error');
  if (status == 403) return AiError('This key may not use that. ${message ?? ''}'.trim(), status: status, type: 'permission_error');
  if (status == 404) return AiError(message ?? '$who has no such model, or no such address. Check the model in $place.', status: status, type: 'not_found_error');
  if (status >= 500) return AiError('$who is having trouble just now. Try again in a moment.', status: status, type: status == 503 || status == 529 ? 'overloaded_error' : 'api_error');
  return AiError(message ?? '$who answered $status.', status: status, type: status == 400 || status == 422 ? 'invalid_request_error' : type);
}

/// The Chat Completions request for a request in the Messages API's shape (see the header). [completionTokens] says
/// `max_completion_tokens` (OpenAI's own, which its reasoning models need) rather than `max_tokens` (what the
/// compatible servers know); [tools] false leaves the tools out; [usage] asks the last chunk for the counts.
Map<String, Object?> openAiBody(Map<String, Object?> body, {bool completionTokens = true, bool tools = true, bool usage = true}) {
  final given = body['tools'];
  final offered = tools && given is List && given.isNotEmpty;
  final max = body['max_tokens'];
  return {
    'model': body['model'],
    'messages': openAiMessages(body),
    'stream': true,
    if (usage) 'stream_options': {'include_usage': true},
    if (max is num) (completionTokens ? 'max_completion_tokens' : 'max_tokens'): max.toInt(),
    if (offered)
      'tools': [
        for (final tool in given)
          if (tool is Map && tool['name'] is String)
            {
              'type': 'function',
              'function': {
                'name': tool['name'],
                if (tool['description'] is String) 'description': tool['description'],
                'parameters': tool['input_schema'] ?? const {'type': 'object', 'properties': <String, Object?>{}},
              },
            },
      ],
  };
}

/// The conversation as Chat Completions takes it (see the header).
List<Map<String, Object?>> openAiMessages(Map<String, Object?> body) {
  final out = <Map<String, Object?>>[];
  final system = body['system'];
  final said = system is String ? system : aiContentText(system);
  if (said.trim().isNotEmpty) out.add({'role': 'system', 'content': said});
  final messages = body['messages'];
  if (messages is! List) return out;
  for (final message in messages) {
    if (message is! Map) continue;
    final role = message['role'], content = message['content'];
    if (role == 'user') {
      if (content is String) {
        out.add({'role': 'user', 'content': content});
        continue;
      }
      final words = <String>[];
      if (content is List) {
        for (final block in content) {
          if (block is! Map) continue;
          if (block['type'] == 'tool_result') {
            final text = aiToolResultText(block['content']);
            out.add({'role': 'tool', 'tool_call_id': block['tool_use_id'], 'content': block['is_error'] == true ? 'Error: $text' : text});
          } else if (block['type'] == 'text' && block['text'] is String) {
            words.add(block['text'] as String);
          }
        }
      }
      if (words.isNotEmpty) out.add({'role': 'user', 'content': words.join('\n\n')});
    } else if (role == 'assistant') {
      final words = content is String ? content : aiContentText(content);
      final calls = [
        if (content is List)
          for (final block in content)
            if (block is Map && block['type'] == 'tool_use')
              {
                'id': block['id'],
                'type': 'function',
                'function': {'name': block['name'], 'arguments': jsonEncode(block['input'] ?? const <String, Object?>{})},
              },
      ];
      if (words.isEmpty && calls.isEmpty) continue;
      out.add({'role': 'assistant', 'content': words.isEmpty ? null : words, if (calls.isNotEmpty) 'tool_calls': calls});
    }
  }
  return out;
}

/// One tool call as it streams.
class _Call {
  String? id;
  final StringBuffer name = StringBuffer();
  final StringBuffer pending = StringBuffer();
  int? block;
  bool closed = false;
}

/// Chat Completions' stream as the Messages API's events (see the header).
class OpenAiTranslator extends AiTranslator {
  OpenAiTranslator({required this.model});

  /// The model asked, for `message_start` where a chunk names none.
  final String model;

  bool _started = false;
  int _next = 0;
  int? _text;
  int? _thought;
  final Map<int, _Call> _calls = {};
  final List<int> _order = [];
  String? _finish;
  Map<String, Object?>? _usage;
  bool _ended = false;

  List<SseEvent> _close(int? index) => index == null ? const [] : [aiEvent('content_block_stop', {'index': index})];

  @override
  Iterable<SseEvent> take(SseEvent raw) sync* {
    final data = raw.data.trim();
    if (data.isEmpty || data == '[DONE]') return;
    final json = aiJson(data);
    final error = json['error'];
    if (error != null) {
      final said = error is Map ? (error['message']?.toString() ?? 'The model stopped with an error.') : '$error';
      yield aiEvent('error', {
        'error': {'type': error is Map ? (error['type']?.toString() ?? 'api_error') : 'api_error', 'message': said},
      });
      return;
    }
    if (!_started) {
      _started = true;
      yield aiEvent('message_start', {
        'message': {'model': json['model'] is String && (json['model'] as String).isNotEmpty ? json['model'] : model, 'usage': const <String, Object?>{}},
      });
    }
    final usage = json['usage'];
    if (usage is Map) _usage = usage.cast<String, Object?>();
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) return;
    final choice = choices.first;
    if (choice is! Map) return;
    final delta = choice['delta'];
    if (delta is Map) {
      final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) {
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
          'delta': {'type': 'thinking_delta', 'thinking': reasoning},
        });
      }
      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
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
          'delta': {'type': 'text_delta', 'text': content},
        });
      }
      final calls = delta['tool_calls'];
      if (calls is List) {
        for (var i = 0; i < calls.length; i++) {
          final piece = calls[i];
          if (piece is! Map) continue;
          final at = (piece['index'] as num?)?.toInt() ?? i;
          final call = _calls.putIfAbsent(at, () {
            _order.add(at);
            return _Call();
          });
          if (call.closed) continue;
          if (piece['id'] is String && (piece['id'] as String).isNotEmpty) call.id ??= piece['id'] as String;
          final function = piece['function'];
          if (function is! Map) continue;
          final name = function['name'];
          if (call.block == null && name is String) call.name.write(name);
          final args = function['arguments'];
          if (call.block == null && call.name.isNotEmpty) {
            // Its name known: the block opens, after whatever was open before it, and is fed what came first.
            yield* _close(_text);
            yield* _close(_thought);
            _text = _thought = null;
            for (final other in _order) {
              final before = _calls[other]!;
              if (!identical(before, call) && before.block != null && !before.closed) {
                before.closed = true;
                yield* _close(before.block);
              }
            }
            call.block = _next++;
            yield aiEvent('content_block_start', {
              'index': call.block,
              'content_block': {'type': 'tool_use', 'id': call.id ?? 'call_$at', 'name': call.name.toString(), 'input': const <String, Object?>{}},
            });
            if (call.pending.isNotEmpty) {
              yield aiEvent('content_block_delta', {
                'index': call.block,
                'delta': {'type': 'input_json_delta', 'partial_json': call.pending.toString()},
              });
              call.pending.clear();
            }
          }
          if (args is String && args.isNotEmpty) {
            if (call.block == null) {
              call.pending.write(args);
            } else {
              yield aiEvent('content_block_delta', {
                'index': call.block,
                'delta': {'type': 'input_json_delta', 'partial_json': args},
              });
            }
          }
        }
      }
    }
    final finish = choice['finish_reason'];
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
    var called = false;
    for (final at in _order) {
      final call = _calls[at]!;
      if (call.block != null) called = true;
      if (call.block != null && !call.closed) {
        call.closed = true;
        yield* _close(call.block);
      }
    }
    final stop = switch (_finish) {
      'tool_calls' || 'function_call' => 'tool_use',
      'length' => 'max_tokens',
      'content_filter' => 'refusal',
      _ => called ? 'tool_use' : 'end_turn',
    };
    final usage = _usage;
    int count(Object? value) => value is num ? value.toInt() : 0;
    final details = usage?['prompt_tokens_details'];
    final cached = details is Map ? count(details['cached_tokens']) : 0;
    yield aiEvent('message_delta', {
      'delta': {'stop_reason': stop},
      if (usage != null) 'usage': {'input_tokens': (count(usage['prompt_tokens']) - cached).clamp(0, 1 << 40), 'output_tokens': count(usage['completion_tokens']), 'cache_read_input_tokens': cached},
    });
    yield aiEvent('message_stop', const {});
  }
}

/// A Chat Completions endpoint with one key: OpenAI's own ([openAiBase]) or another's ([official] false).
class OpenAiChatApi implements AiProvider {
  OpenAiChatApi({required this.key, this.base = openAiBase, this.official = true, this.who = 'OpenAI', this.place = 'Settings › OpenAI', this.settings, HttpClient Function()? client}) : _client = client ?? HttpClient.new;

  /// The key, or none for an endpoint that asks for none (the person's own computer's).
  final String? key;

  /// The API's address, with no slash at its end.
  final String base;

  /// Whether this is OpenAI's own API: its models are cut to the ones that chat, and `max_completion_tokens` is sent.
  final bool official;

  /// The provider's name, and the page its key is on, in what is said.
  final String who;
  final String place;

  /// Where a model that refused tools is remembered, so it is said once ([AiProviderSettings.refuseTools]); none, and
  /// every refusal is asked again without them and said.
  final AiProviderSettings? settings;
  final HttpClient Function() _client;

  Map<String, String> get _headers => {if ((key ?? '').isNotEmpty) HttpHeaders.authorizationHeader: 'Bearer $key'};

  String get _unreachable => '$who could not be reached. Check the connection${official ? '' : ' and the address'}.';

  @override
  AiCall stream(Map<String, Object?> body) {
    final model = body['model'] as String? ?? '';
    final known = settings?.toolsRefused(model) ?? false;
    AiRequest request({required bool tools, bool usage = true}) => AiRequest(
          url: Uri.parse('$base/chat/completions'),
          headers: _headers,
          body: openAiBody(body, completionTokens: official, tools: tools && !known, usage: usage),
          translator: () => OpenAiTranslator(model: model),
        );
    final first = request(tools: true);
    final offered = first.body.containsKey('tools');
    return aiPostStream(
      client: _client,
      first: first,
      errorOf: (status, text) => openAiErrorOf(status, text, who: who, place: place),
      unreachable: _unreachable,
      retry: (refused) {
        final words = refused.message.toLowerCase();
        // An older server that knows no `stream_options`: asked again without, said to no one.
        if (refused.status == 400 && words.contains('stream_options')) return (request: request(tools: true, usage: false), notice: null);
        if (offered && aiRefusedTools(refused)) {
          final news = settings?.refuseTools(model) ?? true;
          return (request: request(tools: false), notice: news ? noToolsNotice(model) : null);
        }
        return null;
      },
    );
  }

  @override
  Future<AiError?> check() async {
    try {
      final answer = await aiGetJson(client: _client, url: Uri.parse('$base/models'), headers: _headers, unreachable: _unreachable, slow: '$who took too long to answer.');
      return answer.status == 200 ? null : openAiErrorOf(answer.status, answer.body, who: who, place: place);
    } on AiError catch (error) {
      return error;
    }
  }

  @override
  Future<List<AiModelInfo>> models() async {
    final answer = await aiGetJson(client: _client, url: Uri.parse('$base/models'), headers: _headers, unreachable: _unreachable, slow: '$who took too long to answer.');
    if (answer.status != 200) throw openAiErrorOf(answer.status, answer.body, who: who, place: place);
    return openAiModelsOf(answer.body, official: official);
  }
}

/// Words in an OpenAI model's id that say it does not chat: speech, pictures, embeddings, moderation, the old
/// completions.
final RegExp _notChat = RegExp(r'embed|whisper|tts|dall-e|davinci|babbage|moderation|transcribe|realtime|audio|image|search|computer-use|sora|instruct');

/// The models a `GET /models` answer lists: for OpenAI's own ([official]) only the ones that chat, the newest first by
/// their version; for another endpoint all of them, as listed, with the rates where the listing gives them
/// (OpenRouter's `pricing`, US dollars a token).
List<AiModelInfo> openAiModelsOf(String body, {required bool official}) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  final data = json is Map ? json['data'] ?? json['models'] : (json is List ? json : null);
  if (data is! List) return const [];
  final found = <AiModelInfo>[];
  for (final model in data) {
    if (model is! Map) continue;
    final id = (model['id'] ?? model['name'] ?? model['model'])?.toString();
    if (id == null || id.isEmpty) continue;
    if (official && (!RegExp(r'^(gpt-|o\d|chatgpt-)').hasMatch(id) || _notChat.hasMatch(id))) continue;
    AiRates? rates;
    final pricing = model['pricing'];
    if (pricing is Map) {
      final input = double.tryParse('${pricing['prompt']}'), output = double.tryParse('${pricing['completion']}');
      if (input != null && output != null && input >= 0 && output >= 0) rates = AiRates(input: input * 1000000, output: output * 1000000);
    }
    final name = model['name'];
    found.add(AiModelInfo(id, name: name is String && name.isNotEmpty && name != id ? name : null, rates: rates));
  }
  if (!official) return found;
  final flagship = openAiFlagship([for (final m in found) m.id]);
  found.sort((a, b) {
    if (a.id == flagship) return -1;
    if (b.id == flagship) return 1;
    final byVersion = _version(b.id).compareTo(_version(a.id));
    return byVersion != 0 ? byVersion : a.id.compareTo(b.id);
  });
  return found;
}

/// A model's version, read from its id: `gpt-5.5` 5.5, `gpt-4o` 4, `o3` 3; 0 for none.
double _version(String id) {
  final match = RegExp(r'^(?:gpt-|chatgpt-|o)(\d+(?:\.\d+)?)').firstMatch(id);
  return match == null ? 0 : double.parse(match.group(1)!);
}

/// The flagship among [ids]: the newest `gpt-<version>` with nothing after it (no `-mini`, no date), else the newest
/// `gpt-` at all; null for none. The default model, read from the list, never written here.
String? openAiFlagship(List<String> ids) {
  final plain = RegExp(r'^gpt-\d+(?:\.\d+)?o?$');
  String? best;
  for (final id in ids.where(plain.hasMatch)) {
    if (best == null || _version(id) > _version(best)) best = id;
  }
  if (best != null) return best;
  for (final id in ids.where((id) => id.startsWith('gpt-'))) {
    if (best == null || _version(id) > _version(best)) best = id;
  }
  return best;
}
