/// What a circle's list draws (circle_list.dart): the circle, its spaces as they stand (kind, unread, who is in voice,
/// how many files), which is open, and what to do when one is pressed or something is asked for. The circle's screen
/// (circle_screen.dart) builds it from Circles and Voice; a test or a picture can build one by hand.
///
/// A circle was once drawn in any of ten layouts; it now always shows its list (Matt, 2026-11-17: "Lets remove the
/// other views and focus on the list view / layout it's the most practical of them all so far").
library;

import 'package:flutter/widgets.dart';

import '../../art/app_icon.dart';
import '../../circles/circle.dart';
import '../../voice/voice.dart';
import 'circle_face.dart';

/// One space of a circle as its list draws it.
@immutable
class CircleSpaceView {
  const CircleSpaceView({
    required this.space,
    required this.channel,
    this.unread = 0,
    this.mentions = 0,
    this.lastMessage,
    this.lastAt,
    this.inVoice = const [],
    this.here = false,
    this.files,
  });

  /// Its entry in the circle's list (name, kind, place, section) and itself as a space (rooms, chat, call).
  final CircleSpace space;
  final VoiceChannel channel;

  /// How many messages from others came after this device last read it.
  final int unread;

  /// How many of those mention this device: an "@" on its mark.
  final int mentions;

  /// Its newest message as a line ("Maya: see you at eight"), and when; null where it has none.
  final String? lastMessage;
  final DateTime? lastAt;

  /// The names of who is in its call now (a voice space's), this device among them as "You" while it is in it.
  final List<String> inVoice;

  /// This device is in its call.
  final bool here;

  /// How many files a Files space holds, where its list has been read on this device; null where not (or another kind).
  final int? files;

  String get seed => space.seed;
  String get name => space.name;
  SpaceKind get kind => space.kind;
  String? get section => space.section;

  /// Anyone is in its call now.
  bool get live => inVoice.isNotEmpty;

  /// Its kind's mark (headphones, a speech bubble, a folder).
  LucideIcon get icon => spaceKindIcon(kind);
}

/// A heading of a circle's list and the spaces under it.
@immutable
class CircleSection {
  const CircleSection(this.name, this.spaces);

  /// Null for the spaces under no heading, which come first.
  final String? name;
  final List<CircleSpaceView> spaces;
}

/// Everything a circle's list is drawn from.
@immutable
class CircleView {
  const CircleView({
    required this.circle,
    required this.spaces,
    required this.onOpen,
    required this.onNewSpace,
    required this.onSettings,
    required this.onInvite,
    required this.onBack,
    required this.onMenu,
    this.selected,
    this.wide = false,
    this.canEdit = false,
    this.online = 0,
    this.onSpaceMenu,
  });

  final Circle circle;

  /// Its spaces in their order.
  final List<CircleSpaceView> spaces;

  /// The seed of the space open in the pane beside it, or null (always null on a phone, where the space is over it).
  final String? selected;

  /// Drawn as a sidebar beside the pane (a computer, an unfolded Fold), else as the whole page (a phone).
  final bool wide;

  /// This device may change the circle: add spaces, rename, arrange, settings.
  final bool canEdit;

  /// How many are in the circle's room now, this device among them.
  final int online;

  /// A space pressed: opened in the pane beside, or over the page on a phone.
  final void Function(CircleSpaceView space) onOpen;

  /// A space held or pressed with the other button: its menu (rename, kind, section, remove); null where none.
  final void Function(CircleSpaceView space)? onSpaceMenu;

  /// A new space asked for, under [section] where it was asked for under one.
  final void Function({String? section}) onNewSpace;

  /// The circle's settings (name, colour, icon, picture, admins).
  final VoidCallback onSettings;

  /// Invite people: friends, the link.
  final VoidCallback onInvite;

  /// Back to the conversations.
  final VoidCallback onBack;

  /// The circle's own menu (invite, settings, leave).
  final VoidCallback onMenu;

  /// Its spaces under their headings, in the order the headings' first spaces come; those under none first.
  List<CircleSection> get sections {
    final order = <String?>[null];
    for (final s in spaces) {
      if (!order.contains(s.section)) order.add(s.section);
    }
    return [
      for (final name in order)
        if (spaces.any((s) => s.section == name)) CircleSection(name, [for (final s in spaces) if (s.section == name) s]),
    ];
  }

  /// Every message unread in it.
  int get unread => spaces.fold(0, (n, s) => n + s.unread);

  /// Its spaces with anyone in their calls.
  List<CircleSpaceView> get live => [for (final s in spaces) if (s.live) s];

  CircleSpaceView? get open => spaces.where((s) => s.seed == selected).firstOrNull;
}
