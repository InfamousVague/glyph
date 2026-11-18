/// Making a circle, adding a space to one, and a circle's settings (Matt, 2026-11-17: "make a new design for [circles]
/// ... simpler and easier to digest ... use iconography and color where possible"): a name, one of the app's hues, an
/// icon or a picture, previewed on the circle's face as they are chosen, its first spaces and friends to bring; a
/// space's name, kind (three big cards, each in its colour) and heading; and, in settings, its people and their roles,
/// its invite link and QR code, arranging its spaces, and leaving or deleting it.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart' show Clipboard, ClipboardData, TextCapitalization;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../circles/circles.dart';
import '../../desktop/ui/qr.dart';
import '../../friends/buddies.dart';
import '../../kit/semantic_colors.dart';
import '../../kit/settings_kit.dart';
import '../../kit/settings_type.dart';
import '../../voice/channels.dart';
import '../../voice/voice.dart';
import '../common.dart';
import '../dialup/bevel.dart';
import '../shell.dart';
import 'arrange_spaces.dart';
import 'circle_face.dart';
import 'circle_invite.dart';
import 'circle_picture.dart';

/// A section of a settings-like page, its rows' icons on [hue] (as Settings' own sections are).
Widget _hued(String hue, Widget section) => GlacierScope(attrs: {'hue': hue}, child: section);

/// A form's list: no wider than 640 and centred on a wide window (a Fold open, a computer), so its fields and its
/// button read as a form rather than bars across the whole window; the margins still scroll it.
Widget _form(List<Widget> children) => Builder(
      builder: (context) => LayoutBuilder(builder: (context, box) {
        final t = context.tokens;
        final side = math.max(t.space(4), (box.maxWidth - 640) / 2);
        return ListView(padding: EdgeInsets.fromLTRB(side, t.space(2), side, t.space(8) + MediaQuery.paddingOf(context).bottom), children: children);
      }),
    );

/// The hues as round swatches, the chosen one ringed and ticked. Each swatch is its hue's own colour
/// ([AppColors.hueSwatch]), not the look's settling of it: in Phosphor, Dial-Up and Mist the look's hues fold into one
/// or a few, and a picker of twelve identical swatches could not be read. Where the look does fold them, a line says
/// that this look draws circles in its own colours and others see the one picked.
class CircleHuePicker extends StatelessWidget {
  const CircleHuePicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final bevel = isBevelChrome(t);
    final folded = {for (final h in circleHues) settingsHue(t.child(attrs: {'hue': h})).toARGB32()}.length < circleHues.length;
    final swatches = Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
      for (final h in circleHues)
        GlacierPressable(
          key: ValueKey('circle-hue-$h'),
          onPressed: () => onChanged(h),
          semanticLabel: '$h${h == value ? ', chosen' : ''}',
          builder: (context, _) {
            final chosen = h == value;
            final fill = t.hueSwatch(h);
            return Container(
              width: 38,
              height: 38,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: bevel ? BoxShape.rectangle : BoxShape.circle,
                border: Border.all(color: chosen ? t.color('app-ink') : const Color(0x00000000), width: 2),
              ),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: bevel ? BoxShape.rectangle : BoxShape.circle,
                  color: fill,
                  border: bevel ? Border.all(color: DialupColors.of(t).dark) : null,
                ),
                child: chosen ? AppIcon(Lucide.check, size: 16, strokeWidth: 3, wash: false, color: fill.computeLuminance() > 0.45 ? const Color(0xFF000000) : const Color(0xFFFFFFFF)) : null,
              ),
            );
          },
        ),
    ]);
    if (!folded) return swatches;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      swatches,
      SizedBox(height: t.space(2)),
      Text('This look draws circles in its own colours. Everyone else sees the colour you pick.', style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
    ]);
  }
}

/// The circle icons as an even grid, each in the circle's hue, the chosen one filled.
class CircleIconPicker extends StatelessWidget {
  const CircleIconPicker({super.key, required this.hue, required this.value, required this.onChanged});
  final String hue;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(2);
    return LayoutBuilder(builder: (context, box) {
      // Six across on a phone, more as there is room, every cell the same width.
      final across = ((box.maxWidth + gap) / (44 + gap)).floor().clamp(6, 12);
      final cell = (box.maxWidth - gap * (across - 1)) / across;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final name in circleIcons.keys)
          SizedBox(
            width: cell,
            child: Center(
              child: GlacierPressable(
                key: ValueKey('circle-icon-$name'),
                onPressed: () => onChanged(name),
                semanticLabel: '${name.replaceAll('-', ' ')}${name == value ? ', chosen' : ''}',
                builder: (context, _) => CircleFace(hue: hue, icon: name, size: cell.clamp(32.0, 44.0), selected: name == value),
              ),
            ),
          ),
      ]);
    });
  }
}

