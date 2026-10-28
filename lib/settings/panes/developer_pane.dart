import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../ai/runs.dart' show useAnyRunning;
import '../../art/art.dart';
import '../../core/preferences.dart';
import '../../guide/guide_state.dart' show guideSeen;
import '../../core/wip.dart';
import '../../shell/header_toolbar.dart';
import '../kit/settings_kit.dart';
import '../settings_search.dart';
import '../settings_sheet.dart' show developerMode;
import 'pane_parts.dart';
import 'settings_host.dart';

/// What Settings' search finds on Developer (`findable`, src/app/settings/DeveloperPane.findable.ts), by the names the
/// page draws, in its order.
const List<SettingsFindable> developerFindable = [
  SettingsFindable('Voice assistant', 'work in progress side key record note shortcut'),
  SettingsFindable('Window', 'inset screen engine'),
  SettingsFindable('Play the scene', 'scene bench thermal heat readings'),
  SettingsFindable('Developer settings', 'mode'),
  SettingsFindable('Reset local data', 'clear erase'),
  SettingsFindable('Reset everything', 'clear erase models'),
  SettingsFindable('Header toolbar', 'top bar icons versions grouped tiles command labelled grouped command'),
];

/// Which readings the scene plays with (`READINGS`), in the choice's order.
const Map<String, String> _readings = {'heat': 'Heat', 'cold': 'No heat', 'none': 'None'};

/// What the window is (diag/windowFacts.ts `windowFacts`), read off the window itself: the inset it is given at its
/// top, its size against the screen, and what draws it.
({String inset, String page, String screen, String engine}) windowFacts(BuildContext context) {
  String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  final media = MediaQuery.of(context);
  final view = View.of(context);
  final screen = view.display.size / view.display.devicePixelRatio;
  return (
    inset: '${n(media.viewPadding.top)}px',
    page: '${n(media.size.width)} × ${n(media.size.height)} @${n(media.devicePixelRatio)}',
    screen: '${n(screen.width)} × ${n(screen.height)}',
    engine: 'Flutter on ${defaultTargetPlatform.name}',
  );
}

/// Port of `DeveloperPane` (src/app/settings/DeveloperPane.tsx), present only while developer mode is on (seven
/// presses on the version in About): what the window is, the scene after Done played from a script, the switch that
/// hides the page, and the two resets. The smoke bench went with the smoke (Matt, 2026-10-24: "remove the smoke on mac
/// too so all versions get blur"): there is no wisp left to measure.
///
/// What differs from the web original:
/// - **Window** reads Flutter's own window: the top inset is the view's padding, and Engine says Flutter and the
///   platform, where the page named its browser engine.
/// - **The bench** (diag/SceneBench.tsx): "Play the scene" is drawn and cannot be pressed until
///   [SettingsFeatures.onPlayScene] is given. The readings' choice is kept for the scene's row and changes nothing
///   else. The page's smoke bench (diag/WispBench.tsx) has no counterpart: the app draws no smoke.
/// - **The resets** ask twice, as the page's do, and then run [SettingsFeatures.onReset] (core/reset.ts is the
///   library's to port); without it the word Reset is there and cannot be pressed.
class DeveloperPane extends StatefulWidget {
  const DeveloperPane({super.key, this.features = const SettingsFeatures(), this.developer, this.assistantSwitch, this.onGuide});

  /// What the Voice assistant switch does; the app's own (lib/core/wip.dart `switchVoiceAssistant`) when null.
  final Future<void> Function(bool on)? assistantSwitch;

  final SettingsFeatures features;

  /// Opens the welcome walkthrough on its first page (Settings' own, the root's `guide.show(0)`); without it the
  /// onboarding row offers nothing.
  final VoidCallback? onGuide;

  /// The switch that hides the page; the app's own when null.
  final DeviceFlag? developer;

  static Widget hosted(BuildContext context) {
    final host = SettingsHost.maybeOf(context);
    return DeveloperPane(features: host?.features ?? const SettingsFeatures(), onGuide: host?.onGuide);
  }

