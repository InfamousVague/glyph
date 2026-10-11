/// Lists said the way people say them, not in cue words: "I need eggs, milk and bread", "the next item is oat milk",
/// "here's my shopping list" and the short sentences after it, and Whisper's own "1. 2. 3." when it hears a list. A
/// port of `src/app/capture/spoken/lists.ts`.
///
/// Deliberately high-precision, as every rule here is (capture/markdown.dart): a missed list is still readable prose,
/// and a false one mangles it. So an enumeration needs a word that introduces a list before its items, an item phrase
/// needs an ordinal or the word "list", and an announced list takes only short, noun-shaped sentences. Pure.
///
/// What differs: [announcesList] answers a [ListKind] where the web answers `'number' | 'bullet'`, and
/// [enumeration] a record where the web answers an object literal.
library;

import '../../core/text.dart';
import 'numbers.dart';
import 'words.dart';

/// Which list a sentence announced, or an open list is: numbered or bullets (the web's `'number' | 'bullet'`).
enum ListKind { number, bullet }

/// Words after which a comma-separated run is a list rather than a clause.
///
/// The whole precision of the enumeration rule rests here. "I need eggs, milk and bread" is a list because of "need";
/// "we went to the store, bought food, and came home" has the same commas and is not, and the difference is that
/// nothing before its first comma introduces a list.
final RegExp _listIntro = RegExp(
  r'\b(?:need|needs|want|wants|buy|get|grab|bring|pack|include|includes|including|like|such\s+as|are|were|is|was|with|pick\s+up)$',
  caseSensitive: false,
);

// Lists said the way people actually say them, not in cue words. Matt's first real list on the Fold was "list item is
// weed", "the next list item is …" and "and lastly, the final item that we need on our list is a gallon of black
// coffee": all prose under the cue rules, because nobody says "bullet point" to a phone.
//
// An item phrase names an item and then gives it: "list item is X", "the next item is X", "another one is X", "item
// number three is X", "the last thing we need on the list is X". Still high precision: a bare "item" or "thing" needs
// an ordinal or the word "list" with it, so "the thing is, I'm tired" and "the item is broken" stay sentences.
const String _leaders = r'(?:(?:and|so|ok(?:ay)?|also|plus|then|lastly|finally|next|oh)[,\s]+)*';
const String _article = r'(?:(?:the|a|an|my|our)\s+)?';
const String _ordinalWord = r'(?:first|second|third|fourth|fifth|sixth|next|last|final|another|other|new|1st|2nd|3rd|4th|5th)';
const String _namedItem =
    // "list item", "the next list item", "list item number two"
    '(?:$_ordinalWord\\s+)?list\\s+(?:item|entry)(?:\\s+(?:number\\s+)?$smallNumber)?'
    // "the next item", "another thing", "the final one", "item number two"
    '|$_ordinalWord\\s+(?:item|thing|entry|one)(?:\\s+(?:number\\s+)?$smallNumber)?'
    '|item\\s+number\\s+$smallNumber'
    // "the item on the list", "the thing we need on our list"
    r'|(?:item|thing)(?=.*\b(?:on|in|for|to)\s+(?:the|our|my|this)\s+(?:\w+\s+)?list\b)';
const String _which =
    r"(?:\s+(?:that\s+|which\s+)?(?:we|i|you)(?:'ll|\s+will)?\s+(?:really\s+)?(?:need|want|have|should\s+get|need\s+to\s+(?:get|buy|add|grab))(?:\s+to\s+(?:get|buy|add|grab))?)?";
const String _onList = r'(?:\s+(?:on|in|for|to)\s+(?:the|our|my|this)\s+(?:\w+\s+)?list)?';
final RegExp _itemPhrase = RegExp(
  '^$_leaders$_article(?:$_namedItem)$_which$_onList'
  r'\s*(?:is|are|will\s+be|would\s+be|should\s+be|[:,-])\s+(.+)$',
  caseSensitive: false,
);

