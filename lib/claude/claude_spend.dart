/// What the app's own Claude spends with the person's key, and the monthly limit they may set on it
/// (docs/CLAUDE_APP.md, "Spending limit"). Matt, 2026-10-20: "Also enable setting spending limits in claude settings
/// in the app".
///
/// **The count is the app's own, on this device.** The API cannot say what a key has spent without an Admin key, so
/// every request the app makes is priced here from the `usage` Claude reports with it ([ClaudeUsage]: the stream's
/// `message_start` and `message_delta`) at the table's prices ([claudePrices]), and added to this month's total.
/// Other apps, and other devices with the same key, are not in it. It is kept in the device's secure store beside the
/// key (one small JSON string, [claudeSpendName]), never synced, and starts again on the 1st of each month, local
/// time.
///
/// **The limit follows the account** (lib/sync/sealed_keys.dart; Matt, 2026-10-26: "the Claude tokens and other stuff
/// is kept in sync across all instances of ghost"): its switch, amount and warning are kept a second time on their
/// own, [claudeLimitName], written only when the person sets them, so a device that never chose one does not send the
/// defaults over a choice made elsewhere. That one travels, sealed; the count stays each device's, as above, so each
/// device holds its own month to the same limit. [ClaudeSpend.reloadLimit] reads it again once another device's
/// arrives.
///
/// **What is counted:** every request through [meterClaude]: each turn of a chat's or a voice ask's tool loop, the
/// inbox's, the folder tools' (all lib/claude/claude_run.dart), and a meeting's write-up (lib/ai/summary_claude.dart).
/// A request cut off before Claude gave its last count (stopped, the connection lost) is counted with what it had
/// reported, its output guessed from what had streamed when no count came.
///
/// **The limit** (off by default): once this month's total reaches it, no request is sent ([ClaudeSpend.reached],
/// [claudeLimitMessage]); a run that crosses it finishes the request it is in and starts no other. "Warn me at 80%"
/// shows a notice in the chat once a month ([ClaudeSpend.takeNotice]).
///
/// **The other providers' limits are this one too** (docs/AI_PROVIDERS.md, "Spending limit"; Matt, 2026-10-29: "Add
/// support for aster 6 and other Ai models as plugins in addition to claude like openAI google gemini etc"): a
/// [ClaudeSpend] each, made by lib/assistant/provider_settings.dart under that provider's own names in the secure store
/// ([ClaudeSpend.spendName], [ClaudeSpend.limitName]), priced by its own rates ([ClaudeSpend.price]) and saying its
/// own name and page ([ClaudeSpend.who], [ClaudeSpend.place]). Claude's is made with none of those said, and is the
/// one it always was.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../account/device_keys.dart' show SecureStore;
import 'messages_api.dart' show ClaudeCall, ClaudeError;
import 'sse.dart' show SseEvent;

/// The name in the secure store.
const String claudeSpendName = 'anthropic-spend';

/// The limit's own name in the secure store: `{on, limit, warn}`, written when the person sets one (see the header).
const String claudeLimitName = 'anthropic-limit';

/// The [ClaudeError.type] of a request the limit kept from being sent.
const String claudeLimitType = 'spending_limit';

/// The monthly amounts Settings offers at a tap, in US dollars.
const List<double> claudeLimitPresets = [5, 10, 25, 50];

/// The limit a person starts from when they switch it on.
const double defaultClaudeLimit = 10;

/// The share of the limit at which "Warn me at 80%" warns.
const double claudeWarnShare = 0.8;

/// One model's prices, in US dollars per million tokens.
@immutable
class ClaudePrice {
  const ClaudePrice({required this.input, required this.output, required this.cacheRead, this.long});

  /// Input not read from the cache.
  final double input;
  final double output;

  /// Input read from the cache.
  final double cacheRead;

  /// Writes to the cache: 1.25 times input for the 5-minute cache, 2 times for the 1-hour one.
  double get cacheWrite5m => input * 1.25;
  double get cacheWrite1h => input * 2;

  /// The prices a prompt longer than [claudeLongPrompt] tokens is billed at, where the model has a second rate card.
  final ClaudePrice? long;
}

/// The prompt length (input, cache writes and cache reads together) above which a model's [ClaudePrice.long] card
/// applies: Haiku 5.5's.
const int claudeLongPrompt = 100000;

/// The date [claudePrices] were read.
const String claudePricesAsOf = '2026-10-20';

