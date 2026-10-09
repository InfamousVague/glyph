import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glacier/glacier.dart';

import 'support/harness.dart';

/// A panel over the page takes the page's own tokens, as the web kit's portal to `document.body` takes the body's:
/// a popover, a menu and the command palette opened from inside a scope (`.app-inverse`, a `data-hue`) are not
/// inside it. What stays where its trigger is, is the trigger.
void main() {
  /// The tokens in force where the words [text] are drawn.
  Tokens tokensAt(WidgetTester tester, String text) => GlacierTheme.of(tester.element(find.text(text)));

  /// [child] inside the app's dark-on-light scope with a hue of its own.
  Widget scoped(Widget child) => GlacierScope(classes: const {'app-inverse'}, attrs: const {'hue': 'sea'}, child: child);

  testWidgets('a popover\'s panel is the page\'s, and its trigger is where it stands', (tester) async {
    await pumpKit(
      tester,
      scoped(
        GlacierPopover(
          ariaLabel: 'Details',
          defaultOpen: true,
          trigger: (context, handle) => GlacierPressable(onPressed: handle.toggle, builder: (context, state) => const Text('trigger')),
          child: const Text('panel'),
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    final root = testTokens();
    final inside = tokensAt(tester, 'trigger'), over = tokensAt(tester, 'panel');
    expect(inside.parent, isNotNull);
    expect(identical(over, inside.rootTokens), isTrue);
    expect(over.parent, isNull);
    // Seen in a colour the scope changes: the inverse scope's ink is the page's paper.
    expect(inside.color('app-ink'), isNot(root.color('app-ink')));
    expect(over.color('app-ink'), root.color('app-ink'));
    // And in one only the scope has at all: the hue's own colour.
    expect(inside.raw('app-space'), isNotNull);
    expect(over.raw('app-space'), isNull);
  });

  testWidgets('a menu\'s panel and its items are the page\'s, a menu inside it too', (tester) async {
    await pumpKit(
      tester,
      scoped(
        GlacierMenu(
          anchor: GlacierAnchor.point(const Offset(120, 80)),
          open: true,
          children: const [
            GlacierMenuItem(child: Text('Copy')),
            GlacierMenuSub(label: Text('Move to'), children: [GlacierMenuItem(child: Text('Archive'))]),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(tokensAt(tester, 'Copy').parent, isNull);
    expect(tokensAt(tester, 'Copy').color('app-ink'), testTokens().color('app-ink'));
    // The row that opens the menu inside it stands in the panel, which is the page's: so is what it opens.
    expect(tokensAt(tester, 'Move to').parent, isNull);
  });

  testWidgets('the command palette is the page\'s', (tester) async {
    await pumpKit(
      tester,
      scoped(
        GlacierCommandPalette(
          open: true,
          onOpenChange: (_) {},
          commands: const [CommandDescriptor(id: 'new', label: 'New note')],
          onRun: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 20));
    expect(tokensAt(tester, 'New note').parent, isNull);
    expect(tokensAt(tester, 'New note').color('app-ink'), testTokens().color('app-ink'));
  });
}
