/// A plugin's setup, drawn (setup_flow.dart; Matt, 2026-10-28: "For each of the plugins add a small onboarding flow
/// start with the lovart and Claude plugins walk the user through setting up an account and getting their keys and have
/// the onboarding test setup to make sure it was successful"). The app's own sheet (lib/sheet/sheet.dart): up from the
/// foot of a phone, a window in the middle of the Mac's; over whatever opened it, the Market or the plugin's page.
///
/// It is the walkthrough made small, so it reads as one of the family (lib/guide/guide.dart, the Academy): the dots
/// saying how far along it is in the plugin's own colour, and Skip, along its top; each step's band in the plugin's
/// wash with its sign in the middle and the app's icons floating round it on glass (lib/guide/pages/band.dart
/// [HueBand]); the step's title and words under it; what is done there; and Back and Next at its foot, Next in the
/// plugin's colour. Each kind of step is drawn by its own part here:
/// - an intro's points, each beside a small tile of the wash (Advanced's);
/// - a page to open: a button for each address, the first in colour, handed to the browser (lib/core/open_link.dart,
///   through the plugins' ground), and the address itself written small under them, to type on another device;
/// - the keys: a field each, drawn as dots until Show, with Paste beside it, which reads the clipboard; Next keeps
///   them through the plugin's own save, once each has the shape it should;
/// - the check, run as the step shows: "Checking…", then what it said, a tick or a warning in words (said aloud as it
///   comes), with Check again, and Paste again where the keys were refused;
/// - the end's own part, the settings that matter or a first thing to try.
///
/// The back gesture, Escape and Back step back; at the first step they put the sheet away, as a tap on the dimmed
/// page does. Put away, the setup is left at the step showing and opens there again (setup_flow.dart [SetupMemory]).
/// Skip puts it away as skipped, Done as done.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart' show Clipboard;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../core/preferences.dart';
import '../../guide/narrator.dart' show VoiceOver;
import '../../guide/pages/band.dart';
import '../../guide/voice_button.dart' show VoiceButton;
import '../../market/market_cards.dart' show MarketButton, MarketButtonLook;
import '../../market/market_items.dart' show marketHues;
import '../../settings/kit/settings_type.dart' show pageText;
import '../../sheet/sheet.dart';
import '../github/plain_field.dart';
import '../host.dart' show pluginGround;
import 'setup_flow.dart';
import 'setup_voice.dart' show setupVoice, setupVoiceAsset;

/// The setup's colour as ink on the page: the deep shade on a light page, the bright one on a dark page.
Color setupInk(Tokens t, PluginSetup setup) {
  final (deep, bright) = marketHues[setup.hues.first] ?? marketHues['indigo']!;
  return t.isDark ? bright : deep;
}

/// The wash, deep shades, white reading on it in either theme.
List<Color> setupWash(PluginSetup setup) => [for (final hue in setup.hues) (marketHues[hue] ?? marketHues['indigo']!).$1];

/// What the clipboard holds as text now.
Future<String?> _clipboard() async => (await Clipboard.getData(Clipboard.kTextPlain))?.text;

class PluginSetupSheet extends StatefulWidget {
  const PluginSetupSheet({super.key, required this.setup, required this.onClose, this.fromStart = false, this.memory, this.prefs, this.open, this.paste, this.voice});

  final PluginSetup setup;

  /// Put away, by Skip, Done, the dimmed page or the back gesture: the caller stops building it.
  final VoidCallback onClose;

  /// From the first step whatever was remembered: Run setup again.
  final bool fromStart;

  /// Where it was left; this device's own when null.
  final SetupMemory? memory;

  /// Simple or Advanced; the app's preferences when null.
  final ValueListenable<Preferences>? prefs;

  /// Hands an address to the browser; the plugins' ground's when null (`openLink` in the app, recorded in a test).
  final Future<void> Function(String url)? open;

  /// Reads the clipboard; the system's when null.
  final Future<String?> Function()? paste;