/// What each model costs, by id. **From** the Claude API reference's model table (the claude-api skill, its table
/// cached 2026-10-06, read [claudePricesAsOf]; Anthropic's own page is platform.claude.com/docs/en/about-claude/pricing):
/// input and output per MTok; cache reads 0.1 times input except where the reference says otherwise (Fable 5.1 and
/// Mythos 5.1 $0.25, Opus 5.5 $0.20, Sonnet 5.5 $0.20); cache writes 1.25 times input (5 minutes) and 2 times (1
/// hour); Haiku 5.5 at $0.50 / $2.50 once its prompt is over 100K tokens. The app offers three of these
/// (claude_settings.dart `claudeModels`); the rest are here for an id kept from before and for the model a
/// server-side fallback answers with (the stream's `message_start` names it). Prices change: update this table, and
/// [claudePricesAsOf] with it.
const Map<String, ClaudePrice> claudePrices = {
  'claude-fable-5-1': ClaudePrice(input: 10, output: 50, cacheRead: 0.25),
  'claude-mythos-5-1': ClaudePrice(input: 10, output: 50, cacheRead: 0.25),
  'claude-fable-5': ClaudePrice(input: 10, output: 50, cacheRead: 1),
  'claude-opus-5-5': ClaudePrice(input: 4, output: 20, cacheRead: 0.20),
  'claude-opus-5': ClaudePrice(input: 5, output: 25, cacheRead: 0.50),
  'claude-opus-4-8': ClaudePrice(input: 5, output: 25, cacheRead: 0.50),
  'claude-opus-4-7': ClaudePrice(input: 5, output: 25, cacheRead: 0.50),
  'claude-opus-4-6': ClaudePrice(input: 5, output: 25, cacheRead: 0.50),
  'claude-sonnet-5-5': ClaudePrice(input: 2, output: 10, cacheRead: 0.20),
  'claude-sonnet-5': ClaudePrice(input: 2, output: 10, cacheRead: 0.20),
  'claude-sonnet-4-6': ClaudePrice(input: 3, output: 15, cacheRead: 0.30),
  'claude-haiku-5-5': ClaudePrice(input: 0.10, output: 0.50, cacheRead: 0.01, long: ClaudePrice(input: 0.50, output: 2.50, cacheRead: 0.05)),
  'claude-haiku-4-5': ClaudePrice(input: 1, output: 5, cacheRead: 0.10),
};

/// A model the table does not know is counted at the dearest of each price it holds: never under the real cost.
final ClaudePrice claudeDearest = ClaudePrice(
  input: claudePrices.values.map((p) => p.input).reduce(math.max),
  output: claudePrices.values.map((p) => p.output).reduce(math.max),
  cacheRead: claudePrices.values.map((p) => p.cacheRead).reduce(math.max),
);

/// A web search Claude runs on the server, in US dollars: Anthropic's published $10 per 1,000. The app asks for no
/// server tools today; a search reported is counted all the same.
const double claudeWebSearchPrice = 0.01;

/// The prices for [model]: its own, a dated id's by its name (`claude-haiku-4-5-20251001`), or [claudeDearest].
ClaudePrice claudePriceOf(String model) {
  final id = model.startsWith('anthropic.') ? model.substring('anthropic.'.length) : model;
  final exact = claudePrices[id];
  if (exact != null) return exact;
  String? best;
  for (final known in claudePrices.keys) {
    if (id.startsWith('$known-') && (best == null || known.length > best.length)) best = known;
  }
  return best == null ? claudeDearest : claudePrices[best]!;
}

/// What one request used, as Claude reports it (the Messages API's `usage`).
class ClaudeUsage {
  ClaudeUsage({this.input = 0, this.output = 0, this.cacheWrite5m = 0, this.cacheWrite1h = 0, this.cacheRead = 0, this.webSearches = 0});

  /// `input_tokens`: the input not written to or read from the cache.
  int input;
  int output;

  /// `cache_creation_input_tokens`, by how long the cache keeps them (`cache_creation`); all 5-minute where the
  /// answer does not say.
  int cacheWrite5m;
  int cacheWrite1h;

  /// `cache_read_input_tokens`.
  int cacheRead;

  /// `server_tool_use.web_search_requests`.
  int webSearches;

  /// The whole prompt: what decides which of a model's rate cards applies.
  int get prompt => input + cacheWrite5m + cacheWrite1h + cacheRead;

