/// The second example canvas, added from Settings beside the first (sample_canvas.dart): how Ghost.md works, in
/// plain words (Matt: "Add a simpler canvas explaining how Glyph works in simpler terms"). Eight cards a person can
/// read in a minute, with the lines telling the order: you say it, the marks are said too, it lands as a note, the
/// note is kept, it can be a board or a canvas, and none of it leaves the phone. A port of
/// `src/app/canvas/howCanvas.ts`.
///
/// Two of the cards are the example board and the sample note themselves, so tapping them opens the real thing.
///
/// What differs: the web holds its words to the recorder (howCanvas.test.ts renders each named cue through
/// `capture/markdown.ts`); the recorder is stage 8, so that half of its test waits for it.
library;

import '../core/iphone_app.dart' show recordsVoice;
import 'json_canvas.dart';
import 'sample_canvas.dart';

/// `HOW_TITLE`.
const String howTitle = 'How Ghost.md works';

/// The canvas as an iPhone is given it (Matt, 2026-10-13, before the Flutter build went to the App Store): the
/// iPhone app records nothing ([recordsVoice]), so its cards speak of writing, name no microphone and no side key,
/// and say nothing of an AI that hears. The cards' ids, places and lines are the same; only the words differ. A
/// canvas already made (the one an account holds from another device) keeps the words it was made with.
const Map<String, String> _typedWords = {
  'saying': 'From your words to the page',
  'speak': '# Write it\n\nTap **+** on the home page and type. Ghost.md keeps the words as you write them.',
  'marks': '# Type the marks too\n\nA `#` for a heading, a dash for a point, a dash and a box for a to-do, and Ghost.md draws them. No menus.',
  'note': '# It lands as a note\n\nPlain Markdown you can read anywhere. Fix a word with a finger.',
  'phone': '# It stays on your phone\n\nNo account is needed. Without one, nothing you write goes anywhere else.',
};

/// [voice] false is the canvas for a build that records nothing; null asks the platform ([recordsVoice]).
Canvas howCanvas({bool? voice}) {
  final spoken = voice ?? recordsVoice;
  String words(String id, String said) => spoken ? said : _typedWords[id]!;
  return Canvas(
    nodes: [
      // Saying it, in a group on the left: the three steps from a voice to a note.
      CanvasNode.group(id: 'saying', x: -40, y: -60, width: 640, height: 480, label: words('saying', 'From your voice to the page'), color: '5'),
      CanvasNode.text(id: 'speak', x: 0, y: 0, width: 260, height: 170, color: '4', text: words('speak', '# Say it\n\nTap the **microphone**, or press the side key, and talk. Ghost.md writes the words as you say them.')),
      CanvasNode.text(id: 'marks', x: 320, y: 0, width: 260, height: 170, text: words('marks', '# Say the marks too\n\nSay *heading*, *bullet point*, *check box* or *done task*, and Ghost.md draws them. No menus.')),
      CanvasNode.text(id: 'note', x: 160, y: 220, width: 260, height: 170, text: words('note', '# It lands as a note\n\nPlain Markdown you can read anywhere. Fix a word with a finger or with your voice.')),
      // Where a note goes, on the right.
      CanvasNode.text(id: 'library', x: 760, y: -40, width: 260, height: 170, text: '# All your notes\n\nThe sidebar keeps them. Search finds any word. Tabs hold the ones you are using.'),
      CanvasNode.file(id: 'board', x: 760, y: 170, width: 260, height: 150, file: '$boardTitle.md'),
      CanvasNode.text(id: 'canvas', x: 760, y: 360, width: 260, height: 190, text: '# Or a canvas\n\nCards on a page with lines between them. This is one: hold a card to move it, double-tap the page to add one.'),
      CanvasNode.text(id: 'phone', x: 160, y: 480, width: 260, height: 170, color: '2', text: words('phone', '# It stays on your phone\n\nThe AI that hears you runs on the phone itself. Nothing you say goes anywhere else.')),
      CanvasNode.file(id: 'every', x: 1120, y: 170, width: 260, height: 150, file: '$sampleTitle.md'),
    ],
    edges: [
      CanvasEdge.of(id: 'e1', fromNode: 'speak', toNode: 'marks', fromSide: Side.right, toSide: Side.left, label: 'and'),
      CanvasEdge.of(id: 'e2', fromNode: 'marks', toNode: 'note', fromSide: Side.bottom, toSide: Side.top, label: 'then'),
      CanvasEdge.of(id: 'e3', fromNode: 'note', toNode: 'library', fromSide: Side.right, toSide: Side.left, label: 'kept with'),
      CanvasEdge.of(id: 'e4', fromNode: 'note', toNode: 'board', fromSide: Side.right, toSide: Side.left, label: 'with columns, it is a board'),
      CanvasEdge.of(id: 'e5', fromNode: 'note', toNode: 'canvas', fromSide: Side.right, toSide: Side.left, label: 'or laid out'),
      CanvasEdge.of(id: 'e6', fromNode: 'note', toNode: 'phone', fromSide: Side.bottom, toSide: Side.top, toEnd: End.none, color: '2'),
      CanvasEdge.of(id: 'e7', fromNode: 'board', toNode: 'every', fromSide: Side.right, toSide: Side.left, toEnd: End.none, label: 'every mark a note can hold'),
    ],
  );
}

String howCanvasBody({bool? voice}) => canvasNoteBody(howTitle, howCanvas(voice: voice));
