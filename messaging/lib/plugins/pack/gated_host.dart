/// What a pack's button may ask of the app: the screen's own host, with every verb held to what the pack declared and
/// to the conversation the button was offered on. A refused call does nothing, and is told to the pack's registry and
/// to whoever keeps its errors, so a developer sees what their pack tried.
library;

import 'package:flutter/widgets.dart';

import '../plugin.dart';
import 'pack_plugin.dart';

class GatedHost implements PluginHost {
  GatedHost(this.inner, {required this.plugin, required this.thread, Future<bool> Function(String url)? openLink});
  final PluginHost inner;
  final PackPlugin plugin;
  final int thread;                                   // the conversation the action was offered on

  @override
  PluginPrefs get prefs => inner.prefs;
  @override
  void say(String words) => throw UnimplementedError(_later);                  // cut to 80; at most once every 1.5 s per pack, else dropped
  @override
  void copy(String text, {String? say}) => throw UnimplementedError(_later);   // needs copy; cut to 200; at most 10 a minute per pack
  @override
  void open(int thread) => throw UnimplementedError(_later);                   // refused
  @override
  Future<void> markRead(int thread) => throw UnimplementedError(_later);       // needs markread; only this.thread
  @override
  void move(int thread, String? section) => throw UnimplementedError(_later);  // needs move; only this.thread; section null or one of the pack's own tab section ids
  @override
  void write(String text) => throw UnimplementedError(_later);                 // needs write; cut to 300
  @override
  void present(WidgetBuilder page) => throw UnimplementedError(_later);        // refused
  @override
  Future<void> deleteThread(int thread) => throw UnimplementedError(_later);   // refused
  @override
  Future<void> reload() => inner.reload();

  /// Needs links; only the pack's one link; Sms.instance.openLink unless given.
  Future<void> openLink(String url) => throw UnimplementedError(_later);
}

const String _later = 'A pack\'s host comes with the Marketplace\'s runtime (lib/plugins/pack/gated_host.dart).';
