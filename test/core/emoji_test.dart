import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/emoji.dart';

/// The emoji shortcodes (lib/core/emoji.dart). The web has no test file for `core/emoji.ts`; these cases are written
/// from its comments: the short list, GitHub's names, and a name that is not there staying the words that were typed.
void main() {
  group('a shortcode’s emoji', () {
    test('is GitHub’s for the names people type, in any case', () {
      expect(emojiFor('tada'), '🎉');
      expect(emojiFor('TADA'), '🎉');
      expect(emojiFor('+1'), '👍');
      expect(emojiFor('thumbsup'), '👍');
      expect(emojiFor('-1'), '👎');
      expect(emojiFor('white_check_mark'), '✅');
      expect(emojiFor('heart'), '❤️');
      expect(emojiFor('penguin'), '🐧');
    });

    test('is nothing for a name that is not on the short list', () {
      expect(emojiFor('not_an_emoji'), isNull);
      expect(emojiFor(''), isNull);
      expect(emojiFor('constructor'), isNull);
    });
  });

  group('the shortcodes in a text', () {
    test('are found with where they sit, colons and all', () {
      expect(shortcodesIn('Shipped :tada: and :rocket:'), [(from: 8, to: 14, emoji: '🎉'), (from: 19, to: 27, emoji: '🚀')]);
      expect(shortcodesIn(':+1:'), [(from: 0, to: 4, emoji: '👍')]);
    });

    test('leave a name that is not one as the words that were typed', () {
      expect(shortcodesIn('at 10:30:45 or :nope: or : tada :'), isEmpty);
      expect(shortcodesIn(''), isEmpty);
    });

    test('count from an offset', () {
      expect(shortcodesIn('a :fire:', 10), [(from: 12, to: 18, emoji: '🔥')]);
    });
  });
}