  /// Says each step's words (lib/guide/narrator.dart [VoiceOver]); the device's player when null. The clips are
  /// `assets/plugin-setup/<plugin>-<step>.mp3` (tool/plugin_setup_voice.py), the walkthrough's voice, and its speaker
  /// switch is the walkthrough's too (Matt, 2026-10-28: "The voiceover with elevenlabs isn't working on the lovart
  /// onboarding": the clips had not been made, and nothing played them).
  final VoiceOver? voice;

  @override
  State<PluginSetupSheet> createState() => _PluginSetupSheetState();
}

class _PluginSetupSheetState extends State<PluginSetupSheet> {
  late final SetupMemory _memory = widget.memory ?? SetupMemory();
  late final VoiceOver _voice = widget.voice ?? VoiceOver();
  ValueListenable<Preferences> get _prefs => widget.prefs ?? preferences;
  PluginSetup get _setup => widget.setup;

  /// The step showing, by its id, so a turn to Simple or Advanced keeps the place.
  late String _at;

  /// Whether the person has moved since it opened: a store read late does not move them after.
  bool _moved = false;

  final Map<String, TextEditingController> _fields = {};
  final Set<String> _shown = {};
  final Map<String, String> _problems = {};
  String? _saveProblem;
  bool _saving = false;

  /// The check's last answer, and the run it is for.
  SetupResult? _result;
  bool _checking = false;
  int _run = 0;

  late VoidCallback _stopWatching;

  bool get _simple => _prefs.value.simple;
  List<SetupStep> get _steps => _setup.stepsFor(simple: _simple);

  int get _index {
    final at = _steps.indexWhere((s) => s.id == _at);
    return at < 0 ? 0 : at;
  }

  SetupStep get _step => _steps[_index];

  @override
  void initState() {
    super.initState();
    String start() => _steps[setupStartIndex(_setup, _steps, _memory, fromStart: widget.fromStart)].id;
    _at = start();
    _prefs.addListener(_redraw);
    _voice.addListener(_redraw);
    _stopWatching = _setup.watch(_redraw);
    final prepare = _setup.prepare;
    if (prepare == null) {
      _memory.at(_setup.id, _at);
      _arrive();
      return;
    }
    // The keys read first: a setup left past them opens there only once they are known to be kept, and its check is
    // run once, then.
    void prepared() {
      if (!mounted || _moved) return;
      setState(() => _at = start());
      _memory.at(_setup.id, _at);
      _arrive();
    }

    unawaited(prepare().then((_) => prepared(), onError: (Object _) => prepared()));
  }