  bool get isEmpty => prompt == 0 && output == 0 && webSearches == 0;

  /// Takes in a `usage` map. The stream reports some counts in `message_start` and the rest, running totals, in
  /// `message_delta`; each count is kept at the most it has been said to be.
  void take(Object? usage) {
    if (usage is! Map) return;
    int count(Object? value) => value is num ? value.toInt() : 0;
    input = math.max(input, count(usage['input_tokens']));
    output = math.max(output, count(usage['output_tokens']));
    cacheRead = math.max(cacheRead, count(usage['cache_read_input_tokens']));
    final written = count(usage['cache_creation_input_tokens']);
    final split = usage['cache_creation'];
    if (split is Map && (split.containsKey('ephemeral_5m_input_tokens') || split.containsKey('ephemeral_1h_input_tokens'))) {
      cacheWrite5m = math.max(cacheWrite5m, count(split['ephemeral_5m_input_tokens']));
      cacheWrite1h = math.max(cacheWrite1h, count(split['ephemeral_1h_input_tokens']));
    } else if (written > cacheWrite5m + cacheWrite1h) {
      cacheWrite5m = written - cacheWrite1h;
    }
    final tools = usage['server_tool_use'];
    if (tools is Map) webSearches = math.max(webSearches, count(tools['web_search_requests']));
  }

  @override
  String toString() => 'ClaudeUsage(in $input, out $output, write $cacheWrite5m+$cacheWrite1h, read $cacheRead, searches $webSearches)';
}

/// What [usage] cost on [model], in US dollars.
double claudeCost(String model, ClaudeUsage usage) {
  final base = claudePriceOf(model);
  final price = base.long != null && usage.prompt > claudeLongPrompt ? base.long! : base;
  const million = 1000000;
  return (usage.input * price.input +
              usage.output * price.output +
              usage.cacheWrite5m * price.cacheWrite5m +
              usage.cacheWrite1h * price.cacheWrite1h +
              usage.cacheRead * price.cacheRead) /
          million +
      usage.webSearches * claudeWebSearchPrice;
}

/// Dollars as Settings shows them: `$12.34`.
String claudeDollars(double amount) => '\$${amount.toStringAsFixed(2)}';

/// A limit as Settings shows it: `$10`, or `$12.50` where it has cents.
String claudeLimitWords(double limit) => limit == limit.roundToDouble() ? '\$${limit.toStringAsFixed(0)}' : claudeDollars(limit);

/// What is said where a request is not sent for the limit; [place] is the page it is changed on.
String claudeLimitMessage(double limit, {String place = 'Settings › Claude'}) => 'Monthly spending limit reached (${claudeLimitWords(limit)}). Change it in $place.';

/// This month as a key: `2026-10`, local time.
String claudeMonthOf(DateTime when) => '${when.year.toString().padLeft(4, '0')}-${when.month.toString().padLeft(2, '0')}';

/// The count and the limit, on this device (see the header).
class ClaudeSpend extends ChangeNotifier {
  ClaudeSpend(this._store, {DateTime Function()? now, this.spendName = claudeSpendName, this.limitName = claudeLimitName, this.price, this.who = 'Claude', this.place = 'Settings › Claude'}) : now = now ?? DateTime.now;

  final SecureStore _store;

  /// The names the count and the limit are kept under: [claudeSpendName] and [claudeLimitName] for Claude's, another
  /// provider's own for its (see the header).
  final String spendName;
  final String limitName;

  /// What a request cost on a model, where it is not Claude's table ([claudeCost]) that prices it.
  final double Function(String model, ClaudeUsage usage)? price;

  /// Who is counted, and the page the limit is changed on, in what the limit and its warning say.
  final String who;
  final String place;

  /// The clock the month is read from.
  @visibleForTesting
  DateTime Function() now;

  bool _on = false;
  double _limit = defaultClaudeLimit;
  bool _warn = true;
  String? _month;
  double _spent = 0;
  int _requests = 0;
  bool _warned = false;
  Future<void>? _loading;
  bool _loaded = false;

  /// Whether the limit's settings were changed before the store was read: those are kept over what it held.
  bool _setEarly = false;

  /// Whether the limit is on.
  bool get on => _on;

  /// The monthly limit, in US dollars.
  double get limit => _limit;

  /// Whether the chat warns once at [claudeWarnShare] of the limit.
  bool get warn => _warn;

