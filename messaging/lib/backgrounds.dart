import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import 'app_state.dart';
import 'sms.dart';

/// What is drawn behind a conversation's messages (Matt, 2026-11-13: "allow changing the backgrounds for chats,
/// there should be a standard way to have the backgrounds sync between apps as my google background syncs with
/// samsung messenger"). One for every chat (the `chat_bg` choice) and one a conversation may have of its own
/// (`chat_bg_<thread>`); a conversation with none of its own wears every chat's.
///
/// There is no standard by which texting apps share a background: Google Messages keeps its own on the phone that
/// set it, for RCS chats only, where no other app can read it. What every app on the phone can share is the palette
/// Android takes from the wallpaper (Material You), which is what [ChatBackground.wallpaper] wears: it follows the
/// phone, as Google's and Samsung's apps do.
///
/// A choice is kept as one word: `none`, `wallpaper`, `preset:dusk`, `color:#RRGGBB`, `image:/path/on/this/phone`,
/// and `wash:#..,#..,#..,#..` (a wash's top and bottom in light, then in dark), which is what someone else's
/// "Match my wallpaper" is here.
///
/// A conversation's own background can be synced with the people in it who have Ghost Messaging (Matt, 2026-11-13: "I
/// want the background to sync for everyone in a chat if they're all using ghost messaging"): it goes as a text in
/// the conversation (android/.../BackgroundWire.kt), their copy wears it, and both draw the text as a line.
@immutable
class ChatBackground {
  const ChatBackground(this.kind, [this.value = '']);

  /// none, wallpaper, preset, color, image, wash.
  final String kind;
  final String value;

  static const none = ChatBackground('none');
  static const wallpaper = ChatBackground('wallpaper');

  bool get isNone => kind == 'none';

  /// Words drawn straight on it (a day's heading, "Delivered", a sender's name) need a ground of their own: a
  /// picture or a colour of the person's can be anything. The presets and the wallpaper's palette are made pale
  /// enough in light and deep enough in dark for the page's ink.
  bool get busy => kind == 'image' || kind == 'color';

  String get raw => switch (kind) { 'none' || 'wallpaper' => kind, _ => '$kind:$value' };

  factory ChatBackground.parse(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'none') return none;
    if (raw == 'wallpaper') return wallpaper;
    final at = raw.indexOf(':');
    if (at <= 0) return none;
    final kind = raw.substring(0, at);
    final value = raw.substring(at + 1);
    return switch (kind) {
      'preset' when chatPresets.any((p) => p.id == value) => ChatBackground(kind, value),
      'color' when _hex(value) != null => ChatBackground(kind, value),
      'wash' when value.split(',').length == 4 && value.split(',').every((h) => _hex(h) != null) => ChatBackground(kind, value),
      'image' when value.isNotEmpty => ChatBackground(kind, value),
      _ => none,
    };
  }

  static String threadKey(int thread) => 'chat_bg_$thread';

  /// Every chat's.
  static ChatBackground everyChat(AppState app) => ChatBackground.parse(app.choice('chat_bg', 'none'));

  /// A conversation's own, or null where it wears every chat's.
  static ChatBackground? own(AppState app, int thread) {
    final raw = app.choice(threadKey(thread), '');
    return raw.isEmpty ? null : ChatBackground.parse(raw);
  }

  /// What [thread] wears.
  static ChatBackground of(AppState app, int thread) => own(app, thread) ?? everyChat(app);

  /// The form of this that another phone can wear: itself, but for "Match my wallpaper", whose colours are this
  /// phone's own and go as the four of them. Null where there is nothing to send (no palette on this phone).
  ChatBackground? get shareable {
    if (kind != 'wallpaper') return this;
    final light = PhonePalette.current?.wash(false);
    final dark = PhonePalette.current?.wash(true);
    if (light == null || dark == null) return null;
    String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return ChatBackground('wash', [light.$1, light.$2, dark.$1, dark.$2].map(hex).join(','));
  }

  /// Its name, as Settings says it.
  String get label => switch (kind) {
        'wallpaper' => 'My wallpaper\'s colours',
        'preset' => chatPresets.firstWhere((p) => p.id == value, orElse: () => chatPresets.first).name,
        'color' => 'A colour',
        'image' => 'A picture',
        'wash' => 'Shared colours',
        _ => 'None',
      };

  /// The two ends of the wash it draws; null for a picture and for none.
  (Color, Color)? colors(bool dark) {
    switch (kind) {
      case 'preset':
        final p = chatPresets.firstWhere((p) => p.id == value, orElse: () => chatPresets.first);
        return dark ? (p.darkTop, p.darkBottom) : (p.lightTop, p.lightBottom);
      case 'color':
        final c = _hex(value);
        return c == null ? null : (c, c);
      case 'wash':
        final c = value.split(',').map(_hex).toList();
        if (c.length != 4 || c.contains(null)) return null;
        return dark ? (c[2]!, c[3]!) : (c[0]!, c[1]!);
      case 'wallpaper':
        return PhonePalette.current?.wash(dark) ?? (dark ? (const Color(0xFF10151C), const Color(0xFF182230)) : (const Color(0xFFEEF2F7), const Color(0xFFDFE7F1)));
    }
    return null;
  }
}

