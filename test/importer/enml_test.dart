import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/importer/enml.dart';

/// Evernote's ENML as Markdown (lib/importer/enml.dart), element by element.
void main() {
  String md(String body, {String? Function(String hash, String type)? media}) =>
      enmlToMarkdown('<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd"><en-note>$body</en-note>', media: media ?? (_, _) => null).markdown;

  test('a div is a line, an empty one a blank line, a <br/> a line break', () {
    expect(md('<div>One</div><div>Two</div><div><br/></div><div>Three<br/>Four<br/></div>'), 'One\nTwo\n\nThree\nFour');
  });

  test('headings, emphasis and strikes, by tag and by style', () {
    expect(md('<h1>Top</h1><h3>Third</h3><div><b>b</b> <strong>s</strong> <i>i</i> <em>e</em> <s>x</s> <del>d</del> <span style="font-weight:700">w</span> <span style="font-style: italic;">it</span> <span style="text-decoration: line-through">lt</span> <u>u</u></div>'),
        '# Top\n\n### Third\n\n**b** **s** *i* *e* ~~x~~ ~~d~~ **w** *it* ~~lt~~ u');
    expect(md('<div><b>bold </b>next</div>'), '**bold** next', reason: 'the mark closes before the space');
  });

  test('lists, nested, ordered and not', () {
    expect(md('<ul><li>a</li><li>b<ul><li>c</li></ul></li></ul><ol><li>one</li><li>two<ol><li>deep</li></ol></li></ol>'), '- a\n- b\n  - c\n\n1. one\n2. two\n   1. deep');
  });

  test('to-dos, as en-todo and as a to-do list', () {
    expect(md('<div><en-todo checked="true"/>Done</div><div><en-todo/>Not yet</div>'), '- [x] Done\n- [ ] Not yet');
    expect(md('<ul style="--en-todo:true;"><li style="--en-checked:true;"><div>Yes</div></li><li style="--en-checked:false;"><div>No</div></li></ul>'), '- [x] Yes\n- [ ] No');
    expect(md('<ul><li><en-todo checked="true"/>In a list</li></ul>'), '- [x] In a list');
  });

  test('a table, its first row the header, short rows filled and a | escaped', () {
    expect(md('<table><tbody><tr><td>A</td><td>B</td></tr><tr><td>x | y</td></tr></tbody></table>'), '| A | B |\n| --- | --- |\n| x \\| y |  |');
  });

  test('links, a link to another Evernote note, code and code blocks', () {
    expect(md('<div><a href="https://x.com/a">words</a> <a href="https://x.com/b">https://x.com/b</a> <a href="evernote:///view/1/s1/g/g/">Other note</a> <code>a`b</code></div>'),
        '[words](https://x.com/a) <https://x.com/b> [[Other note]] ``a`b``');
    expect(md('<div style="-en-codeblock:true"><div>if (a &lt; b) {</div><div>  go();</div><div>}</div></div>'), '```\nif (a < b) {\n  go();\n}\n```');
    expect(md('<pre>one\ntwo</pre>'), '```\none\ntwo\n```');
  });

  test('a quote and a rule', () {
    expect(md('<blockquote><div>Said.</div><div>Twice.</div></blockquote><hr/><div>After</div>'), '> Said.\n> Twice.\n\n---\n\nAfter');
  });

  test('media by hash, a picture on its own line; an unknown hash left out; encrypted text counted', () {
    final out = enmlToMarkdown('<en-note><div>See <en-media hash="ABC" type="image/png"/> and <en-media hash="def" type="application/pdf"/> <en-media hash="nope" type="image/png"/></div><en-crypt>xx</en-crypt></en-note>',
        media: (hash, type) => switch (hash) { 'abc' => '![](image/p.png)', 'def' => '[a.pdf](file/f.pdf)', _ => null });
    expect(out.markdown, 'See\n![](image/p.png)\nand [a.pdf](file/f.pdf)');
    expect(out.used, {'abc', 'def'});
    expect(out.encrypted, 1);
  });

  test('marks in the words are words: escaped where they would be read', () {
    expect(md('<div># not a heading</div><div>- not a list</div><div>2. not a list</div><div>a * b `c` [[d]]</div><div>&gt; not a quote</div>'),
        '\\# not a heading\n\\- not a list\n2\\. not a list\na \\* b \\`c\\` \\[\\[d]]\n\\> not a quote');
  });

  test('entities and unicode', () {
    expect(md('<div>caf&eacute; &amp; 100&nbsp;g — 日本語 🥞 مرحبا</div>'), 'café & 100 g — 日本語 🥞 مرحبا');
  });

  test('ENML that is not well formed is still its words', () {
    final out = enmlToMarkdown('<en-note><div>Open <b>bold</div><div>Next</div>', media: (_, _) => null);
    expect(out.markdown, 'Open bold\nNext');
  });
}
