import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../assistant/app_assistant.dart' show appAssistant;
import '../../assistant/assistant.dart';
import '../../core/preferences.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import 'pane_parts.dart';
import 'settings_host.dart';

/// What Settings' search finds on AI (`findable`, src/app/settings/AiPane.findable.ts), by the names the page draws.
const List<SettingsFindable> aiFindable = [
  SettingsFindable('Model', 'ai llm download formatting format enhance summarize choose your qwen gemma storage remove'),
  SettingsFindable('Fill blanks on their own', 'auto fill blanks automatic weather live facts idle'),
  SettingsFindable('Assistant', 'assistant ai chat ask dock claude openai gpt gemini google custom openrouter ollama lm studio meeting summaries provider which model'),
];

/// A model in the catalogue (core/ai.ts `ModelChoice`).
@immutable
class ModelChoice {
  const ModelChoice({required this.id, required this.name, required this.about, required this.bytes});
  final String id;
  final String name;
  final String about;
  final int bytes;
}

/// The catalogue (core/ai.ts `MODELS`, as the web app has it on 2026-10-07).
const List<ModelChoice> models = [
  ModelChoice(id: 'qwen3.5-2b', name: 'Qwen3.5 2B', about: 'Quick. Good for short notes, and it can shorten long ones.', bytes: 1280835840),
  ModelChoice(id: 'qwen3.5-4b', name: 'Qwen3.5 4B', about: 'The balance. Fits most phones; check a fact it answers from memory.', bytes: 2740937888),
  ModelChoice(id: 'qwen3.5-9b', name: 'Qwen3.5 9B', about: 'The most careful, and the slowest. Wants 12 GB of memory.', bytes: 5680522464),
  ModelChoice(id: 'gemma-4-e4b', name: 'Gemma 4 E4B', about: 'A different voice. Runs like a 4B, with a bigger file.', bytes: 4977171584),
];

/// What every model is, said one way everywhere (core/ai.ts `MODEL_LIMITS`).
const String modelLimits = 'The model has no internet. It knows what it learnt in training, nothing newer, and it can be wrong.';

/// Bytes as a person reads them: "2.7 GB" (`gb`).
String gb(int bytes) => '${(bytes / 1e9).toStringAsFixed(1)} GB';

/// A model's name by its id, or the id for one this build does not offer (`modelName`).
String modelName(String id) => models.where((m) => m.id == id).firstOrNull?.name ?? id;

/// AI's row in the list: the model the AI runs, with what it takes to get when it is not here.
String aiSummary(Preferences prefs, SettingsModelsState? state) {
  final here = state?.present.contains(prefs.formatModel) ?? false;
  final bytes = models.where((m) => m.id == prefs.formatModel).firstOrNull?.bytes ?? 0;
  return '${modelName(prefs.formatModel)}${here ? '' : ', ${gb(bytes)} to get'}';
}

/// Port of `AiPane` (src/app/settings/AiPane.tsx), which is `ModelCard` (ModelCard.tsx): which language model writes
/// the summaries and the review and runs the AI on a note, which of them are here, and the switch for filling a
/// note's blanks on their own.
///
/// One row a model, once. Not here: Get, which downloads it in the open with the bytes arriving in a callout above.
/// Here: a radio to choose it, and Remove beside it, asked twice. The one in use has no Remove unless it is the only
/// one here.
///
/// "Fill blanks on their own" (`autoFill`) and the chosen model (`formatModel`) are stored preferences, live in
/// `preferences` at once.
///
/// What differs from the web original: there is no model store or downloader yet (stage 8). What is on the device
/// is [SettingsFeatures.models], which is null until then and reads as nothing downloaded; **Get cannot be pressed
/// until [SettingsFeatures.onGetModel] is given**, and Remove runs [SettingsFeatures.onRemoveModel]. Nothing here
/// runs a model.
///
/// **Assistant** (docs/AI_PROVIDERS.md, "The assistant"; Matt, 2026-10-29: "Add support for aster 6 and other Ai models
/// as plugins in addition to claude like openAI google gemini etc"): which AI answers the dock's chat and Ask, and
/// which writes meetings up, each Automatic unless chosen (lib/assistant/assistant.dart): Claude where it can, else the
/// first other provider set up, else nobody for the chat and this device's model for meetings. Each row says whether
/// that one can answer now.
class AiPane extends StatefulWidget {
  const AiPane({super.key, this.store, this.features = const SettingsFeatures(), this.android, this.assistant});

