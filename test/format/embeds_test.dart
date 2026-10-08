// A port of src/app/format/embeds.test.ts.
//
// A place or a video line through the model (format/embeds.dart): swapped for a picture-shaped token the model
// copies, and put back exactly, so a model can neither move a place's coordinates nor describe it.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/format/embeds.dart';

const cais = '[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)';
const video = '[![video 0:12](image/poster.jpg)](video/0f8fad5b-d9cb-469f-a165-70867728950e.mp4)';

void main() {
  group('a place or a video line through the model', () {
    test('goes in as a token line and comes back as written, lead and all', () {
      const body = '# Lisbon\n\nLunch\n- $cais\n\n$video\n';
      final guarded = protectEmbeds(body);
      expect(guarded.text, '# Lisbon\n\nLunch\n![place-1](place)\n\n![video-1](video)\n');
      expect(guarded.text, isNot(contains('geo:')));
      expect(restoreEmbeds(guarded.text, guarded.embeds), body);
    });

    test('comes back however the model wrote the token, and on a line of its own when it was buried in words', () {
      final embeds = protectEmbeds('$cais\n$cais\n').embeds;
      expect(restoreEmbeds('[place-1]\nplace 2\n', embeds), '$cais\n$cais\n');
      expect(restoreEmbeds('We ate at ![place-1](place) by the river.', embeds.sublist(0, 1)), 'We ate at \n\n$cais\n\n by the river.');
    });

    test('is never read as another’s token once it is back, whatever the place is called', () {
      const market = '[Market place 2](geo:38.7100,-9.1400)';
      final guarded = protectEmbeds('$market\n$cais\n');
      expect(restoreEmbeds(guarded.text, guarded.embeds), '$market\n$cais\n');
    });

    test('is added at the end when the model lost it, except in a summary, which may leave it out', () {
      final embeds = protectEmbeds('Lunch\n$cais').embeds;
      expect(restoreEmbeds('Lunch was lovely.', embeds), 'Lunch was lovely.\n\n$cais\n');
      expect(restoreEmbeds('Lunch was lovely.', embeds, isFinal: true, appendMissing: false), 'Lunch was lovely.');
      // Still streaming: only what has come is put back.
      expect(restoreEmbeds('Lunch was', embeds, isFinal: false), 'Lunch was');
    });

    test('leaves a place inside words, and one in code, to the words and the code', () {
      const body = 'Met at $cais\n\n```\n$cais\n```';
      expect(protectEmbeds(body), const ProtectedEmbeds(text: body, embeds: []));
    });
  });
}