  @override
  void dispose() {
    unawaited(_voice.hush());
    _voice.removeListener(_redraw);
    _prefs.removeListener(_redraw);
    _stopWatching();
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  TextEditingController _field(SetupPaste step, SetupField field) => _fields.putIfAbsent('${step.id}/${field.id}', () => TextEditingController()..addListener(_redraw));

  /// What a step does as it shows: its words are said, and the check runs.
  void _arrive() {
    _speak();
    if (_step is SetupCheck) unawaited(_check());
  }

  /// The step's clip, Simple's shorter one where it has one: none where its words have no clip yet.
  void _speak() {
    final name = '${_setup.id}-${_step.id}';
    final clip = _simple && setupVoice.containsKey('$name-simple') ? '$name-simple' : name;
    if (!setupVoice.containsKey(clip)) {
      unawaited(_voice.hush());
      return;
    }
    _voice.say([(asset: setupVoiceAsset(clip), length: null)]);
  }

  void _go(int index) {
    final steps = _steps;
    if (index < 0 || index >= steps.length) return;
    setState(() {
      _moved = true;
      _at = steps[index].id;
      _saveProblem = null;
      _problems.clear();
      if (steps[index] is SetupCheck) _result = null;
    });
    _memory.at(_setup.id, _at);
    _arrive();
  }

  void _back() {
    if (_index > 0) {
      _go(_index - 1);
    } else {
      _close();
    }
  }

  /// Put away where it is: it opens here again.
  void _close() {
    _run += 1;
    unawaited(_voice.hush());
    _memory.at(_setup.id, _at);
    widget.onClose();
  }

  void _skip() {
    _run += 1;
    unawaited(_voice.hush());
    _memory.end(_setup.id, _at, SetupEnd.skipped);
    widget.onClose();
  }

  void _finish() {
    unawaited(_voice.hush());
    _memory.end(_setup.id, _at, SetupEnd.done);
    widget.onClose();
  }

  Future<void> _check() async {
    final step = _step;
    if (step is! SetupCheck) return;
    final run = ++_run;
    setState(() {
      _checking = true;
      _result = null;
    });
    SetupResult result;
    try {
      result = await step.run();
    } catch (failure) {
      // A check says its failures in words; one that throws is said as it is.
      result = SetupResult.failed('$failure');
    }
    if (!mounted || run != _run) return;
    setState(() {
      _checking = false;
      _result = result;
    });
  }

  Future<void> _save(SetupPaste step) async {
    if (_saving) return;
    final values = <String, String>{};
    final problems = <String, String>{};
    for (final field in step.fields) {
      final text = _field(step, field).text.trim();
      final problem = text.isEmpty ? 'Paste the ${field.label.toLowerCase()} here first.' : field.shape?.call(text);
      if (problem != null) problems[field.id] = problem;
      values[field.id] = text;
    }
    setState(() {
      _problems
        ..clear()
        ..addAll(problems);
      _saveProblem = null;
    });
    if (problems.isNotEmpty) return;
    setState(() => _saving = true);
    String? wrong;
    try {
      wrong = await step.save(values);
    } catch (failure) {
      wrong = 'They couldn’t be kept: $failure';
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveProblem = wrong;
    });
    if (wrong != null) return;
    // Kept where the plugin keeps them: the fields let go of them.
    for (final field in step.fields) {
      _field(step, field).clear();
    }
    _shown.removeWhere((id) => id.startsWith('${step.id}/'));
    _go(_index + 1);
  }

  Future<void> _paste(TextEditingController into) async {
    String? text;
    try {
      text = await (widget.paste ?? _clipboard)();
    } catch (_) {
      text = null;
    }
    if (!mounted || text == null || text.trim().isEmpty) return;
    into.text = text.trim();
    into.selection = TextSelection.collapsed(offset: into.text.length);
  }

  void _open(String url) => unawaited((widget.open ?? pluginGround.open)(url).catchError((Object _) {}));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final steps = _steps;
    final index = _index;
    final step = steps[index];
    final simple = _simple;
    final last = index == steps.length - 1;
    final ink = setupInk(t, _setup);
    final deep = setupWash(_setup).first;
    final screen = MediaQuery.sizeOf(context);
    // A band, not a poster: a sixth of the window's height, and less at the end, where the settings are; so the step's
    // words and its buttons fit under it in the sheet on a phone and in the Mac's window alike.
    final bandHigh = (screen.height * 0.17).clamp(96.0, 150.0) * (step is SetupDone ? 0.72 : 1);

