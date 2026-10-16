import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/block_ids.dart';

/// The places inside a note a link can point at (lib/core/block_ids.dart): a named line and a heading, what an
/// embed draws of each, and a name made for a line that has none.
void main() {
  const body = '---\ntitle: Trip\n---\n# Trip\n\nThe ferry leaves at nine. ^ferry\n\n## Packing\n\n- Shoes ^shoes\n  - The old ones\n- Charger\n\n```\nnot a heading ^code\n# nor this\n```\n\n### Later\n\nWords.\n\n## Coast\n\nSea.';

  test('a named line, any line, and none in a code block', () {
    expect(blockIdOf('The ferry leaves at nine. ^ferry')?.id, 'ferry');
    expect(blockIdOf('E = mc^2'), isNull);
    expect(blockLine(body, 'ferry'), 6);
    expect(blockLine(body, 'shoes'), 10);
    expect(blockLine(body, 'code'), isNull);
    expect(blockIdsIn(body), {'ferry', 'shoes'});
  });

  test('the headings, by level and line, none in a code block', () {
    expect([for (final heading in headingsOf(body)) (heading.level, heading.text, heading.line)], [(1, 'Trip', 4), (2, 'Packing', 8), (3, 'Later', 19), (2, 'Coast', 23)]);
    expect(headingNamed(body, 'packing')?.line, 8);
    expect(anchorLine(body, '^ferry'), 6);
    expect(anchorLine(body, 'Coast'), 23);
    expect(anchorLine(body, 'Nowhere'), isNull);
  });

  test('what an embed draws: a heading and what is under it, a named line and its own items', () {
    expect(sectionOf(body, 'Packing'), '## Packing\n\n- Shoes ^shoes\n  - The old ones\n- Charger\n\n```\nnot a heading ^code\n# nor this\n```\n\n### Later\n\nWords.');
    expect(sectionOf(body, 'Coast'), '## Coast\n\nSea.');
    expect(sectionOf(body, '^shoes'), '- Shoes ^shoes\n  - The old ones');
    expect(sectionOf(body, '^ferry'), 'The ferry leaves at nine. ^ferry');
    expect(sectionOf(body, '^gone'), isNull);
  });

  test('a name made for a line from its words, not one taken, and written at its end once', () {
    expect(blockIdFor('- [ ] Ask Sam about the photos', const []), 'ask-sam-about');
    expect(blockIdFor('The ferry leaves', const ['ferry-leaves']), 'ferry-leaves-2');
    expect(withBlockId('The ferry leaves  ', 'ferry'), 'The ferry leaves ^ferry');
    expect(withBlockId('The ferry ^ferry', 'other'), 'The ferry ^ferry');
    expect(placeLink('Trip', '^ferry'), '[[Trip#^ferry]]');
    expect(linkTitle('# Trip [one] | two'), 'Trip one  two');
  });
}