/// An item phrase that stops before its item: "The next item is." Whisper commits a phrase at a breath, so "the next
/// item is … Paris" arrives as two: the phrase, then the item. Held, and the next sentence is taken as the item.
final RegExp _itemOpener = RegExp(
  '^$_leaders$_article(?:$_namedItem)$_which$_onList'
  r'\s*(?:is|are|will\s+be|would\s+be|should\s+be)?\s*[.:,-]?\s*$',
  caseSensitive: false,
);

/// Whether [text] is an item phrase that stopped before its item ("The next item is."), waiting for the next
/// sentence.
bool opensItem(String text) => _itemOpener.hasMatch(text);

final RegExp _inlineMarker = RegExp(r'(^|\s)(\d{1,2})\.\s+(?=\S)');

/// Whisper's own numbering, written inline when it hears a list being dictated: "1. The Grand Canyon 2. Spain 3. The
/// next item is". Two or more markers counting up one at a time are that; each piece becomes a spoken "number N," cue
/// so the numbered rule lays it out, and a piece that is only an item phrase is left for the next phrase to finish. A
/// year ("1990.") or a lone "2." in a sentence is not a run.
String inlineNumbering(String paragraph) {
  final markers = _inlineMarker.allMatches(paragraph).toList();
  if (markers.length < 2) return paragraph;
  final numbers = [for (final m in markers) int.parse(m.group(2)!)];
  for (var i = 1; i < numbers.length; i += 1) {
    if (numbers[i] != numbers[i - 1] + 1) return paragraph;
  }
  final starts = [for (final m in markers) m.start + (m.group(1) ?? '').length];
  final prefix = paragraph.substring(0, starts[0]).trim();
  final pieces = <String>[];
  for (var i = 0; i < markers.length; i += 1) {
    final bodyStart = markers[i].end;
    final end = i + 1 < starts.length ? starts[i + 1] : paragraph.length;
    final text = stripEnd(paragraph.substring(bodyStart, end < bodyStart ? bodyStart : end).trim());
    if (text.isEmpty) {
      pieces.add('');
    } else {
      pieces.add(_itemOpener.hasMatch(text) ? '${capitalise(text)}.' : 'Number ${numbers[i]}, $text.');
    }
  }
  return [prefix, ...pieces].where((piece) => piece.isNotEmpty).join(' ');
}

/// The item an item phrase gives, or null: "The next list item is oat milk." is "Oat milk".
String? itemOf(String text) {
  final match = _itemPhrase.firstMatch(text.trim());
  final given = match?.group(1);
  final item = given != null && given.isNotEmpty ? stripEnd(given.trim()) : '';
  return item.isNotEmpty ? capitalise(item) : null;
}

/// A sentence that announces a list: "add a list below", "here's my shopping list", "make a numbered list". Its own
/// words stay; the short sentences after it are taken as the list's items until a longer one ends it.
final RegExp _listAnnounce = RegExp(
  r'\b(?:add|make|start|create|write|begin|do)\s+(?:up\s+)?(?:a|an|the|my|our|this|another)?\s*(?:new\s+|quick\s+)?(?:(numbered|numbering|ordered|bullet(?:ed)?|bullet\s+point|shopping|grocery|to-?\s?do|packing|reading|check)\s+)?list\b'
  r"|\b(?:here(?:'s|\s+is)|this\s+is|that'?s)\s+(?:a|the|my|our)\s+(?:(numbered|\w+)\s+)?list\b",
  caseSensitive: false,
);

/// "Pack these.", "we need the following.": a list said with its colon heard as a full stop.
final RegExp _listLead = RegExp(r'^(?:[a-z]+\s+){0,4}(?:these|the\s+following|as\s+follows)[.:]?$', caseSensitive: false);
final RegExp _leadTail = RegExp(r'\s+(?:these|the\s+following|as\s+follows)[.:]?$', caseSensitive: false);
final RegExp _numberedKind = RegExp(r'^(?:numbered|numbering|ordered)$');