  /// This month's total, in US dollars.
  double get spent {
    _roll();
    return _spent;
  }

  /// The requests counted this month.
  int get requests {
    _roll();
    return _requests;
  }

  /// The limit is on and this month's total has reached it: no request is sent.
  bool get reached => _on && spent >= _limit;

  /// What is said where a request is not sent.
  String get limitMessage => claudeLimitMessage(_limit, place: place);

  /// A new month: the count starts again.
  void _roll() {
    final month = claudeMonthOf(now());
    if (_month == month) return;
    final had = _month != null && (_spent != 0 || _requests != 0 || _warned);
    _month = month;
    _spent = 0;
    _requests = 0;
    _warned = false;
    if (had) unawaited(_save());
  }

  /// Reads what this device keeps. Once; later calls wait for the same read, or for nothing once it is done.
  Future<void> load() => _loaded ? Future<void>.value() : (_loading ??= _load());

  Future<void> _load() async {
    try {
      final kept = await _store.read(spendName);
      final json = kept == null ? null : jsonDecode(kept);
      if (json is Map) {
        if (!_setEarly) {
          _on = json['on'] == true;
          final limit = json['limit'];
          if (limit is num && limit > 0) _limit = limit.toDouble();
          _warn = json['warn'] != false;
        }
        final month = json['month'];
        if (month is String) {
          // Anything counted before the read (none, as the app runs: it reads first) is added to what was kept; no
          // write is made before the read ([_save]), so none of it is in what was kept already.
          final counted = _month == month ? _spent : 0.0, asked = _month == month ? _requests : 0;
          _month = month;
          final spent = json['spent'];
          _spent = (spent is num ? spent.toDouble() : 0) + counted;
          final requests = json['requests'];
          _requests = (requests is num ? requests.toInt() : 0) + asked;
          _warned = json['warned'] == true;
        }
      }
      // The limit's own copy, which another device's may have been written over (see the header). A limit turned on
      // before there was one is a choice made all the same: its copy is made now, so it travels.
      final own = await _store.read(limitName);
      if (!_setEarly) _takeLimit(own);
      if (own == null && json is Map && json['on'] == true) await _saveLimit();
    } catch (_) {
      // A store that cannot be read is a month with nothing counted.
    }
    _loaded = true;
    notifyListeners();
  }

  Map<String, Object?> _json() => {'on': _on, 'limit': _limit, 'warn': _warn, 'month': _month, 'spent': _spent, 'requests': _requests, 'warned': _warned};

