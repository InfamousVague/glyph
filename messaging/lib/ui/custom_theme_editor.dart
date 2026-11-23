/// Settings › Appearance › Make your own look (GMFB-41, from the Uplink gap review: "Customization: custom CSS-style
/// themes"): four colours, light or dark, and a name, seen as they are changed, then kept and used. Shared as a short
/// code, and taken in from one pasted (lib/custom_theme.dart refuses anything that is not a look's colours and name).
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../custom_theme.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import 'common.dart';

Widget _icon(LucideIcon icon) => AppIcon(icon, size: 18);

/// A look of one's own drawn small from its four colours: its page, a bubble from someone else on the surface's
/// colour, and one of yours in the accent. Drawn straight from the colours, so the editor's preview follows each
/// change at once.
class CustomThemePreview extends StatelessWidget {
  const CustomThemePreview({super.key, required this.theme, this.width, this.large = false});
  final CustomTheme theme;
  final double? width;

  /// The editor's: taller, with a line of words on the page too.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = large ? t.fontSize('sm') : t.fontSize('xs');
    final words = t.textAt(size, color: theme.ink);
    final strut = StrutStyle(fontSize: size, height: 1.25, forceStrutHeight: true);
    Widget line(String text, {required bool out}) => Align(
          alignment: out ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: t.space(large ? 3 : 1) + 2, vertical: t.space(large ? 2 : 1)),
            decoration: BoxDecoration(color: out ? theme.accent : theme.surface, borderRadius: BorderRadius.circular(t.radius(large ? 'lg' : 'md'))),
            child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, strutStyle: strut, style: out ? words.copyWith(color: theme.onAccent) : words),
          ),
        );
    return Container(
      width: width,
      padding: EdgeInsets.all(large ? t.space(4) : t.space(1) + 2),
      color: theme.paper,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (large) ...[
          Text(theme.name.trim().isEmpty ? 'Your own look' : theme.name.trim(), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textAt(t.fontSize('md'), weight: 'semibold', color: theme.ink)),
          SizedBox(height: t.space(3)),
          line('Are we still on for Friday?', out: false),
          SizedBox(height: t.space(2)),
          line('Yes! See you at 7', out: true),
        ] else ...[
          line('Free?', out: false),
          SizedBox(height: t.space(1)),
          line('Yes!', out: true),
        ],
      ]),
    );
  }
}

/// Copies [theme]'s code, to paste to anyone.
void shareTheme(BuildContext context, CustomTheme theme) {
  Clipboard.setData(ClipboardData(text: theme.code));
  toast(context, 'Copied ${theme.name}\'s code. Whoever you send it to pastes it in Settings › Appearance.');
}

/// Takes in a look from a code copied: shown in the editor first, to keep or leave. Said plainly where what was copied
/// is not a look's code.
Future<void> pasteTheme(BuildContext context, AppState app) async {
  final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  if (!context.mounted) return;
  final theme = CustomTheme.decode(text);
  if (theme == null) {
    toast(context, text.trim().isEmpty ? 'Copy a look\'s code first, then paste it here' : 'That isn\'t a look\'s code. A code starts GT1.', tone: GlacierToastTone.danger);
    return;
  }
  await push<void>(context, (_) => CustomThemeEditor(app: app, start: theme, pasted: true));
}

/// What a look of one's own offers when pressed while it is in use: change it, share it, remove it.
void themeMenu(BuildContext context, AppState app, CustomTheme theme) => showChoices(context, title: theme.name, choices: [
      Choice('Edit', Lucide.pencil, () => push<void>(context, (_) => CustomThemeEditor(app: app, start: theme, replacing: theme))),
      Choice('Copy its code to share', Lucide.share2, () => shareTheme(context, theme)),
      Choice('Remove', Lucide.trash2, () {
        CustomTheme.remove(app, theme);
        toast(context, '${theme.name} removed');
      }),
    ]);

/// The four colours, each with what it colours.
enum _Part {
  paper('Background', 'The page behind everything'),
  surface('Surface', 'Cards, fields and other people\'s bubbles'),
  ink('Text', 'The words'),
  accent('Accent', 'Your bubbles, Send and what is chosen');

  const _Part(this.label, this.hint);
  final String label, hint;
}

/// Making a look, or changing one ([replacing]); [start] is where it begins: the colours on the screen now for a new
/// one, a code's for one [pasted].
class CustomThemeEditor extends StatefulWidget {
  const CustomThemeEditor({super.key, required this.app, this.start, this.replacing, this.pasted = false});
  final AppState app;
  final CustomTheme? start;
  final CustomTheme? replacing;
  final bool pasted;

  @override
  State<CustomThemeEditor> createState() => _CustomThemeEditorState();
}

class _CustomThemeEditorState extends State<CustomThemeEditor> {
  CustomTheme? _theme;
  late final TextEditingController _name = TextEditingController(text: widget.start?.name ?? '')..addListener(_named);

  /// The colour whose mixer is open, if any.
  _Part? _open;