  /// Which AI does what; the app's own when null.
  final AssistantChoice? assistant;

  /// The preferences to read and write; the app's own when null.
  final PreferencesStore? store;
  final SettingsFeatures features;
  final bool? android;

  static Widget hosted(BuildContext context) => AiPane(features: SettingsHost.maybeOf(context)?.features ?? const SettingsFeatures());

  @override
  State<AiPane> createState() => _AiPaneState();
}

class _AiPaneState extends State<AiPane> {
  /// The model whose Remove has had its first tap, for a few seconds.
  String? _armed;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _removeTapped(String id) {
    _timer?.cancel();
    if (_armed != id) {
      setState(() => _armed = id);
      HapticsProvider.of(context)(HapticKind.warning);
      _timer = Timer(armedFor, () {
        if (mounted) setState(() => _armed = null);
      });
      return;
    }
    setState(() => _armed = null);
    widget.features.onRemoveModel?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store ?? preferences;
    final features = widget.features;
    final state = features.models ?? const SettingsModelsState();
    final android = widget.android ?? defaultTargetPlatform == TargetPlatform.android;
    // The Mac runs them too, and a Mac is not a phone.
    final device = android ? 'the phone' : 'this Mac';
    final present = state.present;
    final held = models.where((m) => present.contains(m.id)).fold<int>(0, (sum, m) => sum + m.bytes);
    final downloading = models.where((m) => m.id == state.downloading).firstOrNull;
    final get = features.onGetModel;
    return ValueListenableBuilder<Preferences>(
      valueListenable: store,
      builder: (context, prefs, _) {
        final t = context.tokens;
        // In use is the one that runs: the chosen one when it is here, else the one standing in for it.
        final running = state.running ?? (present.contains(prefs.formatModel) ? prefs.formatModel : null);
        return PaneBody(
          children: [
            if (downloading != null)
              SettingsCallout(
                icon: const AppIcon(Lucide.download, size: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Getting ${downloading.name}, ${gb(state.received)} of ${gb(state.total)}. Keep Ghost.md open.'),
                    SizedBox(height: t.space(2)),
                    GlacierProgressBar(ariaLabel: 'Downloading ${downloading.name}', value: state.received.toDouble(), max: (state.total < 1 ? 1 : state.total).toDouble(), size: GlacierProgressBarSize.sm),
                  ],
                ),
              ),
            if (state.problem != null) SettingsCallout(child: Text(state.problem!)),
            PaneSection(
              title: 'Model',
              description: Text("Writes the summaries and the review, runs the AI in a note's More sheet, and fills its blanks. Bigger writes better, and is slower. It runs on $device and sends nothing anywhere. $modelLimits"),
              footer: Text(held > 0 ? '${gb(held)} on $device.' : 'Nothing downloaded yet. Get one above, or tap the robot on a note and it will offer to.'),
              children: [
                for (final model in models)
                  () {
                    final here = present.contains(model.id);
                    final inUse = model.id == running;
                    final removable = here && (!inUse || present.length == 1);
                    return SettingRow(
                      key: ValueKey(model.id),
                      label: model.name,
                      hint: Text(here && state.cannotRun.contains(model.id) ? 'Can’t run in this version of Ghost.md. ${model.about} ${gb(model.bytes)}.' : '${model.about} ${gb(model.bytes)}.'),
                      value: removable
                          ? RowAction(onPress: () => _removeTapped(model.id), disabled: features.onRemoveModel == null, child: Text(_armed == model.id ? 'Tap again' : 'Remove'))
                          : inUse
                              ? const Text('In use')
                              : state.downloading == model.id
                                  ? const Text('Downloading')
                                  : null,
                      control: here
                          ? Pick(checked: inUse, label: 'Use ${model.name}', onPress: () => store.update((now) => now.copyWith(formatModel: model.id)))
                          : RowAction(onPress: () => get?.call(model.id), disabled: get == null || state.downloading != null, child: const Text('Get')),
                    );
                  }(),
                SettingRow(
                  label: 'Fill blanks on their own',
                  hint: const Text('A few seconds after you stop typing, blanks the phone can answer fill themselves, so you needn’t reach for Fill. Press it any time instead.'),
                  control: GlacierSwitch(ariaLabel: 'Fill blanks on their own', checked: prefs.autoFill, onCheckedChange: (on) => store.update((now) => now.copyWith(autoFill: on))),
                ),
              ],
            ),
            AssistantSection(choice: widget.assistant ?? appAssistant),
          ],
        );
      },
    );
  }
}

