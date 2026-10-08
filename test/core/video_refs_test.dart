import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/video_refs.dart';

/// How a note names a film (lib/core/video_refs.dart), case for case with the web's `core/videoRefs.test.ts`: a
/// poster picture linked to it, whose film no picture pipeline takes for a picture.
///
/// What differs: the web also asks its pictures' reader (`core/imageRefs.ts` `imageNames`, not ported yet) that the
/// poster is carried and the film is not, and reads the Rust twin's list out of `src-tauri/src/videos.rs`; neither
/// is here to ask, so those two checks wait for the pictures' port. The kinds are held to the list as written.

const String line = '[![video 0:12](image/0f8e-poster.jpg)](video/0f8e7c1a-1b2c-4d5e-8f90-a1b2c3d4e5f6.mp4)';

void main() {
  group('a film in the words', () {
    test('is written as its poster linked to it, with its length', () {
      expect(videoMarkdown('0f8e-poster.jpg', '0f8e7c1a-1b2c-4d5e-8f90-a1b2c3d4e5f6.mp4', 12300), line);
      expect(videoMarkdown('p.jpg', 'f.webm', 3723000), '[![video 1:02:03](image/p.jpg)](video/f.webm)');
    });

    test('names its film once, however often the body says it', () {
      const body = '# Harbour\n\n$line\n\n![](image/other.jpg)\n';
      expect(videoNames(body), ['0f8e7c1a-1b2c-4d5e-8f90-a1b2c3d4e5f6.mp4']);
      expect(videoNames('$body$line\n'), hasLength(1));
    });

    test('is a line of its own, whatever its lead, and nothing else is', () {
      for (final each in [line, '- $line', '1. $line', '> $line', '- [ ] $line', '  $line  ']) {
        expect(
          videoOfLine(each),
          const VideoLine(poster: '0f8e-poster.jpg', video: '0f8e7c1a-1b2c-4d5e-8f90-a1b2c3d4e5f6.mp4', alt: 'video 0:12', ms: 12000),
          reason: each,
        );
      }
      for (final each in [
        'Look $line',
        '$line here',
        '![video 0:12](image/p.jpg)',
        '[![video 0:12](image/p.jpg)](video/f.mkv)',
        '[![video 0:12](image/p.jpg)](video/../f.mp4)',
        '[![video 0:12](https://x/p.jpg)](video/f.mp4)',
        '[a film](video/f.mp4)',
      ]) {
        expect(videoOfLine(each), isNull, reason: each);
      }
    });

    test('reads its length back from the alt, and says one it cannot read as none', () {
      expect(lengthOf('video 0:12'), 12000);
      expect(lengthOf('video 12:04'), 724000);
      expect(lengthOf('video 1:02:03'), 3723000);
      expect(lengthOf('video'), isNull);
      expect(lengthOf('a walk'), isNull);
      expect(videoOfLine('[![video](image/p.jpg)](video/f.mp4)')?.ms, isNull);
    });

    test('says its length as a person reads it, a second at least for any film', () {
      expect(lengthText(0), '0:00');
      expect(lengthText(300), '0:01');
      expect(lengthText(12499), '0:12');
      expect(lengthText(59600), '1:00');
      expect(lengthText(724000), '12:04');
      expect(lengthText(3723000), '1:02:03');
    });
  });

  group('the kinds of film', () {
    test('are the four the phone keeps, each of which a line names', () {
      expect([...videoExtensions]..sort(), ['m4v', 'mov', 'mp4', 'webm']);
      for (final kind in videoExtensions) {
        expect(videoNames('[![video 0:01](image/p.jpg)](video/f.$kind)'), ['f.$kind'], reason: kind);
      }
    });
  });
}
