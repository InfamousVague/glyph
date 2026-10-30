import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note_buttons.dart';

/// Buttons in a note, read and written (lib/core/note_buttons.dart; Matt, 2026-10-30, of a list of plain-Markdown
/// features: "add all 12"): `[label](ghost:verb?values)`, every verb, a value's spaces and escapes, round trips, and
/// nothing read inside code or from an address that is not a button's.
void main() {
  test('every verb is read with its values, and where it lies', () {
    const text = 'Done? [Move to done](ghost:set?status=Done)\n- [Tell the team](ghost:post?to=slack&channel=launch&text=Shipped%20it)\n[Tidy](ghost:claude?rule=Tidy+my+notes) [Roadmap](ghost:open?note=Roadmap) [Log a bug](ghost:new?template=Bug%20report&in=Kiln)';
    final buttons = buttonsIn(text);
    expect([for (final b in buttons) b.verb], [ButtonVerb.set, ButtonVerb.post, ButtonVerb.claude, ButtonVerb.open, ButtonVerb.make]);
    expect(buttons[0].values, {'status': 'Done'});
    expect(buttons[0].from, 6);
    expect(text.substring(buttons[0].from, buttons[0].to), '[Move to done](ghost:set?status=Done)');
    expect(buttons[1].values, {'to': 'slack', 'channel': 'launch', 'text': 'Shipped it'});
    expect(buttons[2]['rule'], 'Tidy my notes', reason: 'a + is a space too');
    expect(buttons[3]['note'], 'Roadmap');
    expect(buttons[4].values, {'template': 'Bug report', 'in': 'Kiln'});
  });

  test('a button is written as it is read back, a space as %20 and a bracket in its label escaped', () {
    const button = NoteButton(label: 'Move [now]', verb: ButtonVerb.set, values: {'status': 'In progress', 'assignee': 'Sam Lee'});
    expect(button.markdown, r'[Move \[now\]](ghost:set?status=In%20progress&assignee=Sam%20Lee)');
    final back = buttonsIn('Go: ${button.markdown}').single;
    expect(back.label, 'Move [now]');
    expect(back.values, button.values);
    expect(back.markdown, button.markdown);
    expect(buttonOf('Open', 'ghost:open?url=https%3A%2F%2Fghostmarkdown.com')!['url'], 'https://ghostmarkdown.com');
  });

  test('an address in angle brackets is read, as CommonMark reads one with a space', () {
    expect(buttonsIn('[Move](<ghost:set?status=In progress>)').single['status'], 'In progress');
  });

  test('nothing is read inside code, from an image, or from an address that is not a button’s', () {
    expect(buttonsIn('`[Move](ghost:set?status=Done)`'), isEmpty);
    expect(buttonsIn('```\n[Move](ghost:set?status=Done)\n```\n'), isEmpty);
    expect(buttonsIn('![Move](ghost:set?status=Done)'), isEmpty);
    expect(buttonsIn('[Move](ghost:launch?status=Done)'), isEmpty, reason: 'no such verb');
    expect(buttonsIn('[Move](https://example.com)'), isEmpty);
    expect(buttonsIn('```\ncode\n```\n[Move](ghost:set?status=Done)').single.verb, ButtonVerb.set, reason: 'after the fence closes');
  });

  test('which ask first, which run where the note cannot be changed, and what each says it does', () {
    expect(buttonOf('a', 'ghost:post?to=discord')!.asksFirst, isTrue);
    expect(buttonOf('a', 'ghost:claude?prompt=Hi')!.asksFirst, isTrue);
    expect(buttonOf('a', 'ghost:set?status=Done')!.asksFirst, isFalse);
    expect(buttonOf('a', 'ghost:open?note=X')!.runsReadOnly, isTrue);
    expect(buttonOf('a', 'ghost:set?status=Done')!.runsReadOnly, isFalse);
    expect(buttonOf('a', 'ghost:set?status=Done&assignee=')!.does, 'Sets status to Done and assignee to nothing.');
    expect(buttonOf('a', 'ghost:post?to=discord&channel=general')!.does, 'Posts this note to Discord, general.');
    expect(buttonOf('a', 'ghost:new?template=Bug%20report&in=Kiln')!.does, 'Makes a note from “Bug report” in Kiln.');
  });
}
