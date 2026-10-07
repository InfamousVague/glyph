import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/preferences.dart';
import '../app/widgets.dart';

/// Stage one's screen: every component of the kit the app uses, live, on the phone, over the app's own theme. The
/// controls at the top are the app's preferences, so the whole page answers to them as Settings › Appearance does.
/// Replaced by the app's own home once the shell is ported.
class KitGallery extends StatefulWidget {
  const KitGallery({super.key});

  @override
  State<KitGallery> createState() => _KitGalleryState();
}

class _KitGalleryState extends State<KitGallery> {
  bool _glass = false;
  bool _small = true;
  double _progress = 35;
  String _segment = 'board';
  bool _palette = false;
  final List<String> _pills = ['Work', 'Home', 'HelloTrade'];
  Motion _motion = Motion.riseIn;
  int _replay = 0;
  String _name = '';

  static const _commands = [
    CommandDescriptor(id: 'new', label: 'New note', group: 'Notes', keywords: 'write create', shortcut: '⌘N'),
    CommandDescriptor(id: 'canvas', label: 'New canvas', group: 'Notes', keywords: 'cards draw'),
    CommandDescriptor(id: 'notebook', label: 'New notebook', group: 'Notes'),
    CommandDescriptor(id: 'weekend', label: 'Open Weekend trip', group: 'Open', keywords: 'cabin'),
    CommandDescriptor(id: 'launch', label: 'Open Launch week', group: 'Open', keywords: 'board'),
    CommandDescriptor(id: 'sprint', label: 'Open This sprint', group: 'Open', keywords: 'query tickets'),
    CommandDescriptor(id: 'settings', label: 'Settings', group: 'Go to', shortcut: '⌘'),
    CommandDescriptor(id: 'sync', label: 'Sync now', group: 'Go to', disabled: true),
  ];