/// Whether [text] is a line a list hangs from, its colon heard as a full stop: "Pack these."
bool leadsList(String text) => _listLead.hasMatch(text.trim());

/// Whether [text] announces a list, and whether it asked for numbers.
ListKind? announcesList(String text) {
  if (_listLead.hasMatch(text.trim()) && _listIntro.hasMatch(text.trim().replaceFirst(_leadTail, ''))) return ListKind.bullet;
  final match = _listAnnounce.firstMatch(text);
  if (match == null) return null;
  final kind = (match.group(1) ?? match.group(2) ?? '').toLowerCase();
  return _numberedKind.hasMatch(kind) ? ListKind.number : ListKind.bullet;
}

/// Short enough, and noun-shaped enough, to be an item in a list someone announced.
const int _maxOpenItemWords = 5;
final RegExp _question = RegExp(r'\?\s*$');
final RegExp _sentenceStart = RegExp(
  r"^(?:i|i'm|im|we|we're|you|he|she|it|it's|they|this|that|that's|there|there's|so|and\s+then)\b",
  caseSensitive: false,
);

bool itemShaped(String text) {
  final body = stripEnd(text);
  if (body.isEmpty || words(body) > _maxOpenItemWords || _question.hasMatch(text)) return false;
  // "I'm tired", "It works", "That's it": a sentence, not an item.
  return !_sentenceStart.hasMatch(body);
}

const int _maxItemWords = 4;
final RegExp _comma = RegExp(r',\s*');
final RegExp _space = RegExp(r'\s+');
final RegExp _pointer = RegExp(r'^(?:these|those|the\s+following)$', caseSensitive: false);
final RegExp _itemSplit = RegExp(r',\s*|\s+(?:and|or)\s+', caseSensitive: false);
final RegExp _leadingAnd = RegExp(r'^(?:and|or)\s+', caseSensitive: false);
final RegExp _conjunction = RegExp(r'\s(?:and|or)\s', caseSensitive: false);

/// "I need eggs, milk, bread and coffee" as an intro and its items, or null.
({String intro, List<String> items})? enumeration(String sentence) {
  final body = stripEnd(sentence);
  if (words(body) > 40) return null;

  String introPart;
  String listPart;

  final colon = body.indexOf(':');
  if (colon > 0) {
    introPart = body.substring(0, colon);
    listPart = body.substring(colon + 1);
  } else {
    final chunks = body.split(_comma);
    if (chunks.length < 2) return null;
    final first = chunks[0];
    // The intro is everything up to and including the LAST list-introducing word in the first chunk; what follows it
    // is the first item.
    final tokens = first.split(_space);
    var cut = -1;
    for (var i = tokens.length - 1; i >= 0; i -= 1) {
      if (_listIntro.hasMatch(tokens.sublist(0, i + 1).join(' '))) {
        cut = i;
        break;
      }
    }
    // "Pack these, the tent, …": "these" points at the list, so it belongs to the intro, not the first item.
    final pointsAtList = cut >= 0 && _pointer.hasMatch(tokens.sublist(cut + 1).join(' '));
    if (cut < 0 || (cut == tokens.length - 1 && !pointsAtList)) return null;
    if (pointsAtList) {
      introPart = first;
      listPart = chunks.sublist(1).join(', ');
    } else {
      introPart = tokens.sublist(0, cut + 1).join(' ');
      listPart = [tokens.sublist(cut + 1).join(' '), ...chunks.sublist(1)].join(', ');
    }
  }

  final items = listPart.split(_itemSplit).map((item) => item.replaceFirst(_leadingAnd, '').trim()).where((item) => item.isNotEmpty).toList();

  if (items.length < 3) return null;
  if (items.any((item) => words(item) > _maxItemWords)) return null;
  // A final conjunction is what makes it spoken-list shaped at all.
  if (colon < 0 && !_conjunction.hasMatch(listPart)) return null;

  return (intro: capitalise(introPart.trim()), items: items);
}
