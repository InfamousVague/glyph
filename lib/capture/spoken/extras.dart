/// The marks said inside a sentence that are not emphasis: tags, counters, links to a note, an item or a page, a
/// line's name, the bookmark, emoji, a line break, and footnotes. A port of `src/app/capture/spoken/extras.ts`.
///
/// Each is a phrase with its own ending ("note link … end link", "anchor … end anchor") or a word that cannot be
/// anything else ("hashtag", "emoji"), so they are read out of the paragraph before it is cut into sentences. The
/// ones that belong at the end of a line - a line's name, the bookmark - and a break between lines leave a stand-in
/// where they were said (spoken/stand_ins.dart), and [finishLines] writes the real marks once the lines are known.
/// Pure but for the note titles a spoken link may name, which the recorder sets as it opens ([setLinkTitles]).
///
/// What differs: nothing. The titles are this library's own state, as they are the web module's.
library;

import '../../core/emoji.dart';
import '../../core/item_syntax.dart';
import '../../core/text.dart';
import '../../core/title_key.dart';
import '../route.dart' show Candidate, matchNote;
import 'numbers.dart';
import 'stand_ins.dart';

/// "Counter three of eight": a counter (`[3/8]`), at the end of what it counts.
final RegExp _counterSaid = RegExp(
  '[.,;]?\\s*\\bcounter\\s+($numberPhrase)\\s+(?:of|out\\s+of)\\s+($numberPhrase)(?=[\\s.,;:!?]|\$)',
  caseSensitive: false,
);

/// "Hashtag travel": a tag. Whisper often writes "#travel" itself, which is left as it is.
final RegExp _tagSaid = RegExp(r'\bhash[\s-]?tag\s+([A-Za-z][\w-]*)', caseSensitive: false);

/// "Note link weekend trip end link": a link to another note (`[[Weekend trip]]`).
final RegExp _noteLinkSaid = RegExp(r'\b(?:no(?:te|de)\s?link|link\s+to\s+note)[,:]?\s+(.+?)[.,]?\s+(?:end|and)\s+link\b', caseSensitive: false);

/// Titles of the notes a spoken link can name, set by the recorder: a link takes the note's own spelling. A library's
/// own state, as the spoken formats are (spoken/inline.dart), set as the recorder opens and by the voice suite per
/// test.
List<String> _linkTitles = const [];

void setLinkTitles(List<String> titles) {
  _linkTitles = titles;
}

/// "Item link ask Sam end link": a link to a line of this note by its name (`[[#^ask-sam]]`).
final RegExp _itemLinkSaid = RegExp(r'\bitem\s?link[,:]?\s+(.+?)[.,]?\s+(?:end|and)\s+link\b', caseSensitive: false);

/// "Link Glyph to attack dot fm end link", "link attack dot fm end link": a link to a page.
final RegExp _linkSaid = RegExp(r'\blink[,:]?\s+(.+?)[.,]?\s+(?:end|and)\s+link\b', caseSensitive: false);

/// "Anchor ship page end anchor": the line's own name (` ^ship-page`), moved to the end of its line when the note is
/// laid out.
final RegExp _anchorSaid = RegExp(
  r'[.,]?\s*\b(?:anchor|item\s+name)[,:]?\s+(.+?)[.,]?\s+(?:end|and)\s+(?:anchor|name)\b([.,!?]?)',
  caseSensitive: false,
);

/// "Bookmark this", "bookmark here", at the end of what it marks: the note's bookmark (`§§`).
final RegExp _bookmarkSaid = RegExp(r'[.,]?\s*\bbookmark\s+(?:this(?:\s+line)?|here)\b(?=[.,!?]|\s*$)([.,!?]?)', caseSensitive: false);

/// "Emoji party popper": the emoji by its name, as a shortcode (`:tada:`, core/emoji.dart).
final RegExp _emojiSaid = RegExp(r'\bemoji[,:]?\s+([A-Za-z]+(?:[\s-]+[A-Za-z]+){0,3})', caseSensitive: false);

/// "… end unsure, note Sam said four hundred, end note": what a mark means, shown on a tap
/// (`??four hundred??(Sam said…)`).
final RegExp _markNoteSaid = RegExp(
  r'(\?\?|==|%%|\*\*|\^\^|\+\+|~~|\|\||\b_)[.,]?\s+(?:with\s+(?:a\s+)?)?note[,:]?\s+(.+?)[.,]?\s+(?:end|and)\s+note\b',
  caseSensitive: false,
);

/// "…, new line, …" with a pause either side: a line break inside the paragraph. "A new line of shoes" is words.
final RegExp _lineBreakSaid = RegExp(r'(^|[.,;!?])\s*\b(?:new|next)\s+line\b[.,;!]?(?=\s|$)', caseSensitive: false);