/// A space's kind as three big cards: its mark in its colour, its name and what it is for; the chosen one filled with
/// its colour's wash and ringed. Side by side where there is room, else one above another.
class SpaceKindCards extends StatelessWidget {
  const SpaceKindCards({super.key, required this.value, required this.onChanged, this.title = 'What it\'s for'});
  final SpaceKind value;
  final ValueChanged<SpaceKind> onChanged;

  /// Over the cards, drawn as a settings section's title is (in capitals; as written under Dial-Up); none if empty.
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.lenOf('0.72rem');
    final cards = _cards(context);
    if (title.isEmpty) return cards;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(t.space(2), 0, t.space(2), t.space(2)),
        child: Semantics(
          label: title,
          child: ExcludeSemantics(
            child: Text(isBevelChrome(t) ? title : title.toUpperCase(), style: pageText(t, size, weight: 'semibold', color: t.color('app-ink-3'), tracking: t.len('app-tracking-caps', em: size))),
          ),
        ),
      ),
      cards,
    ]);
  }

  Widget _cards(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(builder: (context, box) {
      final across = box.maxWidth >= 540;
      final cards = [for (final k in SpaceKind.values) _KindCard(kind: k, chosen: k == value, tall: across, onPress: () => onChanged(k))];
      if (across) {
        return IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (i, c) in cards.indexed) ...[if (i > 0) SizedBox(width: t.space(2)), Expanded(child: c)],
          ]),
        );
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final (i, c) in cards.indexed) ...[if (i > 0) SizedBox(height: t.space(2)), c],
      ]);
    });
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({required this.kind, required this.chosen, required this.tall, required this.onPress});
  final SpaceKind kind;
  final bool chosen;

  /// One of three across: the mark above the words.
  final bool tall;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) => GlacierPressable(
        key: ValueKey('space-kind-${kind.wire}'),
        onPressed: onPress,
        semanticLabel: '${spaceKindTitle(kind)}, ${spaceKindBlurb(kind)}${chosen ? ', chosen' : ''}',
        builder: (context, state) => GlacierScope(
          attrs: {'hue': SpaceKindBadge.hueOf(kind)},
          child: Builder(builder: (context) {
            final t = context.tokens;
            final bevel = isBevelChrome(t);
            final hue = settingsHue(t);
            final words = [
              Text(spaceKindTitle(kind), style: pageText(t, t.fontSize('md'), weight: 'bold', color: t.color('app-ink'))),
              SizedBox(height: t.space(1) / 2),
              Text(spaceKindBlurb(kind), style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-2'), height: 1.35)),
            ];
            final tick = AppIcon(chosen ? Lucide.circleCheck : Lucide.circle, size: 20, wash: false, color: chosen ? hue : t.color('app-ink-4'));
            final inside = tall
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [SpaceKindBadge(kind: kind, size: 44, live: chosen), const Spacer(), tick]),
                    SizedBox(height: t.space(3)),
                    ...words,
                  ])
                : Row(children: [
                    SpaceKindBadge(kind: kind, size: 44, live: chosen),
                    SizedBox(width: t.space(3)),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: words)),
                    SizedBox(width: t.space(2)),
                    tick,
                  ]);
            final pad = EdgeInsets.all(t.space(3) + 2);
            // Dial-Up: a raised card that is pressed in while chosen.
            if (bevel) return Bevel(style: chosen || state.pressed ? BevelStyle.sunken : BevelStyle.raised, color: chosen ? DialupColors.of(t).paper : null, padding: pad, child: inside);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: pad,
              decoration: BoxDecoration(
                color: chosen ? settingsHueWash(t) : t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'),
                borderRadius: BorderRadius.circular(t.radius('lg')),
                border: Border.all(color: chosen ? hue : t.color('app-rule'), width: chosen ? 2 : 1),
              ),
              child: inside,
            );
          }),
        ),
      );
}

