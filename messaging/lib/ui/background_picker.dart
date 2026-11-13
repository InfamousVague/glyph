import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../backgrounds.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../sms.dart';
import 'common.dart';

/// Choosing what is behind the messages (lib/backgrounds.dart): for every chat (Settings › Chat background), or for
/// one conversation (its header › Chat background), which may also wear every chat's. A small conversation at the
/// top shows the choice as it will look.
class BackgroundPicker extends StatefulWidget {
  const BackgroundPicker({super.key, this.thread, this.who});

  /// The conversation whose background this is; null for every chat's.
  final int? thread;

  /// Who the conversation is with, for the page's title.
  final String? who;

  @override
  State<BackgroundPicker> createState() => _BackgroundPickerState();
}

class _BackgroundPickerState extends State<BackgroundPicker> {
  bool _mixing = false;
  bool _busy = false;

  String get _key => widget.thread == null ? 'chat_bg' : ChatBackground.threadKey(widget.thread!);

  /// The name the app keeps this one's picture under.
  String get _file => widget.thread == null ? 'all' : 't${widget.thread}';

  /// [next] null is "the same as every chat" (a conversation's only).
  void _set(ChatBackground? next) {
    final app = AppState.of(context);
    final before = ChatBackground.parse(app.choice(_key, ''));
    app.set(_key, next?.raw ?? '');
    // A picture no longer worn is not kept.
    if (before.kind == 'image' && next?.kind != 'image') Sms.instance.deleteBackground(_file);
  }

