import 'package:flutter/services.dart';

/// The app's stickers (Matt, 2026-11-13: "generate 4 sticker packs using our ghost mascot we've developed"): the
/// ghost in the poses drawn for the message effects, made into stickers by tool/sticker_packs.py and kept in
/// `assets/stickers/<pack>/`. A sticker is sent as a picture message. Mischief is a pack drawn for itself (the
/// dark-cute one: horns, a heart-tipped tail), cut from its own sheet by the same tool.
class StickerPack {
  const StickerPack(this.id, this.name, this.stickers);
  final String id;
  final String name;

  /// The stickers' assets, in the order the pack keeps them.
  final List<String> stickers;
}

/// The packs' names, in the order they are offered. A pack with no pictures is not offered.
const _names = {'ghost': 'Ghost', 'love': 'Love', 'party': 'Party', 'sweet': 'Sweet', 'mischief': 'Mischief'};

Future<List<StickerPack>>? _packs;

/// Every pack the app carries, read from what is bundled.
Future<List<StickerPack>> stickerPacks() => _packs ??= _read();

Future<List<StickerPack>> _read() async {
  try {
    final assets = (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets();
    return [
      for (final e in _names.entries)
        StickerPack(e.key, e.value, assets.where((a) => a.startsWith('assets/stickers/${e.key}/') && a.endsWith('.webp')).toList()..sort()),
    ].where((p) => p.stickers.isNotEmpty).toList();
  } catch (_) {
    return const [];
  }
}

/// A sticker's name as it travels: its pack and its number (`love-03`), from its asset.
String stickerName(String asset) {
  final parts = asset.split('/');
  return '${parts[parts.length - 2]}-${parts.last.replaceAll('.webp', '')}';
}