/// A space as a small pill: its mark and name. The new circle's preview of its first spaces.
class _SpacePill extends StatelessWidget {
  const _SpacePill({required this.kind, required this.name});
  final SpaceKind kind;
  final String name;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.fromLTRB(t.space(1), t.space(1), t.space(3), t.space(1)),
      decoration: BoxDecoration(color: isBevelChrome(t) ? null : t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('full'))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        SpaceKindBadge(kind: kind, size: 22),
        SizedBox(width: t.space(1) + 2),
        Text(name, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('app-ink-2'))),
      ]),
    );
  }
}

/// A circle's picture, chosen or taken away: a row for each.
List<Widget> _pictureRows(BuildContext context, {required String? picture, required ValueChanged<String> onPicked, required VoidCallback onCleared}) => [
      SettingRow(
        key: const ValueKey('circle-picture'),
        icon: AppIcon(Lucide.imagePlus, size: 18),
        label: picture == null ? 'Choose a picture' : 'Change the picture',
        hint: const Text('Shown in the icon\'s place'),
        onPress: () async {
          final p = await pickCirclePicture(context);
          if (p != null) onPicked(p);
        },
      ),
      if (picture != null) SettingRow(icon: AppIcon(Lucide.trash2, size: 18), label: 'Use the icon instead', onPress: onCleared),
    ];

/// One of a new circle's first spaces, before it is made.
class _Draft {
  _Draft(this.name, this.kind);
  String name;
  SpaceKind kind;
}

/// A new circle: its name, colour, icon or picture, previewed; its first spaces (a texting space and a voice space to
/// start, each to rename, retype or drop); and friends to bring, sent it the moment it is made.
class NewCircleScreen extends StatefulWidget {
  const NewCircleScreen({super.key, this.buddies, this.make, this.share});

  /// For a test: friends, and what makes and shares the circle (Circles' own otherwise).
  final Buddies? buddies;
  final Future<Circle?> Function({required String name, String? hue, String icon, String? picture, List<CircleSpace>? spaces})? make;
  final Future<List<Buddy>> Function(Circle circle, List<Buddy> friends)? share;

  @override
  State<NewCircleScreen> createState() => _NewCircleScreenState();
}

class _NewCircleScreenState extends State<NewCircleScreen> {
  final _name = TextEditingController();
  // The same colour each time the page opens (a random one made the page, and its pictures, differ run to run).
  String _hue = 'indigo';
  String _icon = 'users';
  String? _picture;
  // The two spaces a circle starts with (Circles.make's own): one to text in, one to talk in.
  final _spaces = [_Draft('General', SpaceKind.text), _Draft('Lounge', SpaceKind.voice)];
  final Set<String> _with = {};
  bool _making = false;

