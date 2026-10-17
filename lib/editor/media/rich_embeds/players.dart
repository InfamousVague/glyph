/// What plays a rich embed: the service's own player page in a web view, made only once the person taps, never
/// before. Flutter's `webview_flutter`: Android's WebView, and WebKit's on the iPhone and the Mac. Where neither is
/// (a desktop without it, a test), [EmbedPlayers.available] is false and the card's tap opens the link instead.
///
/// The player is not loaded by its own address but from a page of one frame, given the app's site as its base
/// ([embedPageHtml]): YouTube's player refuses a page with no origin to name ("Error 153"), and the frame sends
/// `strict-origin-when-cross-origin`, the site and no more. A press inside the player that would take the page
/// elsewhere (YouTube's logo, Spotify's "Open app") is handed to the phone instead, and the player stays.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../core/link_preview.dart' show LinkOpener;

/// What a player is asked to show.
@immutable
class EmbedPage {
  const EmbedPage({required this.player, required this.title, this.ground = const Color(0xFF000000)});

  /// The service's player: providers.dart's `RichLink.player`.
  final Uri player;

  /// What a screen reader hears it called.
  final String title;

  /// The colour behind the player while it loads.
  final Color ground;
}

/// One player, open: its view, as long as it is wanted, and let go when the card or the layer is gone.
abstract class EmbedPlayback {
  /// The player drawn. [whole] is full screen, where every gesture is the player's; in a card only a tap and a
  /// sideways drag are, so the note still scrolls over it.
  Widget view({required bool whole});

  /// The web view let go: the sound stops with it.
  void dispose();
}

/// What makes players.
abstract class EmbedPlayers {
  const EmbedPlayers();

  /// Whether a player can be made here at all.
  bool get available;

  /// A player for [page], loading at once. [open] is how a press inside it that leaves the player is handed on.
  EmbedPlayback open(EmbedPage page, {LinkOpener? open});
}

/// The app's site, as the player page's base: what YouTube is told the player is embedded in.
const String embedBase = 'https://ghostmarkdown.com/';

String _attr(String text) => text.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');

String _hex(Color color) {
  String two(double part) => (part * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(color.r)}${two(color.g)}${two(color.b)}';
}

/// The page a player is loaded in: one frame, the whole of it, the player's own address in it.
String embedPageHtml(EmbedPage page) =>
    '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
    '<style>html,body{margin:0;padding:0;height:100%;overflow:hidden;background:${_hex(page.ground)}}'
    'iframe{display:block;border:0;width:100%;height:100%}</style></head><body>'
    '<iframe src="${_attr(page.player.toString())}" title="${_attr(page.title)}" '
    'allow="autoplay; encrypted-media; picture-in-picture; fullscreen; clipboard-write" allowfullscreen '
    'referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>';

/// The web views: on Android, the iPhone and the Mac, where `webview_flutter` has registered its platform.
class WebViewEmbedPlayers extends EmbedPlayers {
  const WebViewEmbedPlayers();

  @override
  bool get available => !kIsWeb && WebViewPlatform.instance != null;

  @override
  EmbedPlayback open(EmbedPage page, {LinkOpener? open}) => _WebPlayback(page, open);
}

/// The app's players.
const EmbedPlayers webViewEmbedPlayers = WebViewEmbedPlayers();

class _WebPlayback implements EmbedPlayback {
  _WebPlayback(EmbedPage page, this._open) : _controller = WebViewController.fromPlatformCreationParams(_params()) {
    final controller = _controller;
    unawaited(controller.setJavaScriptMode(JavaScriptMode.unrestricted));
    if (defaultTargetPlatform != TargetPlatform.macOS) unawaited(controller.setBackgroundColor(page.ground).catchError((Object _) {}));
    unawaited(controller.setNavigationDelegate(NavigationDelegate(onNavigationRequest: _onNavigation)));
    final platform = controller.platform;
    // The tap that made the player was the asking: it may start without another.
    if (platform is AndroidWebViewController) unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
    unawaited(controller.loadHtmlString(embedPageHtml(page), baseUrl: embedBase));
  }

  static PlatformWebViewControllerCreationParams _params() {
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      // Played in the card, not taken to the phone's own player, and started by the tap that made it.
      return WebKitWebViewControllerCreationParams(allowsInlineMediaPlayback: true, mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{});
    }
    return const PlatformWebViewControllerCreationParams();
  }

  final WebViewController _controller;
  final LinkOpener? _open;
  bool _gone = false;

  /// The page itself and everything inside its frame stay; anything that would take the whole page elsewhere goes
  /// to the phone.
  NavigationDecision _onNavigation(NavigationRequest request) {
    final url = request.url;
    if (!request.isMainFrame || url.startsWith(embedBase) || url == 'about:blank' || url.startsWith('data:')) return NavigationDecision.navigate;
    final open = _open;
    if (open != null && (url.startsWith('https://') || url.startsWith('http://'))) unawaited(open(url).catchError((Object _) {}));
    return NavigationDecision.prevent;
  }

  static final Set<Factory<OneSequenceGestureRecognizer>> _inCard = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(TapGestureRecognizer.new),
    Factory<OneSequenceGestureRecognizer>(HorizontalDragGestureRecognizer.new),
  };
  static final Set<Factory<OneSequenceGestureRecognizer>> _all = <Factory<OneSequenceGestureRecognizer>>{Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)};

  @override
  Widget view({required bool whole}) => WebViewWidget(controller: _controller, gestureRecognizers: whole ? _all : _inCard);

  @override
  void dispose() {
    if (_gone) return;
    _gone = true;
    // A blank page in its place stops the sound at once, before the platform view is torn down.
    unawaited(_controller.loadHtmlString('<!doctype html><html></html>', baseUrl: embedBase).catchError((Object _) {}));
  }
}