  /// The limit as [claudeLimitName] holds it, over what was read: nothing for none, or for one that will not read.
  /// Answers whether it changed anything.
  bool _takeLimit(String? kept) {
    if (kept == null) return false;
    try {
      final json = jsonDecode(kept);
      if (json is! Map) return false;
      final on = json['on'] == true, warn = json['warn'] != false;
      final limit = json['limit'] is num && (json['limit'] as num) >= 0.01 ? (json['limit'] as num).toDouble() : _limit;
      if (on == _on && warn == _warn && limit == _limit) return false;
      if (limit != _limit) _warned = false;
      _on = on;
      _warn = warn;
      _limit = limit;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The limit's settings as [claudeLimitName] holds them.
  String get limitText => jsonEncode({'on': _on, 'limit': _limit, 'warn': _warn});

  /// Keeps the limit's own copy, after the person set it.
  Future<void> _saveLimit() async {
    try {
      await _store.write(limitName, limitText);
    } catch (_) {
      // Kept in the whole count's copy all the same.
    }
  }

  /// Reads [claudeLimitName] again: another device's limit arrived in the store (lib/sync/sealed_keys.dart).
  Future<void> reloadLimit() async {
    if (!_loaded) await load();
    String? kept;
    try {
      kept = await _store.read(limitName);
    } catch (_) {
      return;
    }
    if (!_takeLimit(kept)) return;
    notifyListeners();
    await _save();
  }

  /// Writes what is kept: the whole of it each time, so the last write is the last word (the store takes its writes
  /// in the order they are made). A store that cannot be written keeps the count for this run of the app only.
  Future<void> _save() async {
    // Read first, so a write never puts this run's count over what was kept before it.
    if (!_loaded) await load();
    try {
      await _store.write(spendName, jsonEncode(_json()));
    } catch (_) {
      // Kept in memory.
    }
  }

  /// Counts one request: [usage] on [model]. Answers what it cost.
  double record(String model, ClaudeUsage usage) {
    _roll();
    final cost = (price ?? claudeCost)(model, usage);
    _spent += cost;
    _requests += 1;
    unawaited(_save());
    notifyListeners();
    return cost;
  }

  /// The notice the chat shows once a month, when "Warn me at 80%" is on and the total has passed it (and not yet
  /// the limit itself): answered once, then null until next month.
  String? takeNotice() {
    if (!_on || !_warn || _warned) return null;
    final spent = this.spent;
    if (spent < _limit * claudeWarnShare || spent >= _limit) return null;
    _warned = true;
    unawaited(_save());
    notifyListeners();
    return 'You’ve used ${claudeDollars(spent)} of your ${claudeLimitWords(_limit)} monthly limit for $who (${(spent / _limit * 100).floor()}%). Change it in $place.';
  }

  Future<void> setOn(bool on) async {
    if (on == _on) return;
    _on = on;
    if (!_loaded) _setEarly = true;
    notifyListeners();
    await _save();
    await _saveLimit();
  }

  /// A new limit, in US dollars; nothing under a cent is taken.
  Future<void> setLimit(double limit) async {
    if (!limit.isFinite || limit < 0.01 || limit == _limit) return;
    _limit = limit;
    if (!_loaded) _setEarly = true;
    // A limit raised past the warning lets it warn again; one lowered is warned of once more too.
    _warned = false;
    notifyListeners();
    await _save();
    await _saveLimit();
  }

  Future<void> setWarn(bool warn) async {
    if (warn == _warn) return;
    _warn = warn;
    if (!_loaded) _setEarly = true;
    notifyListeners();
    await _save();
    await _saveLimit();
  }

  /// Starts this month's count again.
  Future<void> resetCount() async {
    _roll();
    _spent = 0;
    _requests = 0;
    _warned = false;
    notifyListeners();
    await _save();
  }
}

/// [call], its usage counted into [spend] once it ends: priced on the model `message_start` names (a server-side
/// fallback's), else [model]. Ended, stopped or broken alike; counted once.
ClaudeCall meterClaude(ClaudeCall call, {required String model, required ClaudeSpend spend}) {
  final usage = ClaudeUsage();
  var answeredBy = model;
  var finalCount = false;
  var streamed = 0;
  var counted = false;
  void count() {
    if (counted) return;
    counted = true;
    // No last count came: the output is guessed from what streamed, about four characters a token of the events'
    // own text, which their JSON makes more rather than less.
    if (!finalCount && streamed > 0) usage.output = math.max(usage.output, (streamed / 4).ceil());
    if (!usage.isEmpty) spend.record(answeredBy, usage);
  }

  StreamSubscription<SseEvent>? inner;
  late final StreamController<SseEvent> out;
  out = StreamController<SseEvent>(
    onListen: () {
      inner = call.events.listen(
        (event) {
          switch (event.event) {
            case 'message_start':
              final data = _json(event.data);
              final message = data['message'];
              if (message is Map) {
                if (message['model'] is String && (message['model'] as String).isNotEmpty) answeredBy = message['model'] as String;
                usage.take(message['usage']);
              }
            case 'message_delta':
              final data = _json(event.data);
              if (data['usage'] is Map) {
                usage.take(data['usage']);
                finalCount = true;
              }
            case 'content_block_delta':
              streamed += event.data.length;
          }
          if (!out.isClosed) out.add(event);
        },
        onError: (Object error, StackTrace stack) {
          if (!out.isClosed) out.addError(error, stack);
        },
        onDone: () {
          count();
          if (!out.isClosed) unawaited(out.close());
        },
      );
    },
    onPause: () => inner?.pause(),
    onResume: () => inner?.resume(),
    // Not waited for: the request's own stream may take its time to let go, and what reads this one goes on.
    onCancel: () {
      count();
      unawaited(inner?.cancel());
    },
  );
  return ClaudeCall(out.stream, call.cancel);
}

Map<String, Object?> _json(String data) {
  try {
    final parsed = jsonDecode(data);
    return parsed is Map ? parsed.cast<String, Object?>() : const {};
  } catch (_) {
    return const {};
  }
}

/// [ClaudeError] for a request the limit kept back.
ClaudeError claudeLimitError(ClaudeSpend spend) => ClaudeError(spend.limitMessage, type: claudeLimitType);
