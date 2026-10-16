/// Links, pictures and media in the editor: piece H of docs/STAGE4.md, one file to a web file.
///
/// | the web app | here |
/// | --- | --- |
/// | editor/links.ts | links.dart: [shortLinks] |
/// | editor/linkCards.ts | link_cards.dart: [linkCards] |
/// | editor/linkedRows.ts | linked_rows.dart: [linkedRows] |
/// | editor/images.ts, useNotePictures.ts | images.dart: [inlineImages], [insertImage], [pasteImages], [NotePictures] |
/// | editor/placeCards.ts | place_cards.dart: [placeCards] |
/// | editor/MapCard.tsx, MapCard.module.css | map_card.dart: [MapCard], [MapPicture] |
/// | editor/videos.ts, videos.module.css | videos.dart: [videoCards] |
/// | editor/clips.ts | clips.dart: [clips], [tapeSource] |
/// | core/clips.ts | clip_refs.dart |
///
/// [mediaExtensions] is all of them as `src/app/editor/Editor.tsx` adds them, in its order, with what the page
/// reached for itself (the network, the files, the players, the switches) given as [MediaSeams].
library;

import 'package:flutter/foundation.dart';

import '../../core/images.dart';
import '../../core/link_preview.dart';
import '../../core/place_refs.dart';
import '../editor.dart';
import 'attachments.dart';
import 'clips.dart';
import 'images.dart';
import 'link_cards.dart';
import 'linked_rows.dart';
import 'links.dart';
import 'map_card.dart';
import 'picture_words.dart';
import 'place_cards.dart';
import 'videos.dart';

export 'attachments.dart';
export 'clip_refs.dart';
export 'clips.dart';
export 'images.dart';
export 'inline_box.dart';
export 'link_cards.dart';
export 'linked_rows.dart';
export 'links.dart';
export 'map_card.dart';
export 'place_cards.dart';
export 'videos.dart';

/// What the editor's links, pictures and media are told by whoever makes the editor. Everything is optional: with
/// nothing given a note still draws (short links, cards that say the site and the path, pictures waiting, quiet
/// maps, posters with their lengths, quiet memos) and reaches for nothing.
class MediaSeams {
  const MediaSeams({
    this.pictures,
    this.previewer = noLinkPreviews,
    this.openLink,
    this.onLinkTap,
    this.linkPreviews,
    this.placeSwitches,
    this.switches,
    this.linkRead,
    this.linkMenus,
    this.onOpenPlace,
    this.mapTiles,
    this.dark,
    this.films = const FilmSeams(),
    this.tape = Tape.none,
    this.clipPlayer,
  });

  /// Where pictures and posters are drawn from, and kept (lib/core/images.dart).
  final PictureStore? pictures;

  /// What knows the titles of linked pages (lib/core/link_preview.dart).
  final LinkPreviewer previewer;

  /// Opens a web address: a link card's tap.
  final LinkOpener? openLink;

  /// A tap on an address in the words of a view that cannot be edited.
  final void Function(String url)? onLinkTap;

  /// The Link previews switch (`preferences().linkPreviews`).
  final bool Function()? linkPreviews;

  /// Local only and the map switch (`preferences().localOnly`, `.mapTiles`).
  final PlaceSwitches Function()? placeSwitches;

  /// Says when a switch changed (`onPreferences`).
  final Listenable? switches;

  /// Whether a plugin reads a link, which then has its own row and no card. The plugins' own answer
  /// (linked_rows.dart `pluginReadsLink`) unless another is given.
  final LinkRead? linkRead;

  /// Linked lines' rows open their menu on a tap, and a menu action's sentence is said with this
  /// (`linkMenus` of Editor.tsx). Absent: the rows show, and open nothing.
  final LinkMenus? linkMenus;

  /// A map card's tap: opens the place on a map.
  final void Function(GeoTag tag)? onOpenPlace;

  /// What draws a map's tiles.
  final MapTilesBuilder? mapTiles;

  /// The page's side, where the caller knows better than the theme.
  final bool Function()? dark;

  /// The device and the player, for films.
  final FilmSeams films;

  /// The note's recording.
  final Tape tape;

  /// What plays a voice memo.
  final ClipPlayer? clipPlayer;
}

/// Editor.tsx's lines for this piece, in its order: pictures, places, films, short links, link cards (none in a
/// note drawn small: `peek`), the rows under linked lines, and voice memos with the note's tape.
///
/// `places` and `videos` say who is reading, as Editor.tsx's props of those names do (`off` and `still` by
/// default); `peek` is a note drawn small on a card. The tape can be changed later by putting
/// `tapeSource.of(...)` in a compartment of the caller's own instead of [MediaSeams.tape].
Extension mediaExtensions({MediaSeams seams = const MediaSeams(), PlaceMode places = PlaceMode.off, VideoMode videos = VideoMode.still, bool peek = false}) => Extension.list(<Extension>[
  inlineImages(store: seams.pictures),
  placeCards(places, dark: seams.dark, switches: seams.placeSwitches, changed: seams.switches, onOpen: seams.onOpenPlace, tiles: seams.mapTiles),
  videoCards(videos, seams: seams.films),
  // Files in the words (attachments.dart), where the app keeps files, and a picture's words (picture_words.dart):
  // neither drawn in a note drawn small, where a file's line reads as its name.
  attachmentCards(cards: !peek),
  if (!peek) pictureWords(),
  shortLinks(still: peek, onOpen: seams.onLinkTap),
  if (!peek) linkCards(previewer: seams.previewer, open: seams.openLink, enabled: seams.linkPreviews, switches: seams.switches, reads: seams.linkRead ?? pluginReadsLink),
  linkedRows(seams.linkMenus),
  clips(),
  if (seams.clipPlayer != null) clipPlayer.of(seams.clipPlayer!),
  if (seams.tape != Tape.none) tapeSource.of(seams.tape),
]);
