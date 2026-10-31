/// A note's header banner: a picture across the top of the page, named by one flat key in its front matter (Matt,
/// 2026-10-26: "header images for notes … banners at the top"). Lovart makes them (lib/plugins/lovart/banners.dart);
/// any picture the device keeps could be one.
///
///     ---
///     banner: "![](image/lovart-img-….png)"
///     ---
///
/// The value is a picture's own Markdown, quoted, so everything that already follows a note's pictures follows the
/// banner with no change of its own: sync and the team's sync send it with the note ([imageNames] reads the whole
/// body), export carries it, and the note keeps it from the trash's sweep. Obsidian's Banners plugin reads a
/// `banner:` key the same way, a link to the picture.
library;

import 'front_matter.dart' show frontMatterValue;
import 'images.dart' show imageRef;
import 'item_syntax.dart' show jsTrim;
import 'properties.dart' show withFrontMatterValue;

/// The key.
const String bannerKey = 'banner';

/// The shape a banner is asked to be made at, and drawn at until its picture is read: 16:9, a shape Lovart makes
/// (it was 4:1, which Lovart never made: its pictures came square, and a quarter of each showed). A banner read is
/// drawn at the shape of its drawing (lib/note/note_banner.dart `BannerLook`).
const double bannerAspect = 16 / 9;

/// The picture's name a note's banner names, or null where it names none.
String? bannerOf(String body) {
  final value = frontMatterValue(body, bannerKey);
  if (value == null || !value.contains('](image/')) return null;
  final name = imageRef.firstMatch(value)?.group(2) ?? '';
  return name.isEmpty ? null : name;
}

/// The value written for the picture [name].
String bannerValue(String name) => '"![](image/$name)"';

/// The value that says the note is to have no banner, `banner: none`: one taken off on purpose stays off
/// (docs/MARKDOWN_FIRST.md §5, gap 13; Matt, 2026-10-31). Lovart's "once per note" was a list on the device, so a
/// library restored from its files alone gave a note its banner again; the note's own word survives. An older build
/// reads it as no banner ([bannerOf] is null for it).
const String bannerNone = 'none';

/// Whether the note says it is to have no banner.
bool bannerDeclined(String body) => jsTrim(frontMatterValue(body, bannerKey) ?? '').toLowerCase() == bannerNone;

/// The body saying it is to have no banner, whatever it had.
String withoutBanner(String body) => withFrontMatterValue(body, bannerKey, bannerNone);

/// The body with its banner the picture [name], or none for null; front matter made where there was none, and taken
/// away again where the banner was all it held.
String withBanner(String body, String? name) => withFrontMatterValue(body, bannerKey, name == null ? null : bannerValue(name));