  Buddies get _buddies => widget.buddies ?? Buddies.instance;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _make() async {
    if (_making) return;
    setState(() => _making = true);
    final shell = AppShell.maybeOf(context);
    final make = widget.make ?? Circles.instance.make;
    final c = await make(
      name: _name.text,
      hue: _hue,
      icon: _icon,
      picture: _picture,
      spaces: [for (final (i, d) in _spaces.indexed) CircleSpace.make(d.name.trim().isEmpty ? spaceKindTitle(d.kind) : d.name.trim(), kind: d.kind, order: i)],
    );
    if (!mounted) return;
    if (c == null) {
      setState(() => _making = false);
      toast(context, 'Couldn\'t make the circle: the relay server isn\'t connected yet.', tone: GlacierToastTone.danger);
      return;
    }
    final friends = [for (final f in _buddies.friends) if (_with.contains(f.id)) f];
    final missed = friends.isEmpty ? const <Buddy>[] : await (widget.share ?? Circles.instance.share)(c, friends);
    if (!mounted) return;
    setState(() => _making = false);
    toast(context, friends.isEmpty ? '${c.name} made' : '${c.name} made and shared with ${friends.length - missed.length}${missed.isEmpty ? '' : '; couldn\'t reach ${missed.map((f) => f.shown).join(', ')}'}');
    if (shell != null) {
      shell.close();
      shell.openCircle(c);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _spaceMenu(_Draft d) {
    showChoices(context, title: '${d.name} · ${spaceKindTitle(d.kind)}', choices: [
      Choice('Rename', Lucide.pencil, () => askCircleWords(context, title: 'Rename ${d.name}', initial: d.name, then: (n) => setState(() => d.name = n))),
      for (final k in SpaceKind.values)
        if (k != d.kind) Choice('Make it ${spaceKindTitle(k).toLowerCase()}', spaceKindIcon(k), () => setState(() => d.kind = k), hint: spaceKindBlurb(k)),
      Choice('Leave it out', Lucide.x, () => setState(() => _spaces.remove(d)), danger: true),
    ]);
  }

  void _addSpace() {
    showChoices(context, title: 'Add a space', choices: [
      for (final k in SpaceKind.values) Choice(spaceKindTitle(k), spaceKindIcon(k), () => setState(() => _spaces.add(_Draft(_firstName(k), k))), hint: spaceKindBlurb(k)),
    ]);
  }

  static String _firstName(SpaceKind k) => switch (k) {
        SpaceKind.voice => 'Voice',
        SpaceKind.text => 'Chat',
        SpaceKind.files => 'Files',
      };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = _name.text.trim().isEmpty ? 'New circle' : _name.text.trim();
    final gap = SizedBox(height: t.space(5));
    return GhostPage(
      title: 'New circle',
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: ListenableBuilder(
          listenable: _buddies,
          builder: (context, _) {
            final friends = _buddies.friends;
            return _form([
                // The circle as it will look: its face, name and first spaces.
                Center(child: CircleFace(key: const ValueKey('new-circle-face'), hue: _hue, icon: _icon, picture: _picture, size: 76, selected: _picture == null)),
                SizedBox(height: t.space(2)),
                Text(name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xl'), weight: 'bold')),
                SizedBox(height: t.space(2)),
                Wrap(alignment: WrapAlignment.center, spacing: t.space(1) + 2, runSpacing: t.space(1) + 2, children: [for (final d in _spaces) _SpacePill(kind: d.kind, name: d.name)]),
                SizedBox(height: t.space(5)),
                PaneSection(title: 'Name', children: [
                  SettingRowBox(child: GlacierInput(controller: _name, placeholder: 'Circle name', ariaLabel: 'Circle name', autoFocus: true, autoCapitalize: TextCapitalization.words, size: GlacierFieldSize.md)),
                ]),
                gap,
                PaneSection(title: 'Colour', children: [SettingRowBox(child: CircleHuePicker(value: _hue, onChanged: (h) => setState(() => _hue = h)))]),
                gap,
                PaneSection(title: 'Icon', children: [SettingRowBox(child: CircleIconPicker(hue: _hue, value: _icon, onChanged: (i) => setState(() => _icon = i)))]),
                gap,
                _hued('purple', PaneSection(title: 'Picture', description: const Text('Optional: a picture of your own on the circle\'s face.'), children: _pictureRows(context, picture: _picture, onPicked: (p) => setState(() => _picture = p), onCleared: () => setState(() => _picture = null)))),
                gap,
                PaneSection(
                  title: 'First spaces',
                  description: const Text('Press one to rename it or change what it\'s for. You can add more, files spaces too, any time.'),
                  children: [
                    for (final (i, d) in _spaces.indexed)
                      SettingRow(
                        key: ValueKey('new-circle-space-$i'),
                        icon: SpaceKindBadge(kind: d.kind, size: 26),
                        label: d.name,
                        hint: Text(spaceKindTitle(d.kind)),
                        onPress: () => _spaceMenu(d),
                      ),
                    _hued('green', SettingRow(key: const ValueKey('new-circle-add-space'), icon: AppIcon(Lucide.plus, size: 18), label: 'Add a space', onPress: _addSpace)),
                  ],
                ),
                gap,
                _hued('mint', PaneSection(
                  title: 'Bring friends',
                  description: Text(friends.isEmpty ? 'Add friends by username (Settings › Me › Friends) to bring them in one press. Anyone can join by the circle\'s link too.' : 'They\'re sent the circle as soon as it\'s made.'),
                  children: [
                    for (final f in friends)
                      SettingRow(
                        key: ValueKey('new-circle-friend-${f.id}'),
                        icon: AppIcon(Lucide.userRound, size: 18),
                        label: f.shown,
                        control: GlacierSwitch(checked: _with.contains(f.id), onCheckedChange: (on) => setState(() => on ? _with.add(f.id) : _with.remove(f.id)), ariaLabel: f.shown),
                      ),
                  ],
                )),
                gap,
                _hued('green', PaneSection(children: [
                  SettingRow(key: const ValueKey('circle-make'), icon: AppIcon(Lucide.check, size: 18), label: _making ? 'Making…' : 'Make the circle', onPress: _making ? null : _make),
                ])),
            ]);
          },
        ),
      ),
    );
  }
}

/// A new space in [circle]: its kind as three cards, its name, and a heading (those the circle has offered to tap).
class NewCircleSpaceScreen extends StatefulWidget {
  const NewCircleSpaceScreen({super.key, required this.circle, this.section});
  final Circle circle;
  final String? section;