  void _named() => setState(() => _theme = _theme?.copyWith(name: _name.text));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A new look starts from the colours on the screen now.
    if (_theme == null) {
      final t = context.tokens;
      _theme = widget.start ??
          CustomTheme(name: '', dark: t.isDark, paper: t.color('app-paper'), surface: t.color('app-paper-2'), ink: t.color('app-ink'), accent: t.color('app-accent'));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Color _of(CustomTheme theme, _Part p) => switch (p) { _Part.paper => theme.paper, _Part.surface => theme.surface, _Part.ink => theme.ink, _Part.accent => theme.accent };

  void _set(_Part p, String text) {
    final h = text.replaceFirst('#', '');
    final v = int.tryParse(h, radix: 16);
    if (h.length != 6 || v == null) return;
    final c = Color(0xFF000000 | v);
    setState(() => _theme = switch (p) {
          _Part.paper => _theme!.copyWith(paper: c),
          _Part.surface => _theme!.copyWith(surface: c),
          _Part.ink => _theme!.copyWith(ink: c),
          _Part.accent => _theme!.copyWith(accent: c),
        });
  }

  void _save() {
    final theme = _theme!.copyWith(name: _name.text.trim());
    if (theme.problem != null) return;
    CustomTheme.save(widget.app, theme, replacing: widget.replacing);
    toast(context, '${theme.name} is your look now');
    Navigator.of(context).maybePop();
  }

  /// Colours to start from, the same for every part: the page's whites and blacks and a few clear hues.
  static const _presets = ['#FFFFFF', '#F4F1EA', '#E8EEF7', '#1E1F24', '#0B0B0C', '#101A2B', '#0C7F7A', '#4F5BD5', '#C2410C', '#BE185D', '#15803D', '#E5A152'];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final theme = _theme!;
    final problem = theme.problem;
    final editing = widget.replacing != null;
    return GhostPage(
      title: editing ? 'Edit ${widget.replacing!.name}' : (widget.pasted ? 'A look someone shared' : 'Make your own look'),
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8)),
          children: [
            PaneSection(
              description: Text(widget.pasted ? 'This is how it looks. Keep it to use it; you can change it first.' : 'Choose four colours and see them here as you go.'),
              children: [
                SettingRowBox(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(t.radius('lg')),
                    child: CustomThemePreview(key: const ValueKey('custom-theme-preview'), theme: theme, large: true),
                  ),
                ),
              ],
            ),
            SizedBox(height: t.space(5)),
            PaneSection(title: 'Name', children: [
              SettingRowBox(
                child: GlacierInput(
                  key: const ValueKey('custom-theme-name'),
                  controller: _name,
                  placeholder: 'What to call it',
                  ariaLabel: 'Name',
                  autoCapitalize: TextCapitalization.words,
                  maxLength: CustomTheme.nameMost,
                ),
              ),
            ]),
            SizedBox(height: t.space(5)),
            PaneSection(
              title: 'Colours',
              footer: problem == null || problem == 'Give it a name' ? null : Text(problem, key: const ValueKey('custom-theme-problem'), style: TextStyle(color: t.colorOf('#c27c0e'))),
              children: [
                SettingRow(
                  icon: _icon(Lucide.sunMoon),
                  label: 'Brightness',
                  layout: SettingRowLayout.stacked,
                  control: GlacierSegmentedControl(
                    fullWidth: true,
                    value: theme.dark ? 'dark' : 'light',
                    onValueChange: (v) => setState(() => _theme = theme.copyWith(dark: v == 'dark')),
                    options: const [
                      GlacierSegmentedOption(value: 'light', label: Text('Light')),
                      GlacierSegmentedOption(value: 'dark', label: Text('Dark')),
                    ],
                  ),
                ),
                for (final p in _Part.values) ...[
                  SettingRow(
                    key: ValueKey('custom-theme-${p.name}'),
                    label: p.label,
                    hint: Text(p.hint),
                    value: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(hex(_of(theme, p)), style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), mono: true)),
                      SizedBox(width: t.space(2)),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(color: _of(theme, p), shape: BoxShape.circle, border: Border.all(color: t.color('app-rule'))),
                      ),
                    ]),
                    onPress: () => setState(() => _open = _open == p ? null : p),
                  ),
                  if (_open == p)
                    SettingRowBox(
                      child: GlacierColorPicker(
                        key: ValueKey('custom-theme-picker-${p.name}'),
                        value: hex(_of(theme, p)),
                        presets: _presets,
                        onValueChange: (h) => _set(p, h),
                      ),
                    ),
                ],
              ],
            ),
            SizedBox(height: t.space(5)),
            PaneSection(children: [
              SettingRow(
                key: const ValueKey('custom-theme-save'),
                icon: _icon(Lucide.check),
                label: editing ? 'Save and use it' : 'Keep it and use it',
                disabled: problem != null,
                disabledReason: problem,
                onPress: _save,
              ),
              if (problem == null) SettingRow(icon: _icon(Lucide.share2), label: 'Copy its code to share', onPress: () => shareTheme(context, theme.copyWith(name: _name.text.trim()))),
              if (editing)
                SettingRow(
                  icon: _icon(Lucide.trash2),
                  label: 'Remove it',
                  onPress: () {
                    CustomTheme.remove(widget.app, widget.replacing!);
                    toast(context, '${widget.replacing!.name} removed');
                    Navigator.of(context).maybePop();
                  },
                ),
            ]),
          ],
        ),
      ),
    );
  }
}
