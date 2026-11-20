/// A pack as a plugin: its rules compiled once into the classifier, sections, buttons, incoming rule and settings the
/// app already asks its own plugins for (plugin.dart), so the registry, the list and the screens take a pack as they
/// take a built-in. What it may see and do is bounded by format.dart's packSees and packMayAct and by its host
/// (gated_host.dart), never by what it says of itself; and a pack that slows the app down is paused.
library;

import 'dart:typed_data';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../plugin.dart';
import '../registry.dart';
import 'format.dart';
import 'manifest.dart';
import 'review.dart';

class PackPlugin extends GhostPlugin {
  PackPlugin(this.pack, {required this.source, this.approval, void Function(PackPlugin plugin, Object error)? onError, this.onTrouble, Future<bool> Function(String url)? openLink, DateTime Function()? now, bool paused = false})
      : onError = onError ?? _toTheApp {
    throw UnimplementedError('A pack\'s plugin comes with the Marketplace\'s runtime (lib/plugins/pack/pack_plugin.dart).');
  }

  static void _toTheApp(PackPlugin plugin, Object error) => PluginRegistry.instance.failed(plugin, error);

  final PluginPack pack;
  @override
  final PluginSource source;                                   // reviewed or dev, never builtIn
  final PackApproval? approval;                                // non-null for a reviewed pack

  /// Where what it throws, and what its host refuses, is told: the registry it is in. InstalledPlugins and tryPack pass
  /// `(p, e) => registry.failed(p, e)`; PluginRegistry.instance.failed where none is given.
  final void Function(PackPlugin plugin, Object error) onError;

  /// What happened to it that its owner keeps: 'paused' once, `'refused <verb>'` each time. Called synchronously from
  /// whatever is asking it, often a build, so its listener only records (B.9.2).
  final void Function(PackPlugin plugin, String what)? onTrouble;

  /// It was slowing the app down: it gives nothing until [unpause].
  bool get paused => throw UnimplementedError();
  void unpause() => throw UnimplementedError();

  @override
  String get id => pack.registryId;
  @override
  String get name => pack.name;
  @override
  String get description => pack.description;
  @override
  LucideIcon get icon => Lucide.all[pack.symbol] ?? Lucide.puzzle;

  /// Nothing from outside is on until it is added.
  @override
  bool get onByDefault => false;
  @override
  List<TunedClassifier> get tuned => throw UnimplementedError();                   // one classifier: A.8.2
  @override
  List<ListSection> get sections => throw UnimplementedError();                    // A.8.3, A.8.4
  @override
  List<SlotFill> get slots => throw UnimplementedError();                          // A.8.5: Slots.conversationMenu, conversationHeader, messageMenu
  @override
  List<IncomingRule> get incoming => throw UnimplementedError();                   // A.8.6: one rule
  @override
  List<PluginSetting> get settings => throw UnimplementedError();                  // A.7
  @override
  String get hue => pack.hue;
  @override
  PluginShelf get shelf => PluginShelf.values.byName(pack.shelf);
  @override
  String get tagline => pack.tagline;
  @override
  List<String> get adds => packAdds(pack);
  @override
  List<PluginReach> get reaches => packReaches(pack);
  @override
  Set<PluginScope> get scopes => const {PluginScope.device};
  @override
  String? get developer => pack.developer;
  @override
  String? get version => pack.version;
  @override
  Uint8List? get iconPng => pack.icon;
  @override
  List<String> get labels => pack.labels;
}
