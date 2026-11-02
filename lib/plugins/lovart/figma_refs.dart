/// A note's Figma frames as references for Lovart (Matt, 2026-11-02: "when we have figma plugin connected would it be
/// possible to feed figma designs into the lovart inspo generator or header generator?", then "build it and deploy
/// the update"): a header image or an inspiration moodboard made with the frames the note links to, so the pictures
/// start from the design instead of from words alone.
///
/// - **Only where asked.** "Use linked Figma frames" on Lovart's page ([figmaRefsOn]), this device's and off until
///   switched on, since it sends the person's designs, which may be a client's, to Lovart, where until now only words
///   went. And the Figma plugin on with its token kept (lib/plugins/figma/frames.dart `figmaFramesOn`): the frames are
///   read with the person's own token, so a private file is as good as a shared one.
/// - **Which frames.** Every figma.com address in the note that names a file ([figmaLinksIn]), each once, in the
///   order they are written, at most [figmaRefsMost]: a frame's own render where the link has a `node-id`, the
///   file's thumbnail where it has none (lib/plugins/figma/client.dart `FigmaClient.frame`, asked fresh each time, so
///   Figma's picture address is new when Lovart fetches it).
/// - **Sent as addresses.** Lovart's chat takes reference images as `attachments`, a list of image URLs it fetches
///   and reviews itself (the official skill, skills/lovart-skill/SKILL.md: "`--attachments` takes any image URL"), so
///   the picture never passes through this device. A frame Figma will not say (no access, gone, no answer) is left
///   out quietly, and the image is made from the note's words as before.
/// - **Said in the prompt.** Lovart's agent reads the attachments as the prompt tells it to: [withFigmaRefs] adds a
///   line saying what they are and what to take from them, for a banner (the palette and the subject, drawn in the
///   house's style, which stays) or for a moodboard (four directions on the design).
/// - **What Lovart left out is said.** Lovart reviews each reference and may drop one and still finish
///   (client.dart `LovartClient.dropped`); the actions say so, and the jobs nobody asked for note it in the log.
library;

import '../figma/client.dart' show FigmaClient, FigmaFailure, FigmaLink, figmaLinkOfUrl;
import '../figma/frames.dart' show figmaFramesOn;
import '../types.dart' show PluginHost;
import 'manifest.dart';

/// The most frames sent with one image.
const int figmaRefsMost = 3;

/// Whether a note's linked Figma frames go to Lovart with its header image and its inspiration, on this device.
bool figmaRefsOn([PluginHost? via]) => (via ?? host).storage.get<Object?>(figmaRefsKey, false) == true;

/// Switches it.
void setFigmaRefs(bool on, [PluginHost? via]) => (via ?? host).storage.set(figmaRefsKey, on);

/// Whether the frames would go now: the switch, and the Figma plugin on with its token.
bool figmaRefsReady([PluginHost? via]) => figmaRefsOn(via) && figmaFramesOn();

final RegExp _figmaAddress = RegExp(r'https://(?:www\.)?figma\.com/[^\s<>()\[\]"`]+', caseSensitive: false);

/// The Figma files and frames [body] links to, each once, in the order they are written, at most [most].
List<FigmaLink> figmaLinksIn(String body, {int most = figmaRefsMost}) {
  final seen = <String>{};
  final out = <FigmaLink>[];
  for (final match in _figmaAddress.allMatches(body)) {
    // A sentence's full stop or comma after the address is not part of it.
    final address = match.group(0)!.replaceFirst(RegExp(r'[.,;:!?*_]+$'), '');
    final link = figmaLinkOfUrl(address);
    if (link == null || !seen.add(link.key)) continue;
    out.add(link);
    if (out.length >= most) break;
  }
  return out;
}

/// The pictures of [body]'s Figma frames, as addresses Lovart can fetch: none where the switch is off, the Figma
/// plugin is not connected, or the note links to no frame. A frame Figma will not say is left out.
Future<List<String>> figmaRefsFor(String body, {PluginHost? via, FigmaClient? figma}) async {
  if (!figmaRefsReady(via)) return const [];
  final links = figmaLinksIn(body);
  if (links.isEmpty) return const [];
  final client = figma ?? FigmaClient.kept();
  if (client == null) return const [];
  final out = <String>[];
  for (final link in links) {
    try {
      final picture = (await client.frame(link)).picture;
      if (picture != null && !out.contains(picture)) out.add(picture);
    } on FigmaFailure {
      // Not one Figma will say now: the image is made without it.
    }
  }
  return out;
}

/// [prompt] with a line on the [count] attached frames: for a header image ([banner]) or an inspiration moodboard.
String withFigmaRefs(String prompt, int count, {required bool banner}) {
  if (count <= 0) return prompt;
  final which = count == 1 ? 'The attached image is a design' : 'The $count attached images are designs';
  final line = banner
      ? '$which from this note’s Figma file. Take the palette, the shapes and what it shows from ${count == 1 ? 'it' : 'them'} as the reference for the banner’s subject, drawn in the style asked for above, not as a copy or a screenshot of ${count == 1 ? 'it' : 'them'}.'
      : '$which being worked on in Figma for this note. Make the images as directions that build on ${count == 1 ? 'it' : 'them'}: ${count == 1 ? 'its' : 'their'} palette, layout and mood, each taking it somewhere new, not a copy.';
  return '${prompt.trimRight()}\n\n$line';
}

/// What is said where Lovart left out a frame: its own words, or a plain line.
String figmaRefsDroppedWords(List<String> dropped) {
  final said = dropped.firstWhere((words) => words.trim().isNotEmpty, orElse: () => '').trim();
  return said.isEmpty ? 'Lovart left out a Figma frame and made the image without it.' : 'Lovart left out a Figma frame: $said';
}