    final top = Row(
      children: [
        Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: SetupDots(at: index, count: steps.length, color: ink))),
        if (_voice.output != null) ...[
          VoiceButton(key: const ValueKey('setup-voice'), off: _voice.muted, onPressed: () => _voice.setMuted(!_voice.muted), side: t.space(8), icon: 18),
          SizedBox(width: t.space(2)),
        ],
        if (!last)
          MarketButton(key: const ValueKey('setup-skip'), label: 'Skip', semantics: 'Skip setting up ${_setup.name}', look: MarketButtonLook.ring, onPress: _skip)
        else
          MarketButton(key: const ValueKey('setup-close'), label: 'Close', semantics: 'Close', look: MarketButtonLook.ring, onPress: _finish),
      ],
    );

    final band = HueBand(
      key: ValueKey('setup-band-${step.id}'),
      colours: setupWash(_setup),
      height: bandHigh,
      tiles: [for (final icon in step.tiles.isEmpty ? _setup.tiles : step.tiles) bandIcon(icon)],
      sign: (height, width) {
        final mark = _setup.mark;
        final side = math.min(height * 0.46, width * 0.36);
        if (step is SetupIntro && step.mark && mark != null) return bandDisc(step.icon, height: height, width: width, child: mark(side * 0.5));
        if (step is SetupCheck && _result != null) {
          final sign = switch (_result!.kind) {
            SetupCheckKind.ok => Lucide.circleCheck,
            SetupCheckKind.warn => Lucide.triangleAlert,
            SetupCheckKind.failed => Lucide.circleAlert,
          };
          return bandDisc(sign, height: height, width: width);
        }
        return bandDisc(step.icon, height: height, width: width);
      },
    );

    final title = Semantics(
      header: true,
      child: Text(step.title, key: const ValueKey('setup-title'), style: pageText(t, t.fontSize('xl'), weight: 'bold', height: 1.2, color: t.color('app-ink'))),
    );
    final words = Text(_setup.wordsOf(step, simple: simple), key: const ValueKey('setup-words'), style: pageText(t, t.fontSize('md'), height: 1.45, color: t.color('app-ink-2')));

    final body = switch (step) {
      SetupIntro() => simple || step.points.isEmpty ? null : _points(t, step),
      SetupOpen() => _links(t, step, deep),
      SetupPaste() => _pasteBody(t, step),
      SetupCheck() => _checkBody(t, step, ink),
      SetupDone() => step.body?.call(context, simple),
    };

    final (String label, VoidCallback? next) = switch (step) {
      SetupPaste() => (_saving ? 'Keeping…' : 'Check', _saving || step.fields.any((f) => _field(step, f).text.trim().isEmpty) ? null : () => unawaited(_save(step))),
      SetupCheck() => _checking || _result == null ? ('Checking…', null) : (_result?.ok ?? false) ? ('Next', () => _go(index + 1)) : ('Check again', () => unawaited(_check())),
      SetupDone() => ('Done', _finish),
      _ => (index == 0 ? 'Start' : 'Next', () => _go(index + 1)),
    };

    // Next shrinks to fit rather than run off a narrow phone, or a phone with its text made large.
    final foot = Row(
      mainAxisAlignment: index > 0 ? MainAxisAlignment.spaceBetween : MainAxisAlignment.end,
      spacing: t.space(2),
      children: [
        if (index > 0) MarketButton(key: const ValueKey('setup-back'), label: 'Back', look: MarketButtonLook.ring, large: true, onPress: _back),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: MarketButton(key: const ValueKey('setup-next'), label: label, look: MarketButtonLook.filled, color: deep, large: true, onPress: next),
          ),
        ),
      ],
    );

    return Sheet(
      label: 'Set up ${_setup.name}',
      onClose: _close,
      onBack: _back,
      children: [
        Column(
          key: ValueKey('setup-${_setup.id}-${step.id}'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            top,
            SizedBox(height: t.space(3)),
            band,
            SizedBox(height: t.space(5)),
            title,
            SizedBox(height: t.space(2)),
            words,
            if (body != null) ...[SizedBox(height: t.space(4)), body],
            SizedBox(height: t.space(6)),
            foot,
          ],
        ),
      ],
    );
  }

  Widget _points(Tokens t, SetupIntro step) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: t.space(2),
        children: [
          for (final (icon, words) in step.points)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: t.space(3),
              children: [
                SetupTile(setup: _setup, icon: icon, size: t.lenOf('1.9rem')),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: t.space(1)),
                    child: Text(words, style: pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink'))),
                  ),
                ),
              ],
            ),
        ],
      );

  Widget _links(Tokens t, SetupOpen step, Color deep) {
    final quiet = pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('app-ink-3'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: t.space(2),
          runSpacing: t.space(2),
          children: [
            for (final (at, link) in step.links.indexed)
              MarketButton(
                key: ValueKey('setup-open-$at'),
                label: link.label,
                semantics: '${link.label}, in the browser',
                icon: Lucide.externalLink,
                look: at == 0 ? MarketButtonLook.filled : MarketButtonLook.ring,
                color: at == 0 ? deep : null,
                large: true,
                onPress: () => _open(link.url),
              ),
          ],
        ),
        SizedBox(height: t.space(2)),
        Text(step.links.map((l) => shortAddress(l.url)).join(' · '), key: const ValueKey('setup-addresses'), style: quiet),
      ],
    );
  }

  Widget _pasteBody(Tokens t, SetupPaste step) {
    final problem = pageText(t, t.fontSize('sm'), height: 1.4, color: t.color('glacier-red-9'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: t.space(3),
      children: [
        for (final field in step.fields) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: t.space(1),
            children: [
              Text(field.label, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))),
              Row(
                spacing: t.space(1),
                children: [
                  Expanded(
                    child: PlainField(
                      key: ValueKey('setup-field-${field.id}'),
                      label: field.label,
                      controller: _field(step, field),
                      placeholder: field.placeholder,
                      secret: !_shown.contains('${step.id}/${field.id}'),
                      onSubmitted: field == step.fields.last ? () => unawaited(_save(step)) : null,
                    ),
                  ),
                  SetupIconButton(key: ValueKey('setup-paste-${field.id}'), icon: Lucide.clipboardPaste, label: 'Paste the ${field.label.toLowerCase()}', onPress: () => unawaited(_paste(_field(step, field)))),
                  SetupIconButton(
                    key: ValueKey('setup-show-${field.id}'),
                    icon: _shown.contains('${step.id}/${field.id}') ? Lucide.eyeOff : Lucide.eye,
                    label: '${_shown.contains('${step.id}/${field.id}') ? 'Hide' : 'Show'} the ${field.label.toLowerCase()}',
                    onPress: () => setState(() {
                      final id = '${step.id}/${field.id}';
                      if (!_shown.remove(id)) _shown.add(id);
                    }),
                  ),
                ],
              ),
              if (_problems[field.id] case final said?) Semantics(liveRegion: true, child: Text(said, key: ValueKey('setup-problem-${field.id}'), style: problem)),
            ],
          ),
        ],
        if (_saveProblem case final said?) Semantics(liveRegion: true, child: Text(said, key: const ValueKey('setup-save-problem'), style: problem)),
      ],
    );
  }

  Widget _checkBody(Tokens t, SetupCheck step, Color ink) {
    final result = _result;
    final (LucideIcon icon, Color colour, String said) = switch (result) {
      null => (Lucide.loaderCircle, t.color('app-ink-3'), step.checking),
      SetupResult(kind: SetupCheckKind.ok) => (Lucide.circleCheck, ink, result.words),
      SetupResult(kind: SetupCheckKind.warn) => (Lucide.triangleAlert, t.color('glacier-amber-11'), result.words),
      SetupResult() => (Lucide.circleAlert, t.color('glacier-red-9'), result.words),
    };
    final paste = _steps.indexWhere((s) => s is SetupPaste);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: t.space(3),
      children: [
        Semantics(
          liveRegion: true,
          container: true,
          child: Container(
            key: const ValueKey('setup-result'),
            padding: EdgeInsets.all(t.space(3)),
            decoration: BoxDecoration(color: colour.withValues(alpha: t.isDark ? 0.16 : 0.08), borderRadius: BorderRadius.circular(t.radius('lg'))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: t.space(3),
              children: [
                result == null ? SetupTurning(child: AppIcon(icon, size: 20, color: colour)) : AppIcon(icon, size: 20, color: colour),
                Expanded(child: Text(said, key: const ValueKey('setup-result-words'), style: pageText(t, t.fontSize('md'), weight: 'medium', height: 1.4, color: t.color('app-ink')))),
              ],
            ),
          ),
        ),
        if (result != null && (result.pasteAgain || result.link != null))
          Wrap(
            spacing: t.space(2),
            runSpacing: t.space(2),
            children: [
              if (result.pasteAgain && paste >= 0) MarketButton(key: const ValueKey('setup-paste-again'), label: 'Paste again', icon: Lucide.clipboardPaste, look: MarketButtonLook.ring, large: true, onPress: () => _go(paste)),
              if (result.link case final link?) MarketButton(key: const ValueKey('setup-result-link'), label: link.label, semantics: '${link.label}, in the browser', icon: Lucide.externalLink, look: MarketButtonLook.ring, large: true, onPress: () => _open(link.url)),
            ],
          ),
      ],
    );
  }
}

