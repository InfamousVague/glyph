/// The page as an iPhone gives it to the real app, where Flutter would give it otherwise: nothing here is on any
/// other platform ([IPhonePage] hands its child straight back).
///
/// The real iPhone app is the web page in a WKWebView, and three things about that page are WebKit's doing rather
/// than a rule written in ../glyph. Flutter does each differently by default, so each is said here:
///
/// - **The phone's text size is left alone.** The page sets its type in px and rem under
///   `-webkit-text-size-adjust: 100%` (app.css), and WebKit does not scale that with Dynamic Type or embolden it
///   for Bold Text; the app's own size is Settings › Appearance's (`uiScale`). Flutter scales every `Text` by the
///   phone's setting unless told not to, which would put a note's lines where the page's are not.
/// - **The keyboard has a bar with Done on it.** An iPhone's keyboard has no key that puts it away; over a web
///   page WebKit lays its own accessory bar on the keyboard, and its Done is how a person lowers the keyboard in a
///   note. Flutter's text input has no such bar, so [IPhoneKeyboardBar] is drawn in its place, in the page's own
///   paper with a hairline over it, as the find bar that rests on the keyboard is (editor/FindBar.module.css).
///   WebKit's bar also carries two arrows that step between a form's fields; a note is one field, where they are
///   grey, and they are not drawn.
/// - **The page is laid out above the keyboard, and above that bar.** This is the page's own rule ("the bottom of
///   the screen is the top of the keyboard", FindBar.module.css), which its Android half keeps natively
///   (`fitAboveKeyboard`). Every screen here already reads the keyboard's height from `MediaQuery.viewInsets`, so
///   the bar's height is added to it and each of them clears the bar with no change of its own. What the real
///   iPhone app's WebView does instead (it leaves the layout as it was and pans the page so the caret shows) is
///   WebKit's and is not copied: README, "What the iPhone app left open".
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

/// The bar's height: an iPhone's own 44pt row, which is also the least a finger is given.
const double iPhoneKeyboardBarHeight = 44;

/// What [IPhonePage] makes of the phone's [media]: the text size and weight left alone, and the keyboard's inset
/// grown by the bar while the keyboard is up.
MediaQueryData iPhoneMedia(MediaQueryData media) {
  final keyboard = media.viewInsets.bottom;
  return media.copyWith(
    textScaler: TextScaler.noScaling,
    boldText: false,
    viewInsets: keyboard > 0 ? media.viewInsets.copyWith(bottom: keyboard + iPhoneKeyboardBarHeight) : media.viewInsets,
  );
}

class IPhonePage extends StatelessWidget {
  const IPhonePage({super.key, required this.child, this.iPhone});

  final Widget child;

  /// Whether this is an iPhone; the platform's answer where it is not said (a test says).
  final bool? iPhone;

  @override
  Widget build(BuildContext context) {
    if (!(iPhone ?? defaultTargetPlatform == TargetPlatform.iOS)) return child;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    return MediaQuery(
      data: iPhoneMedia(media),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          // Over everything, the app's sheets and menus too, as the keyboard itself is.
          if (keyboard > 0) Positioned(left: 0, right: 0, bottom: keyboard, height: iPhoneKeyboardBarHeight, child: const IPhoneKeyboardBar()),
        ],
      ),
    );
  }
}

/// The row on the keyboard: Done at its end, which gives up the keyboard's focus so the keyboard goes.
class IPhoneKeyboardBar extends StatelessWidget {
  const IPhoneKeyboardBar({super.key, this.onDone});

  /// What Done does; putting the keyboard away where it is not said.
  final VoidCallback? onDone;

  static const Key doneKey = ValueKey<String>('iphone-keyboard-done');

  /// Blurs whatever is being typed in, as WebKit's Done does, and tells the phone the keyboard is not wanted.
  static void lowerKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ratio = MediaQuery.devicePixelRatioOf(context);
    // A hairline is a device pixel, as the find bar's is.
    final hairline = (t.len('glacier-hairline') * ratio).roundToDouble().clamp(1.0, double.infinity) / ratio;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.color('glacier-bg'),
        border: Border(top: BorderSide(color: t.color('app-rule'), width: hairline)),
      ),
      child: Align(
        alignment: AlignmentDirectional.centerEnd,
        child: GlacierPressable(
          key: doneKey,
          onPressed: onDone ?? lowerKeyboard,
          semanticLabel: 'Done',
          // The press must not take the focus it is about to give up: the keyboard would go and come back.
          canRequestFocus: false,
          builder: (context, state) => Padding(
            padding: EdgeInsetsDirectional.only(start: t.space(4), end: t.len('app-gutter-end')),
            child: SizedBox(
              height: iPhoneKeyboardBarHeight,
              child: Center(
                widthFactor: 1,
                child: Text('Done', style: t.textAt(t.fontSize('md'), weight: 'semibold', color: state.pressed ? t.color('glacier-text-muted') : t.color('glacier-text'))),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
