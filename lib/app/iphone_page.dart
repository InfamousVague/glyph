/// The page as an iPhone gives it to the real app, where Flutter would give it otherwise: nothing here is on any
/// other platform ([IPhonePage] hands its child straight back).
///
/// The real iPhone app is the web page in a WKWebView, and three things about that page are WebKit's doing rather
/// than a rule written in tauri/. Flutter does each differently by default, so each is said here:
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
///   grey, and they are not drawn. In simple mode a note's Format bar shares the row (lib/note/format_bar.dart):
///   the note offers its tools through a [KeyboardBarOffer] and the bar draws them at its start, Done at its end
///   still.
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

class IPhonePage extends StatefulWidget {
  const IPhonePage({super.key, required this.child, this.iPhone});

  final Widget child;

  /// Whether this is an iPhone; the platform's answer where it is not said (a test says).
  final bool? iPhone;

  @override
  State<IPhonePage> createState() => _IPhonePageState();
}

class _IPhonePageState extends State<IPhonePage> {
  final KeyboardBarOffers _offers = KeyboardBarOffers();

  @override
  void dispose() {
    _offers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    if (!(widget.iPhone ?? defaultTargetPlatform == TargetPlatform.iOS)) return child;
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    return KeyboardBarScope(
      offers: _offers,
      child: MediaQuery(
        data: iPhoneMedia(media),
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            // Over everything, the app's sheets and menus too, as the keyboard itself is.
            if (keyboard > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboard,
                height: iPhoneKeyboardBarHeight,
                child: ListenableBuilder(listenable: _offers, builder: (context, _) => IPhoneKeyboardBar(tools: _offers.tools)),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a screen offers the keyboard's bar while it is up: the tools at its start, before Done. One stands over
/// the app ([IPhonePage]); a screen puts its tools in it with a [KeyboardBarOffer] and takes them out as it goes.
class KeyboardBarOffers extends ChangeNotifier {
  Widget? _tools;
  Object? _by;
  bool _disposed = false;

  Widget? get tools => _tools;

  /// [by] offers [tools]; null takes them away. Only the one that offered them takes them away, so a screen going
  /// does not clear what the next one just put there.
  void offer(Object by, Widget? tools) {
    if (_disposed) return;
    if (tools == null) {
      if (_tools == null || !identical(_by, by)) return;
      _tools = null;
      _by = null;
    } else {
      if (identical(_tools, tools) && identical(_by, by)) return;
      _tools = tools;
      _by = by;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Where the keyboard's bar takes offers: over the app on an iPhone, nowhere else.
class KeyboardBarScope extends InheritedWidget {
  const KeyboardBarScope({super.key, required this.offers, required super.child});

  final KeyboardBarOffers offers;

  /// The bar's offers, or null where there is no bar to offer to (every other platform).
  static KeyboardBarOffers? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<KeyboardBarScope>()?.offers;

  @override
  bool updateShouldNotify(KeyboardBarScope oldWidget) => !identical(oldWidget.offers, offers);
}

/// A screen's tools for the keyboard's bar, offered for as long as this stands in the tree with [tools] to give:
/// null offers nothing, and takes back what this offered. Draws nothing itself.
class KeyboardBarOffer extends StatefulWidget {
  const KeyboardBarOffer({super.key, required this.tools});

  final Widget? tools;

  @override
  State<KeyboardBarOffer> createState() => _KeyboardBarOfferState();
}

class _KeyboardBarOfferState extends State<KeyboardBarOffer> {
  KeyboardBarOffers? _offers;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final offers = KeyboardBarScope.maybeOf(context);
    if (!identical(offers, _offers)) {
      _offers?.offer(this, null);
      _offers = offers;
    }
    _tell();
  }

  @override
  void didUpdateWidget(KeyboardBarOffer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tools, widget.tools)) _tell();
  }

  /// After the frame: the bar is drawn over the page, and told of the page's tools while the page builds.
  void _tell() {
    final offers = _offers;
    if (offers == null) return;
    final tools = widget.tools;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(widget.tools, tools)) offers.offer(this, tools);
    });
  }

  @override
  void dispose() {
    // After the frame, as the offer was made: the bar stands over the page, and a screen may go as the page builds.
    final offers = _offers;
    if (offers != null) WidgetsBinding.instance.addPostFrameCallback((_) => offers.offer(this, null));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The row on the keyboard: Done at its end, which gives up the keyboard's focus so the keyboard goes; and the
/// screen's [tools] at its start, where it offers any.
class IPhoneKeyboardBar extends StatelessWidget {
  const IPhoneKeyboardBar({super.key, this.onDone, this.tools});

  /// What Done does; putting the keyboard away where it is not said.
  final VoidCallback? onDone;

  /// What stands at the bar's start: a note's Format bar in simple mode.
  final Widget? tools;

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
    final tools = this.tools;
    final done = GlacierPressable(
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
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.color('glacier-bg'),
        border: Border(top: BorderSide(color: t.color('app-rule'), width: hairline)),
      ),
      child: tools == null
          ? Align(alignment: AlignmentDirectional.centerEnd, child: done)
          // The tools take what Done leaves, and scroll sideways on a phone too narrow for all of them.
          : Row(children: [Expanded(child: tools), done]),
    );
  }
}