  @override
  State<NewCircleSpaceScreen> createState() => _NewCircleSpaceScreenState();
}

class _NewCircleSpaceScreenState extends State<NewCircleSpaceScreen> {
  final _name = TextEditingController();
  late final _section = TextEditingController(text: widget.section ?? '');
  SpaceKind _kind = SpaceKind.text;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _section.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _section.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    final circle = Circles.instance.bySeed(widget.circle.seed) ?? widget.circle;
    final s = await Circles.instance.addSpace(circle, _name.text.trim().isEmpty ? spaceKindTitle(_kind) : _name.text, kind: _kind, section: _section.text);
    if (!mounted) return;
    setState(() => _adding = false);
    if (s == null) {
      toast(context, 'Couldn\'t add the space: only the circle\'s owner and admins can.', tone: GlacierToastTone.danger);
      return;
    }
    toast(context, '${s.name} added');
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final headings = <String>{for (final s in widget.circle.spaces) ?s.section};
    final gap = SizedBox(height: t.space(5));
    final typed = _section.text.trim();
    return GhostPage(
      title: 'New space',
      subtitle: widget.circle.name,
      titleLeading: TitleBarMark(icon: circleIconOf(widget.circle.icon), child: CircleFace.of(widget.circle, size: 18)),
      body: SettingsPaneScope(
        finder: SettingsFinder(),
        child: _form([
            SizedBox(height: t.space(2)),
            SpaceKindCards(value: _kind, onChanged: (k) => setState(() => _kind = k)),
            gap,
            PaneSection(title: 'Name', children: [
              SettingRowBox(
                child: Row(children: [
                  SpaceKindBadge(kind: _kind, size: 28),
                  SizedBox(width: t.space(2)),
                  Expanded(child: GlacierInput(controller: _name, placeholder: 'Space name', ariaLabel: 'Space name', autoCapitalize: TextCapitalization.words, size: GlacierFieldSize.md)),
                ]),
              ),
            ]),
            gap,
            PaneSection(
              title: 'Heading',
              description: const Text('Spaces with the same heading are listed together. Leave it empty for none.'),
              children: [
                SettingRowBox(child: GlacierInput(controller: _section, placeholder: 'No heading', ariaLabel: 'Heading', autoCapitalize: TextCapitalization.words, size: GlacierFieldSize.md)),
                if (headings.isNotEmpty)
                  SettingRowBox(
                    child: Wrap(spacing: t.space(2), runSpacing: t.space(2), children: [
                      for (final h in headings)
                        GlacierPressable(
                          key: ValueKey('space-heading-$h'),
                          onPressed: () => _section.text = h,
                          semanticLabel: 'Under $h${typed == h ? ', chosen' : ''}',
                          builder: (context, state) => Container(
                            padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(1)),
                            decoration: BoxDecoration(
                              color: typed == h ? t.color('app-ink') : t.color(state.pressed ? 'app-paper-3' : 'app-paper'),
                              borderRadius: BorderRadius.circular(isBevelChrome(t) ? 0 : t.radius('full')),
                              border: Border.all(color: t.color('app-rule')),
                            ),
                            child: Text(h, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: typed == h ? t.color('app-paper') : t.color('app-ink-2'))),
                          ),
                        ),
                    ]),
                  ),
              ],
            ),
            gap,
            _hued('green', PaneSection(children: [
              SettingRow(key: const ValueKey('circle-space-add'), icon: AppIcon(Lucide.plus, size: 18), label: _adding ? 'Adding…' : 'Add the space', onPress: _adding ? null : _add),
            ])),
        ]),
      ),
    );
  }
}

/// Someone in a circle, as its settings list them.
@immutable
class CirclePerson {
  const CirclePerson({required this.id, required this.name, this.owner = false, this.admin = false, this.here = false, this.me = false});
  final String id;
  final String name;
  final bool owner, admin;

  /// In the circle's room, or one of its spaces, now.
  final bool here;

  /// This install.
  final bool me;

  String get role => owner ? 'Owner' : (admin ? 'Admin' : 'Member');
}

