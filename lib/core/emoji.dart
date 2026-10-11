/// The emoji shortcodes a note is likely to hold, and nothing else. A port of `src/app/core/emoji.ts`, one to one.
///
/// The parser already reads `:tada:` as an Emoji node, and Ghost.md drew it as the words that were typed. Drawing the
/// emoji itself means replacing text, which the editor only does where what is drawn is unmistakably the same thing
/// as what is written - a table, a picture, an emoji.
///
/// The full CLDR list is some two thousand names and a large file to carry on a phone for a notes app. This is the
/// short list: the ones people actually type, GitHub's names for them, so a note written here reads the same there.
/// A name that is not here stays as the words that were typed, which is the honest fallback.
///
/// What differs: the table is the web's, name for name, and `shortcodesIn` answers records where the web answers
/// object literals. The web looks a name up on a plain object, so `:constructor:` and `:tostring:` find what every
/// JavaScript object inherits and are answered as if they were emoji; a Dart map has no such keys, and they are
/// null here.
library;

const Map<String, String> _emoji = {
  // Faces and hands
  'smile': '😄',
  'grin': '😁',
  'joy': '😂',
  'sweat_smile': '😅',
  'wink': '😉',
  'blush': '😊',
  'thinking': '🤔',
  'neutral_face': '😐',
  'upside_down_face': '🙃',
  'cry': '😢',
  'sob': '😭',
  'scream': '😱',
  'sleeping': '😴',
  'sunglasses': '😎',
  'heart_eyes': '😍',
  'shrug': '🤷',
  'facepalm': '🤦',
  'wave': '👋',
  '+1': '👍',
  'thumbsup': '👍',
  '-1': '👎',
  'thumbsdown': '👎',
  'ok_hand': '👌',
  'clap': '👏',
  'pray': '🙏',
  'muscle': '💪',
  'point_right': '👉',
  'raised_hands': '🙌',
  'handshake': '🤝',
  'eyes': '👀',
  // Marks and signs
  'white_check_mark': '✅',
  'heavy_check_mark': '✔️',
  'x': '❌',
  'warning': '⚠️',
  'exclamation': '❗',
  'question': '❓',
  'no_entry': '⛔',
  'heavy_plus_sign': '➕',
  'heavy_minus_sign': '➖',
  'arrow_right': '➡️',
  'arrow_left': '⬅️',
  'arrow_up': '⬆️',
  'arrow_down': '⬇️',
  'recycle': '♻️',
  'sparkles': '✨',
  'star': '⭐',
  'star2': '🌟',
  'fire': '🔥',
  'boom': '💥',
  'zap': '⚡',
  'bulb': '💡',
  'bell': '🔔',
  'heart': '❤️',
  'broken_heart': '💔',
  'tada': '🎉',
  'confetti_ball': '🎊',
  'gift': '🎁',
  'balloon': '🎈',
  'trophy': '🏆',
  'medal': '🏅',
  // Work and things
  'memo': '📝',
  'pencil': '✏️',
  'book': '📖',
  'books': '📚',
  'bookmark': '🔖',
  'paperclip': '📎',
  'pushpin': '📌',
  'round_pushpin': '📍',
  'calendar': '📅',
  'date': '📆',
  'alarm_clock': '⏰',
  'hourglass': '⏳',
  'watch': '⌚',
  'chart_with_upwards_trend': '📈',
  'chart_with_downwards_trend': '📉',
  'bar_chart': '📊',
  'clipboard': '📋',
  'file_folder': '📁',
  'open_file_folder': '📂',
  'page_facing_up': '📄',
  'inbox_tray': '📥',
  'outbox_tray': '📤',
  'email': '📧',
  'envelope': '✉️',
  'telephone': '☎️',
  'iphone': '📱',
  'computer': '💻',
  'keyboard': '⌨️',
  'printer': '🖨️',
  'camera': '📷',
  'video_camera': '📹',
  'microphone': '🎤',
  'headphones': '🎧',
  'speaker': '🔊',
  'mute': '🔇',
  'battery': '🔋',
  'electric_plug': '🔌',
  'wrench': '🔧',
  'hammer': '🔨',
  'gear': '⚙️',
  'lock': '🔒',
  'unlock': '🔓',
  'key': '🔑',
  'mag': '🔍',
  'link': '🔗',
  'package': '📦',
  'money_with_wings': '💸',
  'moneybag': '💰',
  'credit_card': '💳',
  'receipt': '🧾',
  'shopping_cart': '🛒',
  // Places, weather, food, travel
  'house': '🏠',
  'office': '🏢',
  'hospital': '🏥',
  'school': '🏫',
  'car': '🚗',
  'bus': '🚌',
  'train': '🚆',
  'airplane': '✈️',
  'rocket': '🚀',
  'ship': '🚢',
  'bike': '🚲',
  'walking': '🚶',
  'runner': '🏃',
  'sunny': '☀️',
  'cloud': '☁️',
  'rain': '🌧️',
  'snowflake': '❄️',
  'umbrella': '☂️',
  'rainbow': '🌈',
  'ocean': '🌊',
  'mountain': '⛰️',
  'tree': '🌳',
  'seedling': '🌱',
  'coffee': '☕',
  'tea': '🍵',
  'beer': '🍺',
  'wine_glass': '🍷',
  'pizza': '🍕',
  'apple': '🍎',
  'bread': '🍞',
  'cake': '🍰',
  'birthday': '🎂',
  // Small creatures, for the notes that have them
  'dog': '🐶',
  'cat': '🐱',
  'bug': '🐛',
  'bee': '🐝',
  'turtle': '🐢',
  'whale': '🐳',
  'penguin': '🐧',
};

/// A shortcode's emoji, or null when it is not one of the names Ghost.md knows.
String? emojiFor(String name) => _emoji[name.toLowerCase()];

final RegExp _shortcode = RegExp(r':([a-z0-9_+-]{1,32}):', caseSensitive: false);

/// The shortcodes in a piece of text, with where they sit, for the ones that have an emoji.
List<({int from, int to, String emoji})> shortcodesIn(String text, [int offset = 0]) {
  final found = <({int from, int to, String emoji})>[];
  for (final match in _shortcode.allMatches(text)) {
    final emoji = emojiFor(match.group(1) ?? '');
    if (emoji != null) found.add((from: offset + match.start, to: offset + match.end, emoji: emoji));
  }
  return found;
}