Color? _hex(String text) {
  final h = text.trim().replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// A wash made for this app: pale in the light theme, deep in the dark, so the page's ink reads on it.
@immutable
class ChatPreset {
  const ChatPreset(this.id, this.name, this.lightTop, this.lightBottom, this.darkTop, this.darkBottom);
  final String id;
  final String name;
  final Color lightTop;
  final Color lightBottom;
  final Color darkTop;
  final Color darkBottom;
}

const chatPresets = <ChatPreset>[
  ChatPreset('ghost', 'Ghost', Color(0xFFE2FAFA), Color(0xFFD0F1F4), Color(0xFF001F1E), Color(0xFF062B30)),
  ChatPreset('mist', 'Mist', Color(0xFFEEF2F7), Color(0xFFDCE5F0), Color(0xFF0F141B), Color(0xFF172230)),
  ChatPreset('sky', 'Sky', Color(0xFFE3F1FD), Color(0xFFD3E5FB), Color(0xFF0B1929), Color(0xFF10243D)),
  ChatPreset('dusk', 'Dusk', Color(0xFFF2E9F8), Color(0xFFE1DCF6), Color(0xFF191326), Color(0xFF241B3A)),
  ChatPreset('rose', 'Rose', Color(0xFFFDE9EF), Color(0xFFF7DBE8), Color(0xFF28121A), Color(0xFF321526)),
  ChatPreset('dawn', 'Dawn', Color(0xFFFFEFE2), Color(0xFFFBE0E6), Color(0xFF291712), Color(0xFF2C1420)),
  ChatPreset('sand', 'Sand', Color(0xFFF8F1E2), Color(0xFFEEE5D0), Color(0xFF201B11), Color(0xFF2A2214)),
  ChatPreset('mint', 'Mint', Color(0xFFE6F6EE), Color(0xFFD6EFF0), Color(0xFF0C1E19), Color(0xFF0E262A)),
];

/// The colours offered beside the picker for "A colour".
const chatColors = ['#DCE8FB', '#E4DCF7', '#F8DCE6', '#FBE6D4', '#F5EDCB', '#DDF0DC', '#D5EFF0', '#1B2433', '#231B36', '#331922', '#2E2314', '#12261F'];

/// The palette Android takes from the phone's wallpaper (Material You, Android 12 and later; MainActivity's
/// `systemPalette`): what the phone's own apps are coloured by, and so the one look this app can share with them.
/// Read as the app opens and each time it comes back to the front, since the wallpaper may have changed.
@immutable
class PhonePalette {
  const PhonePalette(this._colors);
  final Map<String, Color> _colors;

  static PhonePalette? current;

  /// Returns true when the palette is new.
  static Future<bool> load() async {
    try {
      final raw = await Sms.instance.systemPalette();
      final next = raw == null || raw.isEmpty ? null : PhonePalette({for (final e in raw.entries) e.key: Color(0xFF000000 | (e.value & 0xFFFFFF))});
      final changed = next?._colors.toString() != current?._colors.toString();
      current = next;
      return changed;
    } catch (_) {
      return false;
    }
  }

  Color? operator [](String name) => _colors[name];

  /// Behind a conversation: the accent's palest tones in light, the neutral's deepest warmed by the accent in dark.
  (Color, Color)? wash(bool dark) {
    final top = this[dark ? 'neutral1_900' : 'accent1_50'];
    final bottom = dark ? (this['accent1_800'] == null || this['neutral1_900'] == null ? null : Color.lerp(this['neutral1_900'], this['accent1_800'], 0.45)) : this['accent1_100'];
    return top == null || bottom == null ? null : (top, bottom);
  }

  /// Your own bubbles in the wallpaper's accent, and the words on them.
  (Color, Color)? bubble(bool dark) {
    final ground = this[dark ? 'accent1_200' : 'accent1_600'];
    final ink = dark ? this['accent1_800'] : const Color(0xFFFFFFFF);
    return ground == null || ink == null ? null : (ground, ink);
  }
}

/// The background itself, filling what it is given: a wash from the top to the bottom, or the picture covering it
/// under a veil of the page's ground so bubbles and words keep their footing. Nothing at all for none.
class ChatBackgroundLayer extends StatelessWidget {
  const ChatBackgroundLayer({super.key, required this.background});
  final ChatBackground background;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final b = background;
    if (b.isNone) return const SizedBox.shrink();
    if (b.kind == 'image') {
      return Stack(fit: StackFit.expand, children: [
        Image.file(File(b.value), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (context, _, _) => const SizedBox.shrink()),
        ColoredBox(color: t.color('glacier-bg').withValues(alpha: t.isDark ? 0.42 : 0.28)),
      ]);
    }
    final colors = b.colors(t.isDark);
    if (colors == null) return const SizedBox.shrink();
    return DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [colors.$1, colors.$2])));
  }
}