/// Everyone [c] knows of: its owner and admins, whoever is in its room or one of its spaces now, and whoever has
/// written in its spaces; each by the name they last gave, owner first, then admins, then the rest by name. A circle
/// keeps no list of members (holding its link is being in it), so this is who has been seen.
List<CirclePerson> circlePeople(Circle c) {
  final voice = Voice.instance;
  final me = Circles.instance.signer?.id ?? voice.me;
  final m = c.manifest;
  final ids = <String>{if (m.ownerId.isNotEmpty) m.ownerId, for (final id in m.adminGrants.keys) if (m.granted(id)) id};
  final here = <String>{...Circles.instance.presentIn(c)};
  final names = <String, String>{};
  for (final ch in c.channels) {
    final room = voice.hangoutFor(ch);
    if (room == null) continue;
    for (final p in room.present.values) {
      here.add(p.id);
      if (p.name.isNotEmpty) names[p.id] = p.name;
    }
    for (final msg in room.messages) {
      ids.add(msg.from);
      if (msg.name.isNotEmpty) names.putIfAbsent(msg.from, () => msg.name);
    }
  }
  ids.addAll(here);
  if (me != null && me.isNotEmpty) ids.add(me);
  String nameOf(String id) {
    if (id == me) return 'You';
    final said = names[id];
    if (said != null) return said;
    final known = voice.nameOf(id);
    return known == 'Someone' ? 'Someone (${id.length > 6 ? id.substring(0, 6) : id})' : known;
  }

  final people = [
    for (final id in ids)
      if (id.isNotEmpty) CirclePerson(id: id, name: nameOf(id), owner: id == m.ownerId, admin: id != m.ownerId && m.granted(id), here: id == me || here.contains(id), me: id == me),
  ];
  int rank(CirclePerson p) => p.owner ? 0 : (p.admin ? 1 : 2);
  people.sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return people;
}

/// What the owner can do with someone in their circle, from its settings or its members drawer: make them an admin,
/// or take it back.
void circlePersonMenu(BuildContext context, Circle c, CirclePerson p) {
  final circles = Circles.instance;
  showChoices(context, title: '${p.name} · ${p.role}', choices: [
    p.admin
        ? Choice('Remove as admin', Lucide.userMinus, () async {
            final ok = await circles.grantAdmin(c, p.id, on: false);
            if (context.mounted) toast(context, ok ? '${p.name} is no longer an admin' : 'Couldn\'t change ${p.name}\'s role', tone: ok ? GlacierToastTone.neutral : GlacierToastTone.danger);
          })
        : Choice('Make admin', Lucide.crown, () async {
            final ok = await circles.grantAdmin(c, p.id);
            if (context.mounted) toast(context, ok ? '${p.name} is an admin' : 'Couldn\'t change ${p.name}\'s role', tone: ok ? GlacierToastTone.neutral : GlacierToastTone.danger);
          }, hint: 'Can change the circle and its spaces'),
  ]);
}

/// A person's role in a circle as a small tag, the owner's and admins' filled; a green dot before it while they are on.
class CircleRoleTag extends StatelessWidget {
  const CircleRoleTag({super.key, required this.person});
  final CirclePerson person;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final strong = person.owner || person.admin;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (person.here) ...[
        Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: t.online)),
        SizedBox(width: t.space(2)),
      ],
      Container(
        padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 1),
        decoration: BoxDecoration(color: strong ? t.color('app-ink') : t.color('app-paper-3'), borderRadius: BorderRadius.circular(isBevelChrome(t) ? 0 : t.radius('full'))),
        child: Text(person.role, style: pageText(t, t.fontSize('xs'), weight: 'semibold', color: strong ? t.color('app-paper') : t.color('app-ink-2'))),
      ),
    ]);
  }
}

/// A circle's settings: its name, colour, icon and picture, its spaces, its people and their roles, its invite link
/// and QR code, and leaving it (deleting it, for its owner). Whoever may not change it reads what it is.
class CircleSettingsScreen extends StatefulWidget {
  const CircleSettingsScreen({super.key, required this.seed, this.qr = false});
  final String seed;

  /// Opened with the QR code showing (a picture of it).
  final bool qr;

  @override
  State<CircleSettingsScreen> createState() => _CircleSettingsScreenState();
}

