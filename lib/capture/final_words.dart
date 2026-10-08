/// The words a recording's last decode added, kept as one more phrase. A port of `src/app/capture/finalWords.ts`.
///
/// `capture_stop` drains Whisper after the page has already stopped listening for phrases (engine.dart `stop`), so
/// the words at the very end of a recording - still being decoded when Done was pressed - come back only in the
/// stop's own transcript, never as a phrase. When that transcript carries on from the phrases already committed, word
/// for word, what it adds is set after them as a phrase of its own, timed from the last one to the end of the
/// recording: the note keeps its last words and the tape's transcript keeps its timing. When it disagrees with them
/// anywhere, the phrases stand as they were heard, since they are what the tape and the better words are timed by.
///
/// The recorder compares the transcript with every phrase committed, commands and all, not with the take's words,
/// which leave the commands out and lose what went before "New note": so what the stop adds is only ever words said
/// after the last committed phrase, and it is read by the live reader like any phrase, a command still being said at
/// Done included.
///
/// What differs: the accents. The web compares words after `normalize('NFKD')` with the marks taken off; Dart has no
/// normaliser without a package, so the letters are unaccented from a table of what NFKD makes of the Latin, Greek
/// and Cyrillic letters, the ligatures and the full-width forms (made by Node from its own `normalize`), and a
/// combining mark already apart is taken off as the web takes it. A letter outside those blocks that NFKD would take
/// apart (a Hangul syllable, a Devanagari nukta letter) is compared as it is written, which still matches itself. And
/// `toLocaleLowerCase` is `toLowerCase`, the same but under a Turkish or Lithuanian locale.
library;

import 'markdown.dart';

/// A word, as it is compared: letters and digits, with an apostrophe inside one ("don't", "Sam’s").
final RegExp _word = RegExp(r"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*", unicode: true);

final RegExp _mark = RegExp(r'\p{M}', unicode: true);