  Future<void> _pickPicture() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final uris = await Sms.instance.pickImages();
      if (uris.isEmpty) return;
      final path = await Sms.instance.importBackground(uris.first, _file);
      if (!mounted) return;
      if (path == null) {
        toast(context, 'That picture couldn\'t be read.', tone: GlacierToastTone.danger);
      } else {
        _set(ChatBackground('image', path));
      }
    } catch (e) {
      if (mounted) toast(context, 'Couldn\'t use that picture: $e', tone: GlacierToastTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.of(context);
    final thread = widget.thread;
    final every = ChatBackground.everyChat(app);
    final own = thread == null ? every : ChatBackground.own(app, thread);
    final worn = own ?? every;
    final hasPalette = PhonePalette.current != null;
    bool chosen(ChatBackground b) => own != null && own.kind == b.kind && own.value == b.value;

    return GlacierScope(
      attrs: const {'hue': 'purple'},
      child: Builder(builder: (context) {
        final t = context.tokens;
        return SettingsPaneScope(
          finder: SettingsFinder(),
          child: GhostPage(
            title: thread == null ? 'Chat background' : (widget.who == null ? 'Background' : 'Background with ${widget.who}'),
            body: ListView(
              padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
              children: [
                BackgroundPreview(background: worn),
                SizedBox(height: t.space(5)),
                PaneSection(
                  footer: thread == null
                      ? const Text('Behind the messages of every conversation. A conversation can have one of its own, from its header.')
                      : const Text('Only for this conversation, and only on this phone: texting has no way to send a background to the other person.'),
                  children: [
                    if (thread != null)
                      SettingRow(
                        label: 'Same as every chat',
                        hint: Text(every.label),
                        control: Pick(checked: own == null, label: 'Use every chat\'s background', onPress: () => _set(null)),
                      ),
                    SettingRow(
                      label: 'None',
                      hint: const Text('The plain page.'),
                      control: Pick(checked: chosen(ChatBackground.none), label: 'No background', onPress: () => _set(ChatBackground.none)),
                    ),
                    SettingRow(
                      label: 'Match my wallpaper',
                      hint: const Text('The colours Android takes from this phone\'s wallpaper, which the phone\'s own apps wear too. It changes when the wallpaper does.'),
                      disabledReason: hasPalette ? null : 'Needs Android 12 or later.',
                      control: Pick(checked: chosen(ChatBackground.wallpaper), label: 'Match my wallpaper', onPress: () => _set(ChatBackground.wallpaper)),
                    ),
                  ],
                ),
                SizedBox(height: t.space(5)),
                PaneSection(title: 'Washes', children: [
                  SettingRowBox(
                    child: Wrap(spacing: t.space(3), runSpacing: t.space(3), children: [
                      for (final p in chatPresets)
                        _Swatch(
                          label: p.name,
                          top: t.isDark ? p.darkTop : p.lightTop,
                          bottom: t.isDark ? p.darkBottom : p.lightBottom,
                          chosen: chosen(ChatBackground('preset', p.id)),
                          onPress: () => _set(ChatBackground('preset', p.id)),
                        ),
                    ]),
                  ),
                ]),
                SizedBox(height: t.space(5)),
                PaneSection(title: 'A colour', children: [
                  SettingRowBox(
                    child: Wrap(spacing: t.space(3), runSpacing: t.space(3), children: [
                      for (final hex in chatColors)
                        _Swatch(
                          top: ChatBackground('color', hex).colors(false)!.$1,
                          bottom: ChatBackground('color', hex).colors(false)!.$1,
                          chosen: chosen(ChatBackground('color', hex)),
                          onPress: () => _set(ChatBackground('color', hex)),
                          semanticLabel: 'Colour $hex',
                        ),
                    ]),
                  ),
                  SettingRow(
                    icon: const AppIcon(Lucide.palette, size: 18),
                    label: 'Mix a colour',
                    control: GlacierSwitch(checked: _mixing, onCheckedChange: (on) => setState(() => _mixing = on), ariaLabel: 'Mix a colour'),
                  ),
                  if (_mixing)
                    SettingRowBox(
                      child: GlacierColorPicker(
                        defaultValue: own?.kind == 'color' ? own!.value : '#DCE8FB',
                        // Kept as the drag ends, not on every frame of it.
                        onChangeEnd: (hex) => _set(ChatBackground('color', hex)),
                      ),
                    ),
                ]),
                SizedBox(height: t.space(5)),
                PaneSection(
                  title: 'A picture',
                  footer: const Text('A copy is kept by the app on this phone. It is drawn under a light veil so messages stay readable.'),
                  children: [
                    SettingRow(
                      icon: const AppIcon(Lucide.imagePlus, size: 18),
                      label: own?.kind == 'image' ? 'Choose another picture' : 'Choose a picture',
                      hint: const Text('From your photos.'),
                      onPress: _pickPicture,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// A few bubbles over [background], as a conversation will wear it.
class BackgroundPreview extends StatelessWidget {
  const BackgroundPreview({super.key, required this.background});
  final ChatBackground background;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = AppState.of(context);
    final (mine, onMine) = myBubble(t, app);
    final theirs = theirBubble(t, onBackground: !background.isNone);
    Widget bubble(String text, {required bool out}) => Align(
          alignment: out ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: EdgeInsets.only(top: t.space(1)),
            padding: EdgeInsets.symmetric(horizontal: t.space(3) + 2, vertical: t.space(2)),
            decoration: BoxDecoration(color: out ? mine : theirs, borderRadius: BorderRadius.circular(t.lenOf('1.15rem'))),
            child: Text(text, style: pageText(t, t.fontSize('md') * app.textScale, color: out ? onMine : t.color('app-ink'), height: 1.35)),
          ),
        );
    return Semantics(
      label: 'How it looks: ${background.label}',
      child: ExcludeSemantics(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: t.color('glacier-bg'), borderRadius: BorderRadius.circular(t.radius('lg'))),
          // The rule is drawn over the background, so it rings a picture as it rings the plain page.
          foregroundDecoration: BoxDecoration(borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: t.color('app-rule'))),
          child: RepaintBoundary(
            child: Stack(children: [
              Positioned.fill(child: ChatBackgroundLayer(background: background)),
              Padding(
                padding: EdgeInsets.all(t.space(3)),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Center(child: OnBackground(busy: background.busy, child: Text('Today', style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: t.color('app-ink-3'))))),
                  SizedBox(height: t.space(1)),
                  bubble('Are we still on for tonight?', out: false),
                  bubble('Yes! See you at 7', out: true),
                  bubble('Perfect 🎉', out: false),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.top, required this.bottom, required this.chosen, required this.onPress, this.label, this.semanticLabel});
  final Color top;
  final Color bottom;
  final bool chosen;
  final VoidCallback onPress;
  final String? label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = t.lenOf('3.25rem');
    return GlacierPressable(
      onPressed: onPress,
      semanticLabel: '${semanticLabel ?? label}${chosen ? ', chosen' : ''}',
      builder: (context, state) => AnimatedScale(
        scale: state.pressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 120),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: side,
            height: side,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(t.lenOf('0.9rem')),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [top, bottom]),
              border: Border.all(color: chosen ? settingsHue(t) : t.color('app-rule'), width: chosen ? 2.5 : 1),
            ),
            alignment: Alignment.center,
            child: chosen ? AppIcon(Lucide.check, size: 18, strokeWidth: 2.6, wash: false, color: settingsHue(t)) : null,
          ),
          if (label != null) ...[
            SizedBox(height: t.space(1)),
            Text(label!, style: pageText(t, t.fontSize('xs'), weight: chosen ? 'semibold' : 'regular', color: t.color(chosen ? 'app-ink' : 'app-ink-2'))),
          ],
        ]),
      ),
    );
  }
}
