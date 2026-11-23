/// The connection the hub's route is made over (hub_carrier.dart), apart from what carries it: a WebSocket from a
/// phone or a computer (hub_link_io.dart), the browser's own in a web page (hub_link_web.dart), or whatever another
/// [HubDial] makes: a hub in this very app, another relay, a peer-to-peer stream. Nothing here knows which.
library;

import 'hub_link_io.dart' if (dart.library.js_interop) 'hub_link_web.dart' as platform;

/// One connection to a hub, whatever carries it.
abstract class HubLink {
  /// What the hub says: a String (its JSON) or a Uint8List (a frame). Done when the link has closed.
  Stream<Object> get said;

  /// Says a String or a `List<int>` to the hub.
  void say(Object message);

  Future<void> close();
}

/// Makes a link to the hub at [url], open and ready to be said to; throws where it can't. How long it tries is its
/// own to decide: whoever dials waits for as long as it does.
typedef HubDial = Future<HubLink> Function(String url);

/// Dials the hub at [url] as the platform this runs on does: a WebSocket, dart:io's or the browser's. Ten seconds
/// to connect, then a TimeoutException.
Future<HubLink> dialHub(String url) => platform.dialHub(url);

/// Why a [dialHub] failed, in the platform's own few words: what Settings › Routes says after "Couldn't connect"
/// (relay_choice.dart).
String dialProblem(Object error) => platform.dialProblem(error);