  void _toast(GlacierToastTone tone, String words) => GlacierToast.of(context).toast(tone: tone, message: Text(words));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = MediaQuery.of(context);
    final prefs = preferences.value;
    final gutter = t.len('app-gutter');
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(gutter, media.padding.top + t.space(8), gutter, media.padding.bottom + t.space(16)),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: t.len('glacier-container-md')),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AppEyebrow('Ghost Flutter · stage 1'),
                    SizedBox(height: t.space(2)),
                    Text(
                      'The kit',
                      style: t.text('2xl', weight: 'bold').copyWith(
                            fontSize: t.len('app-title'),
                            letterSpacing: t.len('app-tracking-title', em: t.len('app-title')),
                            height: 1.15,
                          ),
                    ),
                    SizedBox(height: t.space(2)),
                    Text(
                      'Every Glacier component Ghost.md uses, ported to Flutter and drawn from the web app’s own tokens.',
                      style: t.text('md', color: t.color('glacier-text-muted')),
                    ),

                    _Section('Theme', [
                      GlacierSegmentedControl(
                        ariaLabel: 'Theme',
                        fullWidth: true,
                        value: AppPreferences.presets.containsKey(prefs.theme) ? 'system' : prefs.theme,
                        onValueChange: (v) => preferences.value = prefs.copyWith(theme: v),
                        options: const [
                          GlacierSegmentedOption(value: 'system', label: Text('System')),
                          GlacierSegmentedOption(value: 'light', label: Text('Light')),
                          GlacierSegmentedOption(value: 'dark', label: Text('Dark')),
                        ],
                      ),
                      Wrap(
                        spacing: t.space(2),
                        runSpacing: t.space(2),
                        children: [
                          for (final name in const ['dawn', 'boreal', 'ember'])
                            GlacierPressable(
                              onPressed: () => preferences.value = prefs.copyWith(theme: prefs.theme == name ? 'system' : name),
                              pressScale: PressScale.chip,
                              haptic: HapticKind.selection,
                              builder: (context, state) => GlacierPill(
                                variant: prefs.theme == name ? GlacierPillVariant.solid : GlacierPillVariant.outline,
                                tone: GlacierPillTone.accent,
                                child: Text('${name[0].toUpperCase()}${name.substring(1)}'),
                              ),
                            ),
                        ],
                      ),
                    ]),

                    _Section('Density', [
                      GlacierDensitySelector(
                        ariaLabel: 'Density',
                        value: GlacierDensityMode.values.firstWhere((m) => m.token == prefs.density, orElse: () => GlacierDensityMode.comfortable),
                        onValueChange: (mode) => preferences.value = prefs.copyWith(density: mode.token),
                      ),
                    ]),

                    _Section('Switch', [
                      _Row('Haptics', GlacierSwitch(ariaLabel: 'Haptics', checked: prefs.haptics, onCheckedChange: (on) => preferences.value = prefs.copyWith(haptics: on))),
                      _Row('Glass surfaces', GlacierSwitch(ariaLabel: 'Glass surfaces', checked: _glass, glass: _glass, onCheckedChange: (on) => setState(() => _glass = on))),
                      _Row('Small', GlacierSwitch(ariaLabel: 'Small', size: GlacierSwitchSize.sm, checked: _small, onCheckedChange: (on) => setState(() => _small = on))),
                      const _Row('Disabled', GlacierSwitch(ariaLabel: 'Disabled', defaultChecked: true, disabled: true)),
                    ]),

                    _Section('Segmented control', [
                      GlacierSegmentedControl(
                        ariaLabel: 'View',
                        value: _segment,
                        onValueChange: (v) => setState(() => _segment = v),
                        size: _small ? GlacierSegmentedSize.sm : GlacierSegmentedSize.md,
                        options: const [
                          GlacierSegmentedOption(value: 'board', label: Text('Board')),
                          GlacierSegmentedOption(value: 'table', label: Text('Table')),
                          GlacierSegmentedOption(value: 'list', label: Text('List')),
                          GlacierSegmentedOption(value: 'off', label: Text('Off'), disabled: true),
                        ],
                      ),
                    ]),

                    _Section('Progress', [
                      GlacierProgressBar(ariaLabel: 'Backing up', value: _progress),
                      GlacierProgressBar(ariaLabel: 'Backing up, small', value: _progress, size: GlacierProgressBarSize.sm, tone: GlacierProgressBarTone.success),
                      const GlacierProgressBar(ariaLabel: 'Working', indeterminate: true),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppWord(onPressed: () => setState(() => _progress = _progress >= 100 ? 10 : (_progress + 22).clamp(0, 100)), child: Text('Advance · ${_progress.round()}%')),
                      ),
                    ]),

                    _Section('Pill', [
                      Wrap(
                        spacing: t.space(2),
                        runSpacing: t.space(2),
                        children: [
                          for (final variant in GlacierPillVariant.values)
                            for (final tone in GlacierPillTone.values) GlacierPill(tone: tone, variant: variant, glass: _glass, child: Text(tone.name)),
                        ],
                      ),
                      Wrap(
                        spacing: t.space(2),
                        runSpacing: t.space(2),
                        children: [
                          for (final name in _pills)
                            GlacierPill(icon: const Icon(LucideIcons.folder), onRemove: () => setState(() => _pills.remove(name)), child: Text(name)),
                          const GlacierPill(size: GlacierPillSize.sm, tone: GlacierPillTone.accent, child: Text('small')),
                        ],
                      ),
                    ]),

                    _Section('Fields', [
                      GlacierInput(
                        ariaLabel: 'Name',
                        placeholder: 'Name this note',
                        leadingIcon: const Icon(LucideIcons.pencil),
                        glass: _glass,
                        onChange: (v) => setState(() => _name = v),
                      ),
                      GlacierInput(ariaLabel: 'Password', type: GlacierInputType.password, placeholder: 'Password', size: _small ? GlacierFieldSize.sm : GlacierFieldSize.md),
                      GlacierSearchField(placeholder: 'Search notebooks and notes', glass: _glass),
                      const GlacierInput(ariaLabel: 'Disabled', placeholder: 'Disabled', disabled: true),
                      if (_name.isNotEmpty) Text('“$_name”', style: t.text('sm', color: t.color('glacier-text-subtle'))),
                    ]),

                    _Section('Toast', [
                      Wrap(
                        spacing: t.space(2),
                        runSpacing: t.space(2),
                        children: [
                          AppPill(onPressed: () => _toast(GlacierToastTone.neutral, 'Copied the link'), child: const Text('Neutral')),
                          AppPill(onPressed: () => _toast(GlacierToastTone.success, 'Backed up 312 notes'), haptic: HapticKind.success, child: const Text('Success')),
                          AppPill(onPressed: () => _toast(GlacierToastTone.warning, 'The drive is nearly full'), haptic: HapticKind.warning, child: const Text('Warning')),
                          AppPill(onPressed: () => _toast(GlacierToastTone.danger, 'The backup could not be written'), haptic: HapticKind.error, child: const Text('Danger')),
                          AppPill(
                            onPressed: () => GlacierToast.of(context).toast(
                              message: const Text('Moved to the bin'),
                              action: GlacierToastAction(label: 'Undo', onPress: () => _toast(GlacierToastTone.info, 'Put back')),
                            ),
                            child: const Text('With Undo'),
                          ),
                        ],
                      ),
                    ]),

                    _Section('Popover and menu', [
                      Wrap(
                        spacing: t.space(2),
                        runSpacing: t.space(2),
                        children: [
                          GlacierPopover(
                            ariaLabel: 'About this note',
                            trigger: (context, trigger) => AppPill(onPressed: trigger.toggle, icon: const Icon(LucideIcons.info), child: const Text('Popover')),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Weekend trip', style: t.text('md', weight: 'semibold')),
                                SizedBox(height: t.space(1)),
                                Text('Written at the cabin, three hours ago. 214 words.', style: t.text('sm', color: t.color('glacier-text-muted'))),
                              ],
                            ),
                          ),
                          GlacierMenu(
                            ariaLabel: 'Note actions',
                            placement: Placement.bottomEnd,
                            trigger: (context, trigger) => AppPill(onPressed: trigger.toggle, icon: const Icon(LucideIcons.ellipsis), child: const Text('Menu')),
                            children: [
                              const GlacierMenuLabel(child: Text('Weekend trip')),
                              GlacierMenuItem(icon: const Icon(LucideIcons.share2), onSelect: () => _toast(GlacierToastTone.neutral, 'Share'), child: const Text('Share')),
                              GlacierMenuItem(icon: const Icon(LucideIcons.pin), shortcut: const Text('⌘P'), onSelect: () => _toast(GlacierToastTone.neutral, 'Pinned'), child: const Text('Pin')),
                              GlacierMenuSub(
                                label: const Text('Move to'),
                                icon: const Icon(LucideIcons.folderInput),
                                children: [
                                  GlacierMenuItem(onSelect: () => _toast(GlacierToastTone.neutral, 'Moved to Work'), child: const Text('Work')),
                                  GlacierMenuItem(onSelect: () => _toast(GlacierToastTone.neutral, 'Moved to Home'), child: const Text('Home')),
                                  GlacierMenuItem(onSelect: () => _toast(GlacierToastTone.neutral, 'Moved to HelloTrade'), child: const Text('HelloTrade')),
                                ],
                              ),
                              const GlacierMenuItem(icon: Icon(LucideIcons.archive), disabled: true, child: Text('Archive')),
                              const GlacierMenuSeparator(),
                              GlacierMenuItem(icon: const Icon(LucideIcons.trash2), danger: true, onSelect: () => _toast(GlacierToastTone.danger, 'Moved to the bin'), child: const Text('Delete')),
                            ],
                          ),
                        ],
                      ),
                    ]),

                    _Section('Command palette', [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: AppPill(onPressed: () => setState(() => _palette = true), icon: const Icon(LucideIcons.search), child: const Text('Search and commands')),
                      ),
                    ]),

                    _Section('Motion', [
                      GlacierSegmentedControl(
                        ariaLabel: 'Motion',
                        size: GlacierSegmentedSize.sm,
                        value: _motion.name,
                        onValueChange: (name) => setState(() {
                          _motion = Motion.values.byName(name);
                          _replay++;
                        }),
                        options: const [
                          GlacierSegmentedOption(value: 'riseIn', label: Text('Rise')),
                          GlacierSegmentedOption(value: 'scaleIn', label: Text('Scale')),
                          GlacierSegmentedOption(value: 'slideLeft', label: Text('Slide')),
                          GlacierSegmentedOption(value: 'shake', label: Text('Shake')),
                          GlacierSegmentedOption(value: 'pulse', label: Text('Pulse')),
                        ],
                      ),
                      SizedBox(
                        height: t.space(16),
                        child: Row(
                          children: [
                            for (var i = 0; i < 4; i++) ...[
                              if (i > 0) SizedBox(width: t.space(2)),
                              Expanded(
                                child: GlacierMotion(
                                  key: ValueKey('$_replay-$i'),
                                  kind: _motion,
                                  delay: staggerDelay(t, i).delay,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(color: t.color('glacier-surface'), borderRadius: BorderRadius.circular(t.radius('md')), border: Border.all(color: t.color('glacier-border-subtle'))),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ]),

                    _Section('Haptics', [
                      Wrap(
                        spacing: t.space(2),
                        runSpacing: t.space(1),
                        children: [
                          for (final kind in HapticKind.values) AppWord(onPressed: () => HapticsProvider.of(context)(kind), child: Text(kind.name)),
                        ],
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
        GlacierCommandPalette(
          open: _palette,
          onOpenChange: (open) => setState(() => _palette = open),
          commands: _commands,
          placeholder: 'What would you like to do?',
          onRun: (id) => scheduleMicrotask(() => _toast(GlacierToastTone.neutral, _commands.firstWhere((c) => c.id == id).label)),
        ),
      ],
    );
  }
}

/// A section of the page: its eyebrow, then what it shows, a step apart.
class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: EdgeInsets.only(top: t.space(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppEyebrow(title),
          SizedBox(height: t.space(3)),
          for (var i = 0; i < children.length; i++) ...[if (i > 0) SizedBox(height: t.space(3)), children[i]],
        ],
      ),
    );
  }
}

/// A setting's row: its name, and its control at the far end.
class _Row extends StatelessWidget {
  const _Row(this.label, this.control);
  final String label;
  final Widget control;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Expanded(child: Text(label, style: t.text('md', weight: 'medium'))),
        control,
      ],
    );
  }
}