class _CircleSettingsScreenState extends State<CircleSettingsScreen> {
  late bool _qr = widget.qr;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final circles = Circles.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([circles, Voice.instance]),
      builder: (context, _) {
        final c = circles.bySeed(widget.seed);
        if (c == null) return GhostPage(title: 'Circle', body: const Center(child: Text('You left this circle.')));
        final edit = circles.canEdit(c);
        final owner = c.manifest.ownerId.isNotEmpty && circles.signer?.id == c.manifest.ownerId;
        final people = circlePeople(c);
        final online = circles.onlineIn(c);
        final gap = SizedBox(height: t.space(6));
        return GhostPage(
          title: edit ? 'Circle settings' : c.name,
          body: SettingsPaneScope(
            finder: SettingsFinder(),
            child: _form([
                Center(child: CircleFace.of(c, size: 76, selected: c.picture == null)),
                SizedBox(height: t.space(2)),
                Text(c.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xl'), weight: 'bold')),
                Text(
                  [
                    '${c.spaces.length} ${c.spaces.length == 1 ? 'space' : 'spaces'}',
                    '${people.length} ${people.length == 1 ? 'person' : 'people'}',
                    if (online > 0) '$online on now',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: pageText(t, t.fontSize('sm'), color: t.color('app-ink-3')),
                ),
                SizedBox(height: t.space(5)),
                if (edit) ...[
                  _hued('blue', PaneSection(title: 'Circle', children: [
                    SettingRow(key: const ValueKey('circle-rename'), icon: AppIcon(Lucide.pencil, size: 18), label: 'Name', value: Text(c.name), onPress: () => askCircleWords(context, title: 'Rename circle', initial: c.name, then: (n) => circles.edit(c, name: n))),
                    ..._pictureRows(context, picture: c.picture, onPicked: (p) => circles.edit(c, picture: p), onCleared: () => circles.edit(c, clearPicture: true)),
                  ])),
                  gap,
                  PaneSection(title: 'Colour', children: [SettingRowBox(child: CircleHuePicker(value: c.hue, onChanged: (h) => circles.edit(c, hue: h)))]),
                  gap,
                  PaneSection(title: 'Icon', children: [SettingRowBox(child: CircleIconPicker(hue: c.hue, value: c.icon, onChanged: (i) => circles.edit(c, icon: i)))]),
                  gap,
                ] else ...[
                  SettingsCallout(child: const Text('Only the circle\'s owner and the admins they made can change it.')),
                  gap,
                ],
                _hued('amber', PaneSection(title: 'Spaces', children: [
                  SettingRow(
                    key: const ValueKey('circle-arrange'),
                    icon: AppIcon(Lucide.listTree, size: 18),
                    label: edit ? 'Arrange spaces' : 'Spaces',
                    hint: Text(edit ? 'Move, rename, change or delete them' : [for (final k in SpaceKind.values) if (c.spaces.any((s) => s.kind == k)) '${c.spaces.where((s) => s.kind == k).length} ${spaceKindTitle(k).toLowerCase()}'].join(', ')),
                    value: Text('${c.spaces.length}'),
                    onPress: () => push<void>(context, (_) => ArrangeCircleSpacesScreen(seed: c.seed)),
                  ),
                  if (edit) SettingRow(key: const ValueKey('circle-settings-new-space'), icon: AppIcon(Lucide.plus, size: 18), label: 'New space', onPress: () => push<void>(context, (_) => NewCircleSpaceScreen(circle: c))),
                ])),
                gap,
                _hued('green', PaneSection(
                  title: 'People',
                  description: Text(owner ? 'Press someone to make them an admin: admins can change the circle and its spaces too.' : 'The owner makes admins, who can change the circle and its spaces.'),
                  children: [
                    SettingRow(key: const ValueKey('circle-settings-invite'), icon: AppIcon(Lucide.userPlus, size: 18), label: 'Invite people', hint: const Text('Friends in the app, anyone by a text, or the link.'), onPress: () => showCircleInvite(context, c)),
                    for (final p in people)
                      SettingRow(
                        key: ValueKey('circle-person-${p.id}'),
                        icon: AppIcon(p.owner ? Lucide.crown : (p.admin ? Lucide.shieldCheck : Lucide.userRound), size: 18),
                        label: p.name,
                        value: CircleRoleTag(person: p),
                        onPress: owner && !p.owner ? () => _person(context, c, p) : null,
                      ),
                  ],
                )),
                gap,
                _hued('purple', PaneSection(
                  title: 'Invite link',
                  description: const Text('Whoever has the link is in the circle, so share it with people you know.'),
                  children: [
                    SettingRow(
                      key: const ValueKey('circle-copy-link'),
                      icon: AppIcon(Lucide.link, size: 18),
                      label: 'Copy invite link',
                      onPress: () {
                        Clipboard.setData(ClipboardData(text: c.link));
                        toast(context, 'Invite link copied');
                      },
                    ),
                    SettingRow(key: const ValueKey('circle-qr'), icon: AppIcon(Lucide.scanText, size: 18), label: _qr ? 'Hide the QR code' : 'Show a QR code', onPress: () => setState(() => _qr = !_qr)),
                    if (_qr)
                      SettingRowBox(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(t.space(2)),
                            child: Semantics(label: 'The invite link to ${c.name}, as a QR code', child: ExcludeSemantics(child: QrView(data: c.link, size: 200, radius: isBevelChrome(t) ? 0 : 14))),
                          ),
                        ),
                      ),
                  ],
                )),
                gap,
                _hued('red', PaneSection(children: [
                  SettingRow(key: const ValueKey('circle-leave'), icon: AppIcon(Lucide.logOut, size: 18), label: 'Leave circle', hint: const Text('It goes from your list; its link brings you back.'), onPress: () => _leave(context, c)),
                  if (owner) SettingRow(key: const ValueKey('circle-delete'), icon: AppIcon(Lucide.trash2, size: 18), label: 'Delete circle', hint: const Text('Takes every space out of it for everyone, then leaves it.'), onPress: () => _delete(context, c)),
                ])),
            ]),
          ),
        );
      },
    );
  }

  void _person(BuildContext context, Circle c, CirclePerson p) => circlePersonMenu(context, c, p);

  void _leave(BuildContext context, Circle c) {
    showChoices(context, title: 'Leave ${c.name}? It goes from your list; its link brings you back.', choices: [
      Choice('Leave circle', Lucide.logOut, () => _gone(context, c, () => Circles.instance.leave(c), 'Left ${c.name}'), danger: true),
    ]);
  }

  void _delete(BuildContext context, Circle c) {
    showChoices(context, title: 'Delete ${c.name}? Every space goes from it for everyone in it, and it goes from your list. This can\'t be undone.', choices: [
      Choice('Delete circle', Lucide.trash2, () => _gone(context, c, () async {
            // A manifest has no "closed" mark: one with no spaces is said to everyone, then the circle is left here.
            for (final s in c.spaces) {
              final now = Circles.instance.bySeed(c.seed);
              if (now == null) break;
              await Circles.instance.removeSpace(now, s.seed);
            }
            final now = Circles.instance.bySeed(c.seed);
            if (now != null) await Circles.instance.leave(now);
          }, '${c.name} deleted'), danger: true),
    ]);
  }

  /// Does [away], then puts this page and the circle away, saying [words].
  Future<void> _gone(BuildContext context, Circle c, Future<void> Function() away, String words) async {
    final nav = Navigator.of(context);
    final shell = AppShell.maybeOf(context);
    final open = shell?.openCircleSeed == c.seed;
    await away();
    if (context.mounted) toast(context, words);
    nav.maybePop();
    if (open) shell?.go('messages');
  }
}

