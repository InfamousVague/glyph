// The Academy held to the web page's own rectangles. fixtures/web_academy.mjs drew the page in Chromium on the web
// app's dev server at 390 x 844 (every request but the dev server's aborted) and wrote fixtures/<page>.json; here the
// same progress is kept, the same presses made, and each thing's rectangle is asserted against the page's to half a
// pixel. The page had no status bar over it and the screen has a test's 36 px one, so the two are laid over one
// another at the back arrow.
//
// The rows that are `<button>`s on the page are in the browser's own button face there (academy_screen.dart's
// header); for these tests they are drawn in the Mac's Arial, as Chromium drew them, so their words wrap where the
// page's did. Without that file the tests of those rows are skipped.
//
// Where the redesign leaves the page on purpose (Matt, 2026-10-28: "spice up the academy with more colors and
// iconography"), the page is held from below it: a band now heads the card, so after the top bar the two are laid
// over one another again at the first thing under the band (the title on the contents, the chapter's words on a
// lesson and a chapter's end), and the card is held only across. The speaker at the end of the top bar narrows the
// heading and moves the count, which are held only down. On the contents each chapter's row is a coloured tile and
// words with more room round them, so the rows are held only across, and the lines under them from the next thing
// the page and the screen share (the cheat sheet's line).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/academy/academy_screen.dart';
import 'package:ghost_md/academy/lessons.dart';
import 'package:ghost_md/art/app_icon.dart';
import 'package:ghost_md/home/home_parts.dart' show CssLines;

import 'support.dart';

const learnedSome = {'title', 'heading', 'bold', 'italic', 'both', 'struck', 'code', 'link', 'list', 'number', 'todo', 'quote', 'rule', 'fence', 'wiki', 'bookmark'};