/// Your own bubbles and the words on them (Settings › Appearance): Ghost Keyboard's primary (KeyboardTheme.kt's accent
/// and onAccent: #51FCFB under #00302F on the dark page, #008B8A under white on the light), the page's ink, or the
/// accent Android takes from the phone's wallpaper.
(Color, Color) myBubble(Tokens t, AppState app) {
  switch (app.bubble) {
    case 'ink':
      return (t.color('app-ink'), t.color('app-paper'));
    case 'wallpaper':
      final w = PhonePalette.current?.bubble(t.isDark);
      if (w != null) return w;
  }
  return (Color(t.isDark ? 0xFF51FCFB : 0xFF008B8A), Color(t.isDark ? 0xFF00302F : 0xFFFFFFFF));
}

/// Someone else's bubble: a shade off the plain page, and the page's own paper where a background is behind it (a
/// shade off a wash would be lost in it).
Color theirBubble(Tokens t, {required bool onBackground}) => t.color(t.isDark ? 'app-paper-3' : (onBackground ? 'app-paper' : 'app-paper-2'));

/// Small words that sit straight on a conversation's background (a day's heading, "Delivered", a sender's name):
/// over a picture or a colour of the person's ([ChatBackground.busy]) they stand on a pill of the page's ground.
class OnBackground extends StatelessWidget {
  const OnBackground({super.key, required this.busy, required this.child});
  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!busy) return child;
    final t = context.tokens;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 2),
      decoration: BoxDecoration(color: t.color('glacier-bg').withValues(alpha: 0.78), borderRadius: BorderRadius.circular(t.lenOf('1rem'))),
      child: child,
    );
  }
}