/// Settings › AI › Assistant (see [AiPane]).
class AssistantSection extends StatefulWidget {
  const AssistantSection({super.key, required this.choice});

  final AssistantChoice choice;

  @override
  State<AssistantSection> createState() => _AssistantSectionState();
}

class _AssistantSectionState extends State<AssistantSection> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.choice.load());
  }

  /// Whether [id] can answer the chat now, or write meetings up, in a few words.
  String _state(String id, {required bool meetings}) {
    final choice = widget.choice;
    if (id == claudeAssistantId) {
      if (!choice.claudeOn()) return 'Off: add Claude in the Market.';
      if (!choice.claude.hasKey) return 'Needs its key: Settings › Claude.';
      if (meetings && !choice.claude.meetings) return 'Its Write meeting summaries with Claude is off.';
      return 'Ready.';
    }
    final other = choice.other(id);
    if (other == null) return '';
    if (!other.allowed()) return 'Off: add ${other.name} in the Market.';
    if (!other.settings.ready) return 'Needs setting up: Settings › ${other.name}.';
    if (meetings && !other.settings.meetings) return 'Its Write meeting summaries with ${other.name} is off.';
    return 'Ready: ${other.settings.model}.';
  }

  List<Widget> _picks({required String chosen, required List<(String, String)> choices, required bool meetings, required void Function(String id) pick}) {
    final choice = widget.choice;
    final auto = meetings ? choice.autoMeetingsBy : choice.autoChatBy;
    final now = chosen == assistantAuto ? 'Now' : 'Would be';
    return [
      for (final (id, name) in choices)
        SettingRow(
          key: ValueKey('assistant-${meetings ? 'meetings' : 'chat'}:$id'),
          label: name,
          hint: Text(switch (id) {
            assistantAuto => auto == null ? (meetings ? '$now: this device’s own model.' : '$now: nobody. Set up Claude or another AI to talk to it.') : '$now: ${choice.nameOf(auto)}.',
            assistantDevice => 'The summary model on your device, and nothing of a meeting leaves it.',
            _ => _state(id, meetings: meetings),
          }),
          control: Pick(checked: chosen == id, label: '${meetings ? 'Meetings by' : 'Chat with'} $name', onPress: () => pick(id)),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final choice = widget.choice;
    return ListenableBuilder(
      listenable: choice,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: context.tokens.space(4),
        children: [
          PaneSection(
            title: 'Assistant',
            description: const Text('Which AI answers the dock’s chat and Ask. Automatic is Claude where it can answer, else the first other AI you have set up.'),
            footer: const Text('Each one you set up sends what you ask, and the notes it reads to answer, from this device to its provider under your own key. A chosen one that can’t answer just now (its key forgotten, its plugin off) lets Automatic stand in.'),
            children: _picks(chosen: choice.chat, choices: choice.chatChoices, meetings: false, pick: (id) => unawaited(choice.setChat(id))),
          ),
          PaneSection(
            title: 'Meeting summaries',
            description: const Text('Which AI writes your meetings up. Automatic is Claude where it may, else the first other AI allowed to, else the summary model on your device.'),
            children: _picks(chosen: choice.meetings, choices: choice.meetingsChoices, meetings: true, pick: (id) => unawaited(choice.setMeetings(id))),
          ),
        ],
      ),
    );
  }
}