/// "Footnote Sam said so end footnote": a footnote marker where it was said, its words under the note.
final RegExp _footnoteSaid = RegExp(
  r'([.!?]?)[,]?\s*\bfoot\s?note[,:.]?\s+(.+?)[.,]?\s+(?:end|and)\s+foot\s?note\b([.,!?]?)',
  caseSensitive: false,
);

/// The spoken names people give emoji, where they differ from the shortcode.
const Map<String, String> _emojiSaidAs = {
  'thumbs_up': '+1',
  'thumbs_down': '-1',
  'party': 'tada',
  'party_popper': 'tada',
  'celebration': 'tada',
  'check': 'white_check_mark',
  'check_mark': 'white_check_mark',
  'tick': 'white_check_mark',
  'cross': 'x',
  'cross_mark': 'x',
  'light_bulb': 'bulb',
  'laughing': 'joy',
  'crying': 'sob',
  'smiley': 'smile',
  'money_bag': 'moneybag',
  'magnifying_glass': 'mag',
  'lightning': 'zap',
  'plane': 'airplane',
  'sun': 'sunny',
  'pin': 'pushpin',
};

final RegExp _notSlug = RegExp('[^a-z0-9]+');
final RegExp _edgeDashes = RegExp(r'^-+|-+$');

/// A spoken name as a line's name: "Ship Page" is `ship-page`, as said (core/boards.dart reads
/// `[a-z0-9][a-z0-9_-]*`).
String spokenSlug(String text) => text.toLowerCase().replaceAll(_notSlug, '-').replaceAll(_edgeDashes, '');

final RegExp _dot = RegExp(r'\s*\b(?:dot)\b\s*');
final RegExp _slash = RegExp(r'\s*\b(?:forward\s+)?slash\b\s*');
final RegExp _colon = RegExp(r'\s*\bcolon\b\s*');
final RegExp _dash = RegExp(r'\s*\b(?:dash|hyphen)\b\s*');
final RegExp _underscore = RegExp(r'\s*\bunderscore\b\s*');
final RegExp _aroundSign = RegExp(r'\s*([./:])\s*');
final RegExp _stopsAtEnd = RegExp(r'[.,]+$');
final RegExp _address = RegExp(r'^(?:https?:\/\/)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?:[/?#]\S*)?$');
final RegExp _scheme = RegExp(r'^https?:\/\/');

/// "attack dot fm slash glyph" as `https://attack.fm/glyph`, or null when it isn't an address.
String? spokenAddress(String text) {
  final said = text
      .trim()
      .toLowerCase()
      .replaceAll(_dot, '.')
      .replaceAll(_slash, '/')
      .replaceAll(_colon, ':')
      .replaceAll(_dash, '-')
      .replaceAll(_underscore, '_')
      .replaceAllMapped(_aroundSign, (m) => m.group(1)!)
      .replaceFirst(_stopsAtEnd, '');
  // Words still apart are words: "Glyph to attack.fm" is a name and an address, not one address.
  if (!_address.hasMatch(said)) return null;
  return _scheme.hasMatch(said) ? said : 'https://$said';
}

final RegExp _wordGap = RegExp(r'[\s-]+');

String _spokenEmoji(Match found) {
  final all = found.group(0)!, words = found.group(1)!;
  final said = words.toLowerCase().split(_wordGap);
  for (var take = said.length; take >= 1; take -= 1) {
    final name = said.sublist(0, take).join('_');
    final code = _emojiSaidAs[name] ?? (emojiFor(name) != null ? name : null);
    if (code != null) {
      final rest = words.split(_wordGap).sublist(take).join(' ');
      return ':$code:${rest.isNotEmpty ? ' $rest' : ''}';
    }
  }
  return all;
}

final RegExp _article = RegExp(r'^(?:the|my|our)\s+', caseSensitive: false);
final RegExp _noteAtEnd = RegExp(r'\s+note$', caseSensitive: false);
final RegExp _to = RegExp(r'\s+to\s+', caseSensitive: false);
final RegExp _fullStop = RegExp('[.!?]');

String? _knownTitle(String said) {
  for (final title in _linkTitles) {
    if (titleKey(title) == titleKey(said)) return title;
  }
  return matchNote(said, [for (final title in _linkTitles) Candidate(id: title, title: title)])?.note.title;
}

