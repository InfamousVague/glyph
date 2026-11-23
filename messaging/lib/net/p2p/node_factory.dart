import 'node.dart';
import 'node_ffi.dart';

/// This device's node on the direct network, not yet started; null where this build has no core (a browser, a
/// platform the library was not built for, a build that left it out), and then there is no direct route at all.
///
/// The one place a node is made. What it is made of (lib/net/p2p/node_ffi.dart: the Rust core through `dart:ffi`
/// wherever there is one) is nobody else's to know; a test hands the route a stand-in instead.
P2pNode? makeP2pNode() => IrohNode.make();