/// An address as it is typed: no scheme, no `www.`, no slash at its end. `https://console.anthropic.com/settings/keys`
/// is `console.anthropic.com/settings/keys`.
String shortAddress(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final host = uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
  final path = uri.path == '/' ? '' : uri.path.replaceFirst(RegExp(r'/$'), '');
  return '$host$path';
}

/// Where the reader is, as the walkthrough's dots: a ring still to come, a small dot passed, a longer bar for the
/// step showing, in the plugin's colour.
class SetupDots extends StatelessWidget {
  const SetupDots({super.key, required this.at, required this.count, required this.color});
  final int at;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final subtle = t.color('glacier-text-subtle');
    final turn = t.reducedMotion ? Duration.zero : const Duration(milliseconds: 240);
    return Semantics(
      key: const ValueKey('setup-dots'),
      label: 'Step ${at + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: turn,
                curve: t.curve('glacier-ease-out'),
                width: i == at ? 18 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == at ? color : (i < at ? subtle : subtle.withValues(alpha: 0)),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: i == at ? color : subtle, width: t.len('app-line')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small tile of the setup's wash with a white icon on it, or its mark: an intro's points, the plugin page's card.
class SetupTile extends StatelessWidget {
  const SetupTile({super.key, required this.setup, required this.size, this.icon});
  final PluginSetup setup;
  final double size;

  /// The icon; the plugin's mark (or its first tile's icon) where null.
  final LucideIcon? icon;

  @override
  Widget build(BuildContext context) {
    final colours = setupWash(setup);
    final mark = setup.mark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colours.length > 1 ? colours : [colours.first, colours.first]),
        boxShadow: [BoxShadow(color: colours.first.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ExcludeSemantics(child: icon != null || mark == null ? bandIcon(icon ?? setup.tiles.firstOrNull ?? Lucide.sparkles)(size) : mark(size * 0.5)),
    );
  }
}

/// A square button with an icon alone, named for a screen reader: Paste, Show.
class SetupIconButton extends StatelessWidget {
  const SetupIconButton({super.key, required this.icon, required this.label, required this.onPress});
  final LucideIcon icon;
  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.space(10);
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: label,
      builder: (context, state) => GlacierFocusRing(
        visible: state.focused,
        radius: t.radius('md'),
        child: Container(
          width: side,
          height: side,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: state.pressed ? t.color('app-wash') : t.color('glacier-surface'),
            borderRadius: BorderRadius.circular(t.radius('md')),
            border: Border.all(color: t.color('glacier-border'), width: t.len('glacier-hairline')),
          ),
          child: AppIcon(icon, size: 18, color: t.color('app-ink-2')),
        ),
      ),
    );
  }
}

/// Its child turning, once a second and a bit; still for a person who asked for less motion.
class SetupTurning extends StatefulWidget {
  const SetupTurning({super.key, required this.child});
  final Widget child;

  @override
  State<SetupTurning> createState() => _SetupTurningState();
}

class _SetupTurningState extends State<SetupTurning> with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.tokens.reducedMotion) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(turns: _turn, child: widget.child);
}