/// What NFKD with its marks taken off makes of a letter: each key is the letters that become its value.
const Map<String, String> _unaccentedAs = {
  "ªàáâãäåāăąǎǟǡǻȁȃȧḁạảấầẩẫậắằẳẵặａ": "a",
  "²２": "2",
  "³３": "3",
  "µ": "μ",
  "¹１": "1",
  "ºòóôõöōŏőơǒǫǭȍȏȫȭȯȱṍṏṑṓọỏốồổỗộớờởỡợｏ": "o",
  "¼": "1⁄4",
  "½": "1⁄2",
  "¾": "3⁄4",
  "ÀÁÂÃÄÅĀĂĄǍǞǠǺȀȂȦḀẠẢẤẦẨẪẬẮẰẲẴẶＡ": "A",
  "ÇĆĈĊČḈＣ": "C",
  "ÈÉÊËĒĔĖĘĚȄȆȨḔḖḘḚḜẸẺẼẾỀỂỄỆＥ": "E",
  "ÌÍÎÏĨĪĬĮİǏȈȊḬḮỈỊＩ": "I",
  "ÑŃŅŇǸṄṆṈṊＮ": "N",
  "ÒÓÔÕÖŌŎŐƠǑǪǬȌȎȪȬȮȰṌṎṐṒỌỎỐỒỔỖỘỚỜỞỠỢＯ": "O",
  "ÙÚÛÜŨŪŬŮŰŲƯǓǕǗǙǛȔȖṲṴṶṸṺỤỦỨỪỬỮỰＵ": "U",
  "ÝŶŸȲẎỲỴỶỸＹ": "Y",
  "çćĉċčḉｃ": "c",
  "èéêëēĕėęěȅȇȩḕḗḙḛḝẹẻẽếềểễệｅ": "e",
  "ìíîïĩīĭįǐȉȋḭḯỉịｉ": "i",
  "ñńņňǹṅṇṉṋｎ": "n",
  "ùúûüũūŭůűųưǔǖǘǚǜȕȗṳṵṷṹṻụủứừửữựｕ": "u",
  "ýÿŷȳẏẙỳỵỷỹｙ": "y",
  "ĎḊḌḎḐḒＤ": "D",
  "ďḋḍḏḑḓｄ": "d",
  "ĜĞĠĢǦǴḠＧ": "G",
  "ĝğġģǧǵḡｇ": "g",
  "ĤȞḢḤḦḨḪＨ": "H",
  "ĥȟḣḥḧḩḫẖｈ": "h",
  "Ĳ": "IJ",
  "ĳ": "ij",
  "ĴＪ": "J",
  "ĵǰｊ": "j",
  "ĶǨḰḲḴＫ": "K",
  "ķǩḱḳḵｋ": "k",
  "ĹĻĽḶḸḺḼＬ": "L",
  "ĺļľḷḹḻḽｌ": "l",
  "Ŀ": "L·",
  "ŀ": "l·",
  "ŉ": "ʼn",
  "ŔŖŘȐȒṘṚṜṞＲ": "R",
  "ŕŗřȑȓṙṛṝṟｒ": "r",
  "ŚŜŞŠȘṠṢṤṦṨＳ": "S",
  "śŝşšſșṡṣṥṧṩẛｓ": "s",
  "ŢŤȚṪṬṮṰＴ": "T",
  "ţťțṫṭṯṱẗｔ": "t",
  "ŴẀẂẄẆẈＷ": "W",
  "ŵẁẃẅẇẉẘｗ": "w",
  "ŹŻŽẐẒẔＺ": "Z",
  "źżžẑẓẕｚ": "z",
  "ǄǱ": "DZ",
  "ǅǲ": "Dz",
  "ǆǳ": "dz",
  "Ǉ": "LJ",
  "ǈ": "Lj",
  "ǉ": "lj",
  "Ǌ": "NJ",
  "ǋ": "Nj",
  "ǌ": "nj",
  "ǢǼ": "Æ",
  "ǣǽ": "æ",
  "Ǯ": "Ʒ",
  "ǯ": "ʒ",
  "Ǿ": "Ø",
  "ǿ": "ø",
  "ʹ": "ʹ",
  "ͺ": " ",
  "ΆἈἉἊἋἌἍἎἏᾈᾉᾊᾋᾌᾍᾎᾏᾸᾹᾺΆᾼ": "Α",
  "ΈἘἙἚἛἜἝῈΈ": "Ε",
  "ΉἨἩἪἫἬἭἮἯᾘᾙᾚᾛᾜᾝᾞᾟῊΉῌ": "Η",
  "ΊΪἸἹἺἻἼἽἾἿῘῙῚΊ": "Ι",
  "ΌὈὉὊὋὌὍῸΌ": "Ο",
  "ΎΫϒϓϔὙὛὝὟῨῩῪΎ": "Υ",
  "ΏὨὩὪὫὬὭὮὯᾨᾩᾪᾫᾬᾭᾮᾯῺΏῼ": "Ω",
  "ΐίϊἰἱἲἳἴἵἶἷὶίιῐῑῒΐῖῗ": "ι",
  "άἀἁἂἃἄἅἆἇὰάᾀᾁᾂᾃᾄᾅᾆᾇᾰᾱᾲᾳᾴᾶᾷ": "α",
  "έϵἐἑἒἓἔἕὲέ": "ε",
  "ήἠἡἢἣἤἥἦἧὴήᾐᾑᾒᾓᾔᾕᾖᾗῂῃῄῆῇ": "η",
  "ΰϋύὐὑὒὓὔὕὖὗὺύῠῡῢΰῦῧ": "υ",
  "όὀὁὂὃὄὅὸό": "ο",
  "ώὠὡὢὣὤὥὦὧὼώᾠᾡᾢᾣᾤᾥᾦᾧῲῳῴῶῷ": "ω",
  "ϐ": "β",
  "ϑ": "θ",
  "ϕ": "φ",
  "ϖ": "π",
  "ϰ": "κ",
  "ϱῤῥ": "ρ",
  "ϲ": "ς",
  "ϴ": "Θ",
  "Ϲ": "Σ",
  "ЀЁӖ": "Е",
  "Ѓ": "Г",
  "Ї": "І",
  "Ќ": "К",
  "ЍЙӢӤ": "И",
  "ЎӮӰӲ": "У",
  "йѝӣӥ": "и",
  "ѐёӗ": "е",
  "ѓ": "г",
  "ї": "і",
  "ќ": "к",
  "ўӯӱӳ": "у",
  "Ѷ": "Ѵ",
  "ѷ": "ѵ",
  "ӁӜ": "Ж",
  "ӂӝ": "ж",
  "ӐӒ": "А",
  "ӑӓ": "а",
  "Ӛ": "Ә",
  "ӛ": "ә",
  "Ӟ": "З",
  "ӟ": "з",
  "Ӧ": "О",
  "ӧ": "о",
  "Ӫ": "Ө",
  "ӫ": "ө",
  "Ӭ": "Э",
  "ӭ": "э",
  "Ӵ": "Ч",
  "ӵ": "ч",
  "Ӹ": "Ы",
  "ӹ": "ы",
  "ḂḄḆＢ": "B",
  "ḃḅḇｂ": "b",
  "ḞＦ": "F",
  "ḟｆ": "f",
  "ḾṀṂＭ": "M",
  "ḿṁṃｍ": "m",
  "ṔṖＰ": "P",
  "ṕṗｐ": "p",
  "ṼṾＶ": "V",
  "ṽṿｖ": "v",
  "ẊẌＸ": "X",
  "ẋẍｘ": "x",
  "ẚ": "aʾ",
  "Ῥ": "Ρ",
  "ﬀ": "ff",
  "ﬁ": "fi",
  "ﬂ": "fl",
  "ﬃ": "ffi",
  "ﬄ": "ffl",
  "ﬅﬆ": "st",
  "０": "0",
  "４": "4",
  "５": "5",
  "６": "6",
  "７": "7",
  "８": "8",
  "９": "9",
  "Ｑ": "Q",
  "ｑ": "q",
};