/// Asks for a line of words (a name, a heading), then gives it to [then].
void askCircleWords(BuildContext context, {required String title, String initial = '', String? hint, required void Function(String words) then}) {
  unawaited(push<void>(context, (_) => _WordsPage(title: title, initial: initial, hint: hint, then: then)));
}

class _WordsPage extends StatefulWidget {
  const _WordsPage({required this.title, required this.initial, required this.then, this.hint});
  final String title;
  final String initial;
  final String? hint;
  final void Function(String words) then;

  @override
  State<_WordsPage> createState() => _WordsPageState();
}

class _WordsPageState extends State<_WordsPage> {
  late final _words = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _words.dispose();
    super.dispose();
  }

  void _done() {
    // Empty is an answer only where it means something ("no heading").
    if (_words.text.trim().isEmpty && widget.hint == null) return;
    widget.then(_words.text.trim());
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GhostPage(
      title: widget.title,
      body: ListView(
        padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(8)),
        children: [
          PaneSection(
            description: widget.hint == null ? null : Text(widget.hint!),
            children: [
              SettingRowBox(child: GlacierInput(controller: _words, ariaLabel: widget.title, autoFocus: true, autoCapitalize: TextCapitalization.words, size: GlacierFieldSize.md, onSubmitted: (_) => _done())),
            ],
          ),
          SizedBox(height: t.space(4)),
          PaneSection(children: [SettingRow(key: const ValueKey('words-save'), icon: AppIcon(Lucide.check, size: 18), label: 'Save', onPress: _done)]),
        ],
      ),
    );
  }
}