void main() {
  var arial = false;
  setUpAll(() async {
    await loadAppFonts();
    arial = await loadButtonFace();
  });
  setUp(() => academyButtonFace = arial ? 'Arial' : null);
  tearDown(() => academyButtonFace = null);

  /// The icon inside the thing of that key.
  Finder icon(String name) => find.descendant(of: key(name), matching: find.byType(AppIcon));

  /// The line at the top and the card's own words, which every page of the Academy has.
  void top(WidgetTester tester, Held held, {bool bars = false, required String below}) {
    held.anchor('back', tester.getRect(key('academy-back')));
    held.check('back', rectsOf(tester, key('academy-back')));
    held.check('backIcon', rectsOf(tester, icon('academy-back')));
    held.check('headingIcon', rectsOf(tester, icon('academy-heading')));
    held.check('heading', rectsOf(tester, key('academy-heading')), dims: 'xyh');
    held.check('count', rectsOf(tester, key('academy-count')), dims: 'yh');
    if (bars) {
      held.check('bars', rectsOf(tester, find.descendant(of: key('academy-bars'), matching: find.byType(Row))));
      held.check('bar', rectsOf(tester, find.descendant(of: key('academy-bars'), matching: find.byType(AnimatedContainer))));
    }
    held.check('card', rectsOf(tester, key('academy-card')), dims: 'xw');
    // Under the band: the page again, from [below] down.
    held.anchor(below, tester.getRect(key(below == 'title' ? 'academy-title' : 'academy-chapter')));
    held.check('title', rectsOf(tester, key('academy-title')));
  }

  /// The box of some words' lines at the page's own line height.
  Finder lined(Finder words) => find.ancestor(of: words, matching: find.byType(CssLines));

  List<Rect> each(WidgetTester tester, String prefix, Iterable<String> names) => [for (final name in names) tester.getRect(key('$prefix:$name'))];

  testWidgets('the contents are the page’s, rect for rect', (tester) async {
    freshDevice();
    await showAcademy(tester);
    final held = Held(Reference('contents'));
    top(tester, held, below: 'title');
    held.check('teach', [tester.getRect(lined(find.textContaining('A mark at a time')))]);
    held.check('go', rectsOf(tester, key('academy-go')));
    held.check('goIcon', rectsOf(tester, icon('academy-go')));
    held.check('skip', rectsOf(tester, key('academy-skip')));
    held.check('skipWords', rectsOf(tester, key('academy-skip-words')));
    held.check('skipName', rectsOf(tester, find.text('I know Markdown already')));
    held.check('skipSaid', rectsOf(tester, key('academy-skip-said')));
    if (arial) {
      held.check('chapters', rectsOf(tester, key('academy-chapters')), dims: 'xw');
      held.check('chapterRow', each(tester, 'chapter', chapters), dims: 'xw');
    }
    // Under the chapters, from the cheat sheet's line down.
    final sheetLine = tester.getRect(lined(find.textContaining('Every mark is in the cheat sheet')));
    held.anchor('teach', sheetLine, at: 1);
    held.check('teach', [sheetLine], from: 1);
    held.check('foot', rectsOf(tester, key('academy-foot')));
    held.check('footButtons', [tester.getRect(key('academy-start-again')), tester.getRect(key('academy-cheat-sheet'))]);
    held.check('footIcons', [tester.getRect(icon('academy-start-again')), tester.getRect(icon('academy-cheat-sheet'))]);
    held.done();
    expect(held.checked, greaterThan(arial ? 25 : 14));
    await away(tester);
  });

  testWidgets('a lesson and its playground are the page’s, rect for rect', (tester) async {
    freshDevice();
    await showAcademy(tester);
    await press(tester, key('academy-go'));
    final held = Held(Reference('lesson'));
    top(tester, held, bars: true, below: 'chapter');
    held.check('chapter', rectsOf(tester, key('academy-chapter')));
    held.check('teach', rectsOf(tester, lined(find.text(lessons.first.teach))));
    held.check('example', rectsOf(tester, key('academy-example')));
    held.check('exampleText', rectsOf(tester, key('academy-example-text')));
    held.check('showMe', rectsOf(tester, key('academy-show-me')));
    held.check('showMeIcon', rectsOf(tester, icon('academy-show-me')));
    held.check('task', rectsOf(tester, key('academy-task')));
    held.check('playground', rectsOf(tester, key('playground')));
    held.check('part', [tester.getRect(key('playground-typed')), tester.getRect(key('playground-shows'))]);
    held.check('label', [tester.getRect(find.text('YOU TYPE')), tester.getRect(find.text('YOUR NOTE SHOWS'))]);
    held.check('field', rectsOf(tester, key('playground-field')));
    held.check('shown', rectsOf(tester, key('playground-shown')));
    held.check('waiting', rectsOf(tester, key('playground-waiting')));
    held.check('foot', rectsOf(tester, key('academy-foot')));
    held.check('footButtons', [tester.getRect(find.ancestor(of: find.text('Show me a hint'), matching: find.byType(ConstrainedBox)).first), tester.getRect(key('academy-next'))]);
    held.done();
    expect(held.checked, greaterThan(35));
    await away(tester);
  });

  testWidgets('a lesson passed, with the note drawn under it, is the page’s', (tester) async {
    freshDevice();
    await showAcademy(tester);
    await press(tester, key('academy-go'));
    await press(tester, key('academy-show-me'));
    final held = Held(Reference('lesson-passed'));
    top(tester, held, bars: true, below: 'chapter');
    held.check('playground', rectsOf(tester, key('playground')));
    held.check('part', [tester.getRect(key('playground-typed')), tester.getRect(key('playground-shows'))]);
    held.check('field', rectsOf(tester, key('playground-field')));
    held.check('shown', rectsOf(tester, key('playground-shown')));
    held.check('editor', rectsOf(tester, key('playground-note')));
    held.check('foot', rectsOf(tester, key('academy-foot')));
    held.check('praise', rectsOf(tester, key('academy-praise')));
    held.check('praiseIcon', rectsOf(tester, icon('academy-praise')));
    held.check('footButtons', rectsOf(tester, key('academy-next')));
    held.done();
    await away(tester);
  });

  testWidgets('a lesson’s hint is where the page puts it', (tester) async {
    freshDevice();
    await showAcademy(tester);
    await press(tester, key('academy-go'));
    await press(tester, find.text('Show me a hint'));
    final held = Held(Reference('lesson-hint'));
    top(tester, held, bars: true, below: 'chapter');
    held.check('hint', rectsOf(tester, key('academy-hint')));
    held.check('foot', rectsOf(tester, key('academy-foot')));
    held.check('footButtons', rectsOf(tester, key('academy-next')));
    held.done();
    await away(tester);
  });

  testWidgets('the contents with some of it learned are the page’s', (tester) async {
    freshDevice(learned: learnedSome);
    await showAcademy(tester);
    final held = Held(Reference('contents-begun'));
    top(tester, held, below: 'title');
    held.check('go', rectsOf(tester, key('academy-go')));
    held.check('skip', rectsOf(tester, key('academy-skip')));
    if (arial) held.check('chapterRow', each(tester, 'chapter', chapters), dims: 'xw');
    held.done();
    await away(tester);
  });

  testWidgets('the end of a chapter is the page’s, its buttons squeezed as the page squeezes them', (tester) async {
    freshDevice(learned: learnedSome);
    await showAcademy(tester);
    await press(tester, key('chapter:Links and places'));
    await press(tester, key('academy-next'));
    final its = [for (final lesson in lessonsIn('Links and places')) lesson.id];
    final held = Held(Reference('chapter-end'));
    top(tester, held, bars: true, below: 'chapter');
    held.check('chapter', rectsOf(tester, key('academy-chapter')));
    held.check('teach', rectsOf(tester, lined(find.textContaining('You can come back'))));
    held.check('list', rectsOf(tester, key('academy-list')));
    held.check('again', each(tester, 'again', its));
    held.check('againTick', each(tester, 'again-tick', its));
    held.check('againMark', each(tester, 'again-mark', its));
    if (arial) held.check('againName', each(tester, 'again-name', its));
    held.check('foot', rectsOf(tester, key('academy-foot')));
    held.check('footButtons', [tester.getRect(key('academy-all-chapters')), tester.getRect(key('academy-next-chapter'))]);
    held.done();
    await away(tester);
  });
}
