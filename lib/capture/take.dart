/// One recording's words, and the card a command read at Done puts up, as state with no screen and no clock of its
/// own. A port of `src/app/capture/take.ts`.
///
/// The recorder keeps the take's words here: each phrase the live reader (live_route.dart) says is words arrives by
/// `listen`, which only shows it, and the stretches that were commands are marked for the better words to leave out
/// (`commandSpans`, `keywordSpans`). A command the live reader did not carry out is read once, from the whole
/// transcript, at Done (final_instruction.dart): words for a note by name, or a new list by name. It is offered here
/// with `offerFinal`, and with the microphone stopped its card waits for a tap - Add or Create (`confirm`), or Cancel
/// (`cancel`). "New note" carries the take on in a fresh note (`fork`).
///
/// What differs: the call. `markdown` and [takeMarkdown] take `titled` and `partial` as named parameters, so
/// `TakeMarkdownOptions` has no type of its own; [takeMarkdown] takes the segments themselves, where the web takes
/// anything with a `segments`, and answers a record. The take is generic in any note (see take_types.dart).
library;

import 'command.dart' show FinalPlan;
import 'markdown.dart' show RenderOptions, Segment, renderNote;
import 'offers.dart' show Offer, OfferPlace, OfferPlan, offerFor;
import 'take_host.dart' show Haptic, RouteViewDone, RouteViewMoved, TakeHost;
import 'take_types.dart' show Span, TakeCandidate;

// The confirm card reads offers from here, where the recorder's take makes them.
export 'offers.dart' show Offer, OfferNew, OfferPlace, OfferPlan;

final RegExp _leadingMarks = RegExp(r'^[\s.,;:!?…]+');

/// One recording's words: see the library's comment.
class Take<N extends Object> {
  Take(this._host);

  final TakeHost<N> _host;

  /// The words of the note, as committed phrases (commands taken out).
  List<Segment> segments = [];

  /// Recording spans that were commands, for the better-words pass to leave out.
  List<Span> commandSpans = [];

  /// Phrases that were words and then "Glyph": the better words keep only what came before it.
  List<Span> keywordSpans = [];

  /// Notes other than this one that commands changed.
  Set<String> touched = {};

  Offer<N>? _pending;

  // ---- the card after Done ---------------------------------------------------------------------------------------

  void _setPending(Offer<N>? offer) {
    _pending = offer;
    _host.offer(offer);
  }

  /// Offer a plan only after the complete capture has been classified.
  void offerFinal(FinalPlan<TakeCandidate<N>> plan) {
    segments = [];
    _host.changed();
    final made = offerFor<N>(plan);
    if (made == null) return;
    _setPending(made);
    _host.route(null);
    _host.haptic(Haptic.selection);
  }

  /// Offer a finished recording's changes: shown, and on a tap left to the recorder to carry out
  /// (`offerChanges`; capture_screen.dart `_confirmPending`).
  void offerChanges({required String heading, required String action, required List<String> lines, String? detail}) {
    segments = [];
    _host.changed();
    _setPending(OfferPlan<N>(heading: heading, action: action, lines: lines, detail: detail));
    _host.route(null);
    _host.haptic(Haptic.selection);
  }

  /// Add or Create, tapped: the command does what it showed. A new list is made by the recorder once this is done.
  /// No review follows the card, so nothing is logged for one.
  void confirm() {
    final held = _pending;
    if (held == null) return;
    _setPending(null);
    if (held is OfferPlace<N>) {
      _host.addItems(held.note, held.text, held.placement);
    } else if (held is OfferPlan<N>) {
      // The recorder writes these itself, so the card's words stay up as the outcome and the phone says it worked.
      _host.route(RouteViewDone(text: held.heading));
      _host.haptic(Haptic.success);
    } else {
      _host.route(RouteViewMoved(title: held.title));
    }
  }

  /// Cancel, tapped: nothing happens.
  void cancel() {
    if (_pending == null) return;
    _setPending(null);
  }

  // ---- carrying on in another note -------------------------------------------------------------------------------

  /// The take carries on in another note: what it has is that note's, and stays there. The stretches of the tape it
  /// came from are marked as commands, so the better words never write them into the next note.
  void fork() {
    for (final segment in segments) {
      commandSpans.add(Span(startMs: segment.startMs, endMs: segment.endMs));
    }
    segments = [];
    _host.changed();
  }

  // ---- a phrase --------------------------------------------------------------------------------------------------

  /// Listen only. The recorder uses this for every live Whisper commit: it renders the accumulating transcript but
  /// cannot route, infer, write, or derive a note from an incomplete utterance.
  void listen(Segment segment) {
    final text = segment.text.replaceFirst(_leadingMarks, '');
    if (text.isEmpty) return;
    segments = [...segments, Segment(startMs: segment.startMs, endMs: segment.endMs, text: text)];
    _host.changed();
  }

  /// Whether there is anything to save: words that lay out as something. Read from the laid-out note, as the
  /// recorder's Done reads it, so a cue said alone - held for a sentence that never comes - is nothing to save.
  bool get hasContent => renderNote(segments).markdown.trim() != '';

  /// The take's markdown: its words as the cues lay them out. [titled] is whether the words may take a `# title`:
  /// not when they go on the end of a note that has one. [partial] is the phrase still being guessed, set after the
  /// words and marked as pending.
  String markdown({required bool titled, String partial = ''}) => takeMarkdown(segments, titled: titled, partial: partial).markdown;
}

/// A take's markdown, from what it holds: its words as the cues lay them out, and the phrase still being guessed
/// after them. What the page shows as it is spoken and what is saved at Done are this, so they cannot disagree.
/// `pendingFrom` is where the guessed phrase starts, for drawing it lighter.
({String markdown, int? pendingFrom}) takeMarkdown(List<Segment> segments, {required bool titled, String partial = ''}) {
  final rendered = renderNote(segments, partial, RenderOptions(titled: titled));
  return (markdown: rendered.markdown, pendingFrom: rendered.pendingFrom);
}
