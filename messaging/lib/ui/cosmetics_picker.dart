import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../friends/buddies.dart';
import '../kit/settings_kit.dart';
import '../kit/settings_type.dart';
import '../me/cosmetics.dart';
import '../me/me.dart';
import '../voice/channels.dart';
import 'common.dart';
import 'cosmetics_ui.dart';
import 'profile_card.dart' show ProfileFace;

/// Profile › Look (GMFB-34): what your profile wears, each kind a row opening its pieces, with how you look now at the
/// top: your face dressed, your name in its effect, over your banner.
class CosmeticsSection extends StatelessWidget {
  const CosmeticsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final me = Me.instance;
    return ListenableBuilder(
      listenable: me,
      builder: (context, _) {
        final c = me.cosmetics;
        return PaneSection(
          title: 'Look',
          description: const Text('Dress your profile. Friends and people in your spaces see it on your profile card.'),
          children: [
            SettingRowBox(child: _Preview(cosmetics: c, name: me.shownName, picture: me.pictureOwn)),
            for (final kind in CosmeticKind.values)
              SettingRow(
                key: ValueKey('look-${kind.name}'),
                icon: AppIcon(_iconOf(kind), size: 18),
                label: kind.label,
                value: Text(CosmeticCatalog.find(kind, c.of(kind))?.label ?? 'None'),
                onPress: () => push(context, (_) => CosmeticPickerScreen(kind: kind)),
              ),
            if (!c.isEmpty)
              SettingRow(
                icon: AppIcon(Lucide.x, size: 18),
                label: 'Take everything off',
                onPress: () => wear(Cosmetics.none),
              ),
          ],
        );
      },
    );
  }
}

LucideIcon _iconOf(CosmeticKind kind) => switch (kind) {
      CosmeticKind.decoration => Lucide.sparkles,
      CosmeticKind.border => Lucide.circleUser,
      CosmeticKind.banner => Lucide.image,
      CosmeticKind.name => Lucide.type,
      CosmeticKind.effect => Lucide.flame,
    };

/// Puts [c] on: kept, told to friends and said again in every space.
void wear(Cosmetics c) {
  Me.instance.setCosmetics(c);
  Buddies.instance.shareProfile();
  Voice.instance.sayMeEverywhere();
}

/// How the profile looks with [cosmetics]: the banner, the dressed face over its edge, the name in its effect, and the
/// profile effect over all of it, as the card draws them.
class _Preview extends StatelessWidget {
  const _Preview({required this.cosmetics, required this.name, required this.picture});
  final Cosmetics cosmetics;
  final String name;
  final String picture;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final face = t.lenOf('4rem');
    final bannerH = t.lenOf('4.5rem');
    final hues = [t.color('app-paper-3'), t.color('app-paper-2')];
    return ClipRRect(
      key: const ValueKey('look-preview'),
      borderRadius: BorderRadius.circular(t.radius('lg')),
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            height: bannerH + face / 2,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: bannerH,
                child: CosmeticBanner(id: cosmetics.banner, fallback: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: hues)))),
              ),
              Positioned(
                left: t.space(4),
                top: bannerH - face / 2,
                child: DressedFace(size: face, cosmetics: cosmetics, face: ProfileFace(name: name, picture: picture, size: face)),
              ),
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(2), t.space(4), t.space(3)),
            child: NameEffectText(name.isEmpty ? 'You' : name, id: cosmetics.name, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink'))),
          ),
        ]),
        if (cosmetics.effect.isNotEmpty) Positioned.fill(child: ProfileEffectLayer(id: cosmetics.effect)),
      ]),
    );
  }
}

/// The pieces of one kind, as tiles: None first, then each piece drawn as it would be worn. The one worn is ringed.
class CosmeticPickerScreen extends StatelessWidget {
  const CosmeticPickerScreen({super.key, required this.kind});
  final CosmeticKind kind;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final me = Me.instance;
    return GhostPage(
      title: kind.label,
      body: ListenableBuilder(
        listenable: me,
        builder: (context, _) {
          final worn = me.cosmetics.of(kind);
          final pieces = CosmeticCatalog.of(kind);
          final wide = kind == CosmeticKind.banner || kind == CosmeticKind.name;
          return GridView.builder(
            padding: EdgeInsets.fromLTRB(t.space(4), t.space(3), t.space(4), t.space(8) + MediaQuery.paddingOf(context).bottom),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: wide ? t.lenOf('14rem') : t.lenOf('8rem'),
              mainAxisSpacing: t.space(3),
              crossAxisSpacing: t.space(3),
              childAspectRatio: wide ? 2.4 : 0.85,
            ),
            itemCount: pieces.length + 1,
            itemBuilder: (context, i) {
              final piece = i == 0 ? null : pieces[i - 1];
              final id = piece?.id ?? '';
              return _Tile(
                key: ValueKey('piece-${id.isEmpty ? 'none' : id}'),
                kind: kind,
                piece: piece,
                worn: worn == id,
                onPick: () => wear(me.cosmetics.withKind(kind, id)),
              );
            },
          );
        },
      ),
    );
  }
}

/// One tile: the piece as it would look worn alone on your own face, name or card (None: a ban sign), its name under.
class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.kind, required this.piece, required this.worn, required this.onPick});
  final CosmeticKind kind;
  final Cosmetic? piece;
  final bool worn;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final me = Me.instance;
    final p = piece;
    final face = t.lenOf('3rem');
    Widget show;
    if (p == null) {
      show = Center(child: AppIcon(Lucide.ban, size: 22, color: t.color('app-ink-3')));
    } else {
      final just = Cosmetics.none.withKind(kind, p.id);
      show = switch (kind) {
        CosmeticKind.decoration || CosmeticKind.border => Center(child: DressedFace(size: face, cosmetics: just, face: ProfileFace(name: me.shownName, picture: me.pictureSharp, size: face))),
        CosmeticKind.banner => ClipRRect(borderRadius: BorderRadius.circular(t.radius('md')), child: CosmeticBanner(id: p.id, fallback: const SizedBox.shrink())),
        CosmeticKind.name => Center(child: NameEffectText(me.shownName.isEmpty ? p.label : me.shownName, id: p.id, style: pageText(t, t.fontSize('lg'), weight: 'bold', color: t.color('app-ink')))),
        CosmeticKind.effect => ClipRRect(
            borderRadius: BorderRadius.circular(t.radius('md')),
            child: Stack(children: [Positioned.fill(child: ColoredBox(color: t.color('app-paper-3'))), Positioned.fill(child: ProfileEffectLayer(id: p.id))]),
          ),
      };
    }
    return GlacierPressable(
      onPressed: onPick,
      semanticLabel: '${p?.label ?? 'None'}${worn ? ', worn' : ''}',
      builder: (context, state) => Container(
        padding: EdgeInsets.all(t.space(2)),
        decoration: BoxDecoration(
          color: t.color(state.pressed ? 'app-paper-3' : 'app-paper-2'),
          borderRadius: BorderRadius.circular(t.radius('lg')),
          border: Border.all(color: worn ? t.color('app-ink') : t.color('app-rule'), width: worn ? 2 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: show),
          SizedBox(height: t.space(1)),
          Text(p?.label ?? 'None', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: worn ? 'bold' : 'medium', color: t.color('app-ink-2'))),
        ]),
      ),
    );
  }
}