  @override
  State<DeveloperPane> createState() => _DeveloperPaneState();
}

class _DeveloperPaneState extends State<DeveloperPane> {
  String _scene = 'heat';

  @override
  Widget build(BuildContext context) {
    final features = widget.features;
    final developer = widget.developer ?? developerMode;
    final facts = windowFacts(context);
    final play = features.onPlayScene;
    return PaneBody(
      children: [
        PaneSection(
          title: 'Window',
          description: const Text('Read off the page: what it is given at its top, its size against the screen, and what draws it.'),
          children: [
            SettingRow(label: 'Top inset', hint: const Text("The status bar's height when the page is drawn under it; 0 when it is not."), value: Text(facts.inset)),
            SettingRow(label: 'Page', hint: const Text('Its size, and pixels to the point.'), value: Text(facts.page)),
            SettingRow(label: 'Screen', value: Text(facts.screen)),
            SettingRow(label: 'Engine', value: Text(facts.engine)),
          ],
        ),
        PaneSection(
          title: 'The phone at work',
          description: const Text("The scene after Done, played from a script. The models are pretend, the screen is this one, and the words are the note's."),
          children: [
            SettingRow(
              label: 'Readings',
              hint: const Text('With a heat reading, without one as on a phone that hides its thermal zones, or with none as on the Mac or a binary before generation 14.'),
              layout: SettingRowLayout.stacked,
              control: GlacierSegmentedControl(
                ariaLabel: 'Readings',
                fullWidth: true,
                size: GlacierSegmentedSize.sm,
                options: [for (final entry in _readings.entries) GlacierSegmentedOption(value: entry.key, label: Text(entry.value))],
                value: _scene,
                onValueChange: (value) => setState(() => _scene = _readings.containsKey(value) ? value : 'heat'),
              ),
            ),
            _SceneRow(play: play == null ? null : () => play(_scene)),
          ],
        ),
        PaneSection(
          title: 'Developer mode',
          children: [
            SettingRow(
              icon: const AppIcon(Lucide.terminal, size: 20),
              label: 'Developer settings',
              hint: const Text('Turning this off hides the page again. Seven taps on the version in About bring it back.'),
              control: ValueListenableBuilder<bool>(
                valueListenable: developer,
                builder: (context, on, _) => GlacierSwitch(ariaLabel: 'Developer settings', checked: on, onCheckedChange: developer.set),
              ),
            ),
          ],
        ),
        PaneSection(
          title: 'Reset',
          description: const Text('Two taps: the first arms it, the second does it. Ghost.md reloads on the welcome walkthrough afterwards.'),
          children: [
            _ResetRow(
              label: 'Reset local data',
              hint: 'Notes, recordings, pictures, settings, the guide and the sign-in go. Downloaded models stay, and so does this page.',
              models: false,
              onReset: features.onReset,
            ),
            _ResetRow(label: 'Reset everything', hint: 'The same, and the downloaded models too. They come back when asked for.', models: true, onReset: features.onReset),
          ],
        ),
        // After Reset, so the cards above stand where the page's do (test/settings/panes/pages_test.dart, rect for
        // rect). The onboarding again, as a new person meets it (Matt, 2026-10-28: "Add a developer setting to re run the
        // onboarding"): the walkthrough marked unseen and opened on its first page, so it behaves as on a first launch
        // (a relaunch part way comes back to it) until it is finished. Notes, settings and the sign-in stay; Reset
        // local data below is the way to a whole first launch.
        PaneSection(
          title: 'Onboarding',
          children: [
            SettingRow(
              key: const ValueKey('developer-run-onboarding'),
              icon: const AppIcon(Lucide.sparkles, size: 20),
              label: 'Run the onboarding again',
              hint: const Text('The welcome walkthrough from its first page, with its voice, as on a first launch. Your notes and settings stay.'),
              control: RowAction(
                key: const ValueKey('developer-run-onboarding-go'),
                disabled: widget.onGuide == null,
                onPress: () {
                  guideSeen().clear();
                  widget.onGuide?.call();
                },
                child: const Text('Run'),
              ),
            ),
          ],
        ),
        // Ghost.md's branch `voice/assistant-flag` has this card (lib/core/wip.dart), as the page's first; here it is
        // the last, so everything above it stays where `main`'s page has it, which is the page this one is held to
        // rect for rect. Only on a phone, where there is an assistant to be.
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          PaneSection(
            title: 'Work in progress',
            children: [
              SettingRow(
                icon: const AppIcon(Lucide.mic, size: 20),
                label: 'Voice assistant',
                hint: const Text(wipAssistantHint),
                control: ValueListenableBuilder<bool>(
                  valueListenable: wipAssistant,
                  builder: (context, on, _) => GlacierSwitch(ariaLabel: 'Voice assistant', checked: on, onCheckedChange: (next) => unawaited((widget.assistantSwitch ?? switchVoiceAssistant)(next))),
                ),
              ),
            ],
          ),
        // The header toolbar's six versions (Matt, 2026-10-28: "add a developer setting to switch between 5
        // versions"; lib/shell/header_toolbar.dart): this device's own choice, drawn on the bar at once. Last of all,
        // so every card above stands where it did.
        ValueListenableBuilder<String>(
          valueListenable: headerToolbarChoice,
          builder: (context, chosen, _) => PaneSection(
            title: 'Header toolbar',
            description: const Text('Six ways to draw the controls at the top: what stands out, what is grouped, and in what colour. This device only; a choice shows at once.'),
            children: [
              for (final version in HeaderToolbarVersion.values)
                SettingRow(
                  key: ValueKey('developer-header-${version.id}'),
                  label: '${version.number}. ${version.label}',
                  hint: Text(version.hint),
                  control: Pick(checked: chosen == version.id, label: 'Use ${version.label}', onPress: () => headerToolbarChoice.set(version.id)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Play the scene" (`busy = useAnyRunning()`): the bench's run would queue behind a real one and then play against
/// the real engine, so the row is held off, and says why, while the model is on a note. The row hears the runs
/// itself: nothing else on the page is drawn again for one.
class _SceneRow extends StatefulWidget implements PaneRow {
  const _SceneRow({required this.play});
  final VoidCallback? play;

  @override
  State<_SceneRow> createState() => _SceneRowState();
}

class _SceneRowState extends State<_SceneRow> {
  late final ValueListenable<bool> _busy = useAnyRunning();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: _busy,
        builder: (context, busy, _) => SettingRow(
          icon: const AppIcon(Lucide.smartphone, size: 20),
          label: 'Play the scene',
          hint: const Text('Listening again, then the run: loading, reading, thinking, writing, done.'),
          onPress: widget.play ?? () {},
          disabled: widget.play == null || busy,
          disabledReason: busy ? 'The model is on a note. Try again when it is done.' : null,
        ),
      );
}

/// A reset that has to be tapped twice (`ResetRow`): armed for five seconds, then done. A reset that fails says why
/// in its hint.
class _ResetRow extends StatefulWidget implements PaneRow {
  const _ResetRow({required this.label, required this.hint, required this.models, required this.onReset});
  final String label;
  final String hint;
  final bool models;
  final Future<void> Function({required bool models})? onReset;

  @override
  State<_ResetRow> createState() => _ResetRowState();
}

class _ResetRowState extends State<_ResetRow> {
  String? _problem;

  @override
  Widget build(BuildContext context) {
    final reset = widget.onReset;
    return SettingRow(
      label: widget.label,
      hint: Text(_problem ?? widget.hint),
      control: ArmedAction(
        word: 'Reset',
        busyWord: 'Resetting',
        onDo: reset == null ? null : () => reset(models: widget.models),
        onFailed: (why) => setState(() => _problem = why),
      ),
    );
  }
}
