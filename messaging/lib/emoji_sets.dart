/// The emoji sets the person chooses between in Settings › Look (Matt, 2026-11-13: "give the user a suite of emoji
/// libraries to choose from"). Each but the phone's own is a font the app carries (assets/emoji/, with its licence in
/// LICENSES.md), put first among the fallbacks of the page's faces: Inter has no emoji, so the set chosen draws
/// every one, in messages, the composer, reactions and notifications' previews in the app alike.
class EmojiSet {
  const EmojiSet(this.id, this.name, this.family, this.about);
  final String id;
  final String name;

  /// The font family in pubspec.yaml, or null for the emoji Android itself draws.
  final String? family;
  final String about;
}

const emojiSets = [
  EmojiSet('system', 'This phone\'s', null, 'What Android draws: Samsung\'s on a Galaxy, Google\'s on a Pixel.'),
  EmojiSet('noto', 'Noto', 'Ghost Emoji Noto', 'Google\'s, as on a Pixel and in Google Messages.'),
  EmojiSet('twemoji', 'Twemoji', 'Ghost Emoji Twemoji', 'Flat and bright, from Twitter and Discord.'),
  EmojiSet('openmoji', 'OpenMoji', 'Ghost Emoji OpenMoji', 'Hand-drawn outlines with flat colour.'),
  EmojiSet('outline', 'Outline', 'Ghost Emoji Outline', 'One colour, in the text\'s own ink.'),
];

EmojiSet emojiSet(String id) => emojiSets.firstWhere((s) => s.id == id, orElse: () => emojiSets.first);

/// Shown in each set's row in Settings, one at a time: a face, a heart with its variation selector, a skin tone, a
/// joined family, a flag and the ghost.
const emojiSample = ['😀', '❤️', '👍🏽', '👨‍👩‍👧', '🇺🇸', '🎉', '👻'];