/// Tags, counters, links, emoji and the other marks said inside a sentence, written as what they are.
String spokenExtras(String paragraph) {
  return paragraph
      .replaceAllMapped(_itemLinkSaid, (found) {
        final slug = spokenSlug(found.group(1)!);
        return slug.isNotEmpty ? '[[#^$slug]]' : found.group(0)!;
      })
      .replaceAllMapped(_noteLinkSaid, (found) {
        final said = found.group(1)!.trim().replaceFirst(_article, '').replaceFirst(_noteAtEnd, '');
        // The note's own spelling, and the closest title when the name was misheard ("week and trip").
        return '[[${_knownTitle(said) ?? capitalise(said)}]]';
      })
      .replaceAllMapped(_linkSaid, (found) {
        final inner = found.group(1)!;
        final bare = spokenAddress(inner);
        if (bare != null) return '<$bare>';
        // "Glyph to attack dot fm": the words, then where they go, split at the last "to" that leaves an address.
        final parts = inner.split(_to);
        for (var at = parts.length - 1; at >= 1; at -= 1) {
          final address = spokenAddress(parts.sublist(at).join(' to '));
          final words = parts.sublist(0, at).join(' to ').trim();
          if (address != null && words.isNotEmpty) return '[$words]($address)';
        }
        return found.group(0)!;
      })
      .replaceAllMapped(_markNoteSaid, (found) => '${found.group(1)}(${found.group(2)!.trim()})')
      .replaceAllMapped(_anchorSaid, (found) {
        final slug = spokenSlug(found.group(1)!);
        return slug.isNotEmpty ? '$anchorMark$slug$anchorMark${found.group(2)}' : found.group(0)!;
      })
      .replaceAllMapped(_bookmarkSaid, (found) => '$bookmarkMark${found.group(1)}')
      .replaceAllMapped(_emojiSaid, _spokenEmoji)
      .replaceAllMapped(_lineBreakSaid, (found) {
        final before = found.group(1)!;
        return '${before.isNotEmpty && _fullStop.hasMatch(before)
            ? before
            : before.isNotEmpty
            ? '.'
            : ''}$breakMark';
      })
      .replaceAllMapped(_tagSaid, (found) => '#${found.group(1)!.toLowerCase()}')
      .replaceAllMapped(_counterSaid, (found) {
        final n = spokenNumber(found.group(1)!);
        final m = spokenNumber(found.group(2)!);
        return n == null || m == null || m < 1 ? found.group(0)! : ' [$n/$m]';
      });
}

final RegExp _commasAtEnd = RegExp(r'[,;]+$');
final RegExp _endsInStop = RegExp(r'[.!?]$');

/// The footnotes said in [text] lifted out: each one's words pushed onto [footnotes], in order, and a marker
/// (`[^1]`) left where it was said. The notes are written under the whole note (capture/markdown.dart `renderNote`).
String liftFootnotes(String text, List<String> footnotes) {
  return text.replaceAllMapped(_footnoteSaid, (found) {
    final before = found.group(1)!, after = found.group(3)!;
    final words = capitalise(found.group(2)!.trim().replaceFirst(_commasAtEnd, ''));
    footnotes.add(_endsInStop.hasMatch(words) ? words : '$words.');
    return '[^${footnotes.length}]${after.isNotEmpty ? after : before}';
  });
}

final RegExp _breakThenWord = RegExp('$breakMark *(\\S)');
final RegExp _nameOn = RegExp('$anchorMark([^$anchorMark]*)$anchorMark');
final RegExp _spaceBeforeStop = RegExp(r'\s+([.,;!?])');
final RegExp _spaces = RegExp(r' {2,}');
final RegExp _itemStop = RegExp(r'[.,;]+$');

/// The stand-ins put back as marks, once the note is laid out: a line break where one was said, a line's name at the
/// end of its line (after the bookmark, as core/boards.dart reads it), and the bookmark on the last line it was said
/// on, since a note holds one.
String finishLines(String body) {
  final lines = body.replaceAllMapped(_breakThenWord, (found) => '  \n${found.group(1)!.toUpperCase()}').replaceAll(breakMark, '').split('\n');
  var marked = -1;
  for (var index = 0; index < lines.length; index += 1) {
    if (lines[index].contains(bookmarkMark)) marked = index;
  }
  final used = <String>{};
  final out = <String>[];
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final names = [for (final found in _nameOn.allMatches(line)) found.group(1) ?? ''];
    if (names.isEmpty && !line.contains(bookmarkMark)) {
      out.add(line);
      continue;
    }
    final broken = line.endsWith('  ');
    var text = line.replaceAll(_nameOn, '').replaceAll(bookmarkMark, '').replaceAllMapped(_spaceBeforeStop, (m) => m.group(1)!).replaceAll(_spaces, ' ').trimRight();
    // A list item's words end without a stop, before its bookmark and name.
    if (listLead(text) != null) text = text.replaceFirst(_itemStop, '');
    if (index == marked) text += ' $bookmarkSigns';
    final name = names.isNotEmpty ? names.last : '';
    if (name.isNotEmpty) {
      var unique = name;
      for (var count = 2; used.contains(unique); count += 1) {
        unique = '$name-$count';
      }
      used.add(unique);
      text += ' ^$unique';
    }
    out.add(broken ? '$text  ' : text);
  }
  return out.join('\n');
}