final Map<int, String> _unaccented = {
  for (final entry in _unaccentedAs.entries)
    for (final unit in entry.key.codeUnits) unit: entry.value,
};

/// [text] as `normalize('NFKD')` with the marks taken off leaves it, for the letters the table knows.
String _plain(String text) {
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    final known = _unaccented[unit];
    if (known != null) {
      out.write(known);
    } else {
      out.writeCharCode(unit);
    }
  }
  return out.toString().replaceAll(_mark, '');
}

/// The words of [text], accents and case gone: only to tell whether one transcript carries on from another.
List<String> _wordsOf(String text) => [for (final match in _word.allMatches(text)) _plain(match.group(0)!).toLowerCase()];

final RegExp _lead = RegExp(r'^[\s,;:!?….-]+');

/// [text] after its first [count] words, as it was written, with Whisper's punctuation and casing kept.
String _afterWords(String text, int count) {
  if (count == 0) return text.trim();
  final words = _word.allMatches(text).toList();
  if (count - 1 >= words.length) return '';
  final last = words[count - 1];
  if (last.group(0)!.isEmpty) return '';
  return text.substring(last.end).replaceFirst(_lead, '').trim();
}

/// [segments] with what [transcript] says past them as one more phrase, ending at [endMs]; [segments] as they were
/// when the transcript adds nothing, says something else, or there is none (the simulated engine has none).
List<Segment> withFinalWords(List<Segment> segments, String? transcript, int endMs) {
  final finalText = transcript?.trim();
  if (finalText == null || finalText.isEmpty) return [...segments];
  final committed = _wordsOf(segments.map((segment) => segment.text).join(' '));
  final finalWords = _wordsOf(finalText);
  if (finalWords.isEmpty || committed.length >= finalWords.length) return [...segments];
  for (var index = 0; index < committed.length; index += 1) {
    if (committed[index] != finalWords[index]) return [...segments];
  }
  final suffix = _afterWords(finalText, committed.length);
  if (suffix.isEmpty) return [...segments];
  final startMs = segments.isEmpty ? 0 : segments.last.endMs;
  return [...segments, Segment(text: suffix, startMs: startMs, endMs: endMs > startMs + 1 ? endMs : startMs + 1)];
}
