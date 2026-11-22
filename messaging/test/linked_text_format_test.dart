import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_messaging/mentions.dart';
import 'package:ghost_messaging/ui/markdown_field.dart';
import 'package:ghost_messaging/ui/thread.dart' show LinkedText;

/// A message's formatting as LinkedText draws it (GMFB-35): markers not drawn, links and mentions still pressable
/// inside formatting, a spoiler inked over until pressed.
const _ink = Color(0xFF222222);

Widget _host(Widget child) => Directionality(textDirection: TextDirection.ltr, child: Center(child: child));

List<TextSpan> _spans(WidgetTester tester) {
  final rich = tester.widget<RichText>(find.byType(RichText).first);
  final out = <TextSpan>[];
  rich.text.visitChildren((s) {
    if (s is TextSpan && s.text != null) out.add(s);
    return true;
  });
  return out;
}

void main() {
  testWidgets('markers are not drawn and the words are formatted', (tester) async {
    await tester.pumpWidget(_host(const LinkedText('a **bold** and ~~gone~~ `x`', ink: _ink, style: TextStyle(fontSize: 14, color: _ink))));
    final spans = _spans(tester);
    expect(spans.map((s) => s.text).join(), 'a bold and gone x');
    expect(spans.firstWhere((s) => s.text == 'bold').style!.fontWeight, FontWeight.w700);
    expect(spans.firstWhere((s) => s.text == 'gone').style!.decoration, TextDecoration.lineThrough);
    expect(spans.firstWhere((s) => s.text == 'x').style!.fontFamily, 'JetBrains Mono Variable');
  });

  testWidgets('a link and a mention inside formatting still press', (tester) async {
    Mention? pressed;
    const text = '**see https://x.com** *@Maya*';
    await tester.pumpWidget(_host(LinkedText(text, ink: _ink, style: const TextStyle(fontSize: 14, color: _ink), mentions: const [Mention(23, 5, 'maya1')], onMention: (m) => pressed = m)));
    final spans = _spans(tester);
    expect(spans.map((s) => s.text).join(), 'see https://x.com @Maya');
    final link = spans.firstWhere((s) => s.text == 'https://x.com');
    expect(link.recognizer, isA<TapGestureRecognizer>());
    expect(link.style!.fontWeight, FontWeight.w700);
    final mention = spans.firstWhere((s) => s.text == '@Maya');
    expect(mention.style!.fontStyle, FontStyle.italic);
    (mention.recognizer! as TapGestureRecognizer).onTap!();
    expect(pressed, const Mention(23, 5, 'maya1'));
  });

  testWidgets('a link written in code is not a link', (tester) async {
    await tester.pumpWidget(_host(const LinkedText('`https://x.com`', ink: _ink, style: TextStyle(fontSize: 14, color: _ink))));
    expect(_spans(tester).single.recognizer, isNull);
  });

  testWidgets('a spoiler is inked over until pressed', (tester) async {
    await tester.pumpWidget(_host(const LinkedText('the end: ||he dies||', ink: _ink, style: TextStyle(fontSize: 14, color: _ink))));
    var secret = _spans(tester).firstWhere((s) => s.text == 'he dies');
    expect(secret.style!.backgroundColor, _ink);
    expect(secret.semanticsLabel, 'Spoiler, tap to reveal');
    (secret.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    secret = _spans(tester).firstWhere((s) => s.text == 'he dies');
    expect(secret.style!.backgroundColor, isNot(_ink));
    expect(secret.recognizer, isNull);
  });

  testWidgets('a quote has a bar in place of its marker', (tester) async {
    await tester.pumpWidget(_host(const LinkedText('> said\nok', ink: _ink, style: TextStyle(fontSize: 14, color: _ink))));
    expect(_spans(tester).map((s) => s.text).join(), '▍ said\nok');
  });

  testWidgets('words under a link open its address', (tester) async {
    await tester.pumpWidget(_host(const LinkedText('read [the docs](https://gogho.st/docs)', ink: _ink, style: TextStyle(fontSize: 14, color: _ink))));
    final spans = _spans(tester);
    expect(spans.map((s) => s.text).join(), 'read the docs');
    final words = spans.firstWhere((s) => s.text == 'the docs');
    expect(words.recognizer, isA<TapGestureRecognizer>());
    expect(words.semanticsLabel, 'Link: the docs, https://gogho.st/docs');
  });

  group('MarkdownController', () {
    testWidgets('dims the markers in the composer', (tester) async {
      final c = MarkdownController(text: 'a **b** c');
      late BuildContext ctx;
      await tester.pumpWidget(_host(Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      })));
      final span = c.buildTextSpan(context: ctx, style: const TextStyle(color: _ink), withComposing: false);
      final parts = [for (final s in span.children!) s as TextSpan];
      expect(parts.map((s) => s.text).join(), 'a **b** c');
      expect(parts.where((s) => s.text == '**').every((s) => s.style!.color!.a < 0.5), isTrue);
      expect(parts.firstWhere((s) => s.text == 'b').style, isNull);
      c.dims = () => false;
      expect(c.buildTextSpan(context: ctx, style: const TextStyle(color: _ink), withComposing: false).children, isNull);
    });

    test('wraps the selection', () {
      final c = MarkdownController(text: 'make this bold');
      c.selection = const TextSelection(baseOffset: 5, extentOffset: 9);
      c.wrapSelection('**');
      expect(c.text, 'make **this** bold');
      expect(c.selection, const TextSelection(baseOffset: 7, extentOffset: 11));
      c.selection = const TextSelection.collapsed(offset: 0);
      c.wrapSelection('`');
      expect(c.text, '``make **this** bold');
      expect(c.selection, const TextSelection.collapsed(offset: 1));
    });
  });
}
