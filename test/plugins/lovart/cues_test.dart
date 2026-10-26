// `{image: a prompt}` and the inspiration section, pure (lib/plugins/lovart/cues.dart, inspiration.dart): which cues
// are cues, where each picture goes, what Lovart is asked for a note, and which meetings are design meetings.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/blanks_syntax.dart' show blankPattern;
import 'package:ghost_md/plugins/lovart/cues.dart';
import 'package:ghost_md/plugins/lovart/inspiration.dart';

void main() {
  group('cues', () {
    test('finds each {image: …} with its prompt and place, with or without the space, in any case', () {
      const body = '# Brand\n\nA logo {image: a fox in one line} for the cover.\n{IMAGE:sunset over dunes}';
      final cues = imageCues(body);
      expect([for (final c in cues) (c.prompt, c.line)], [('a fox in one line', 3), ('sunset over dunes', 4)]);
      expect(body.substring(cues.first.from, cues.first.to), '{image: a fox in one line}');
      expect(cues.last.text, '{IMAGE:sunset over dunes}');
    });

    test('is a cue only once it is closed and has words, and never a blank, a template, code or an escape', () {
      for (final body in [
        '{image: still typing',
        '{image:   }',
        '{?what day}',
        '{{image: a template}}',
        r'\{image: escaped}',
        '`{image: in code}`',
        '```\n{image: in a fence}\n```',
        r'${image: shell}',
      ]) {
        expect(imageCues(body), isEmpty, reason: body);
      }
      // And a blank is still a blank beside a cue.
      const both = 'On {?what day} {image: a calendar}';
      expect(imageCues(both).single.prompt, 'a calendar');
      expect(blankPattern.allMatches(both).map((m) => m[0]), ['{?what day}']);
    });

    test('a cue on a line of its own becomes the picture, a list’s marker kept', () {
      const body = 'Ideas\n{image: a red chair}\nmore';
      expect(withImage(body, imageCues(body).single, 'lovart-1.png'), 'Ideas\n![a red chair](image/lovart-1.png)\nmore');
      const listed = '- {image: a lamp}';
      expect(withImage(listed, imageCues(listed).single, 'lovart-2.png'), '- ![a lamp](image/lovart-2.png)');
    });

    test('a cue among words leaves the words without it, and the picture on its own line after', () {
      const body = 'The hero shot {image: a misty forest} goes on top.';
      expect(withImage(body, imageCues(body).single, 'lovart-3.png'), 'The hero shot goes on top.\n![a misty forest](image/lovart-3.png)');
    });

    test('several cues, resolved one after another as the note changes', () {
      var body = 'A {image: one} and B {image: two}\n{image: three}';
      final names = ['lovart-a.png', 'lovart-b.png', 'lovart-c.png'];
      for (final name in names) {
        body = withImage(body, imageCues(body).first, name);
      }
      expect(body, 'A and B\n![one](image/lovart-a.png)\n![two](image/lovart-b.png)\n![three](image/lovart-c.png)');
      expect(imageCues(body), isEmpty);
    });

    test('a caption keeps to one line with no bracket to end it early', () {
      expect(pictureCaption('a [bold] idea'), 'a bold idea');
      expect(pictureCaption('x' * 200).length, 120);
    });
  });

  group('inspiration', () {
    test('asks for four images, one each, from the title and the summary where there is one', () {
      const meeting = '# Homepage redesign\n\n## Summary\n\nWe chose a calmer layout with more white space.\n\n- Sam: wireframes by Friday\n\nTranscript words that should not go.';
      final prompt = inspirationPrompt(meeting);
      expect(prompt, startsWith('Make a moodboard of 4 inspiration images for the ideas in this note, “Homepage redesign”.'));
      expect(prompt, contains('one image each'));
      expect(prompt, contains('calmer layout'));
      expect(prompt, isNot(contains('Transcript words')));
    });

    test('takes the note’s first 1500 characters where it has no summary, its pictures left out', () {
      final body = '# Notes\n\n![old](image/x.png)\n${'word ' * 600}';
      final prompt = inspirationPrompt(body);
      expect(prompt, isNot(contains('image/x.png')));
      expect(prompt.split('The note:\n').last.length, lessThanOrEqualTo(inspirationChars + 1));
    });

    test('adds an Inspiration section at the end, or to the one there is', () {
      expect(withInspiration('# Moodboard\n\nIdeas.\n', ['lovart-1.png', 'lovart-2.png']), '# Moodboard\n\nIdeas.\n\n## Inspiration\n\n![Inspiration](image/lovart-1.png)\n![Inspiration](image/lovart-2.png)\n');
      const has = '# M\n\n## Inspiration\n\n![Inspiration](image/lovart-1.png)\n\n## Next steps\n\n- ship';
      expect(withInspiration(has, ['lovart-9.png']), '# M\n\n## Inspiration\n\n![Inspiration](image/lovart-1.png)\n![Inspiration](image/lovart-9.png)\n\n## Next steps\n\n- ship');
    });
  });

  group('design meetings', () {
    test('a design word in the title is enough', () {
      expect(looksLikeDesignMeeting('Logo review', ''), isTrue);
      expect(looksLikeDesignMeeting('UX sync', ''), isTrue);
      expect(looksLikeDesignMeeting('Mood board for the launch', ''), isTrue);
    });

    test('in the summary it takes two different ones, so a stand-up that names the UI once is not one', () {
      expect(looksLikeDesignMeeting('Engineering standup', 'Fixed the login bug; the UI tests are flaky.'), isFalse);
      expect(looksLikeDesignMeeting('Weekly', 'Reviewed the mockups and settled the colour palette.'), isTrue);
    });

    test('whole words only', () {
      expect(looksLikeDesignMeeting('Designated driver rota', 'Build quotas and guidance.'), isFalse);
    });
  });
}
