import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/short_url.dart';

/// A link's address, shortened (lib/core/short_url.dart). The web has no test file for `core/shortUrl.ts`; these
/// cases are written from its comments: "the first 3 chars after the tld then a ... and the last 3 chars".
void main() {
  group('an address, shortened', () {
    test('keeps the host without its scheme and www, then three characters either end of the rest', () {
      expect(shortUrl('https://www.notion.so/attackfm/Launch-plan-9f2b3c'), 'notion.so/att…b3c');
      expect(shortUrl('http://example.com/a/long/path/to/a/page.html'), 'example.com/a/l…tml');
      expect(shortUrl('  https://WWW.Example.com/abcdefghij  '), 'Example.com/abc…hij');
    });

    test('keeps a short path whole, since shortening it would save nothing', () {
      expect(shortUrl('https://attack.fm/glyph'), 'attack.fm/glyph');
      expect(shortUrl('https://attack.fm/123456789'), 'attack.fm/123456789');
      expect(shortUrl('https://attack.fm/1234567890'), 'attack.fm/123…890');
    });

    test('is the host alone where nothing follows it, slashes at either end not counted', () {
      expect(shortUrl('https://attack.fm/'), 'attack.fm');
      expect(shortUrl('https://attack.fm'), 'attack.fm');
      expect(shortUrl('attack.fm///'), 'attack.fm');
      expect(shortUrl('https://attack.fm/glyph/'), 'attack.fm/glyph');
    });

    test('counts a query or a fragment as what follows the host', () {
      expect(shortUrl('https://x.y?q=1'), 'x.y/?q=1');
      expect(shortUrl('https://x.y#section-twelve'), 'x.y/#se…lve');
    });

    test('shortens every http address in running text, and stops at a bracket or a space', () {
      expect(shortenUrls('See https://www.notion.so/attackfm/Launch-plan-9f2b3c today'), 'See notion.so/att…b3c today');
      expect(shortenUrls('[doc](https://www.notion.so/attackfm/Launch-plan-9f2b3c) and <HTTP://a.b/c>'), '[doc](notion.so/att…b3c) and <a.b/c>');
      expect(shortenUrls('no address here, nor ftp://a.b/c'), 'no address here, nor ftp://a.b/c');
    });
  });
}
