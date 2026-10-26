// MADE, not written: read off the web app's own guide/marks.ts `markGroups()` as its page runs it, with every plugin
// that ships switched on, on 2026-10-07. Each row's icon is the kit's, by lucide's own name (lib/art/lucide.g.dart).
// ignore_for_file: prefer_single_quotes
// coverage:ignore-file

/// One mark of the cheat sheet (`MarkRow`).
class MarkRow {
  const MarkRow({required this.name, required this.symbol, required this.typed, required this.words, required this.looks, required this.icon, this.say});
  final String name;

  /// The characters themselves.
  final String symbol;

  /// A line showing it at work, as typed.
  final String typed;

  /// The words of the example.
  final String words;

  /// Which kind of mark it is (`Looks`).
  final String looks;

  /// Lucide's name for its icon.
  final String icon;

  /// How it is said to the recorder, where it can be.
  final String? say;
}

/// A group of marks, with the line under its title.
class MarkGroup {
  const MarkGroup({required this.title, required this.lead, required this.rows});
  final String title;
  final String lead;
  final List<MarkRow> rows;
}

const List<MarkGroup> markGroups = [
  MarkGroup(
    title: "Words",
    lead: "Around the words they mark, anywhere in a line.",
    rows: [
      MarkRow(name: "Bold", symbol: "**", typed: "**Friday at noon**", words: "Friday at noon", looks: "bold", icon: "bold", say: "“bold” … “end bold”"),
      MarkRow(name: "Italic", symbol: "_", typed: "_a quiet aside_", words: "a quiet aside", looks: "italic", icon: "italic", say: "“italic” … “end italic”"),
      MarkRow(name: "Both", symbol: "***", typed: "***really now***", words: "really now", looks: "both", icon: "baseline", say: "“bold italic” … “end bold italic”"),
      MarkRow(name: "Struck through", symbol: "~~", typed: "~~the old plan~~", words: "the old plan", looks: "struck", icon: "strikethrough", say: "“strike” … “end strike”"),
      MarkRow(name: "Code", symbol: "`", typed: "`npm run dev`", words: "npm run dev", looks: "code", icon: "code", say: "“code” … “end code”"),
      MarkRow(name: "A link", symbol: "[ ]( )", typed: "[Ghost.md](https://attack.fm/glyph)", words: "Ghost.md", looks: "link", icon: "link", say: "“link our site to attack dot fm end link”"),
      MarkRow(name: "A tag", symbol: "#", typed: "- [ ] Ship the pricing page #web #launch", words: "#web", looks: "tag", icon: "hash", say: "“hashtag web”"),
    ],
  ),
  MarkGroup(
    title: "Lines",
    lead: "At the start of a line, with a space after them.",
    rows: [
      MarkRow(name: "Title", symbol: "#", typed: "# Weekend trip", words: "Weekend trip", looks: "h1", icon: "heading-1", say: "“title” or “call this note”"),
      MarkRow(name: "Heading", symbol: "##", typed: "## The budget", words: "The budget", looks: "h2", icon: "heading-2", say: "“heading” or “new section”"),
      MarkRow(name: "Smaller heading", symbol: "###", typed: "### Friday", words: "Friday", looks: "h3", icon: "heading-3", say: "“subheading”"),
      MarkRow(name: "A list", symbol: "-", typed: "- Oat milk\n- Rye bread", words: "Oat milk", looks: "bullet", icon: "list", say: "“bullet point”"),
      MarkRow(name: "In order", symbol: "1.", typed: "1. Unplug it\n2. Wait a minute", words: "Unplug it", looks: "number", icon: "list-ordered", say: "“number one”, “first”"),
      MarkRow(name: "A to-do", symbol: "- [ ]", typed: "- [ ] Book the cabin", words: "Book the cabin", looks: "todo", icon: "list-todo", say: "“remember to”, “check box”"),
      MarkRow(name: "Done", symbol: "- [x]", typed: "- [x] Call Sam", words: "Call Sam", looks: "done", icon: "square-check-big", say: "“done task: …”"),
      MarkRow(name: "A due date", symbol: "📅", typed: "- [ ] Book the cabin 📅 2026-10-09", words: "Book the cabin", looks: "field", icon: "calendar-days", say: "“due Friday”"),
      MarkRow(name: "A priority", symbol: "⏫", typed: "- [ ] Fix the gate ⏫", words: "Fix the gate", looks: "field", icon: "chevrons-up", say: "“high priority”, “urgent”"),
      MarkRow(name: "A person", symbol: "@", typed: "- [ ] Book the cabin @sam", words: "sam", looks: "field", icon: "at-sign", say: "“for Sam”"),
      MarkRow(name: "A field by name", symbol: "[ :: ]", typed: "- [ ] Ask about the budget [effort:: 3]", words: "3", looks: "field", icon: "tag"),
      MarkRow(name: "A choice", symbol: "- ( )", typed: "Where do we stay?\n- ( ) Tent\n- (x) Cabin", words: "Cabin", looks: "choice", icon: "circle-dot", say: "“option: tent”, “picked option: cabin”"),
      MarkRow(name: "A counter", symbol: "[ / ]", typed: "- Water [3/8]", words: "3/8", looks: "counter", icon: "gauge", say: "“counter three of eight”"),
      MarkRow(name: "A sum", symbol: "=", typed: "= \$450 + 120 * 2", words: "\$690", looks: "sum", icon: "calculator", say: "“calculate: four hundred plus one hundred twenty”"),
      MarkRow(name: "A blank", symbol: "{?}", typed: "Cheapest day to fly: {?which day}", words: "which day", looks: "blank", icon: "square-dashed"),
      MarkRow(name: "A quote", symbol: ">", typed: "> The deposit comes back in full.", words: "The deposit comes back in full.", looks: "quote", icon: "message-square-quote", say: "“quote”"),
      MarkRow(name: "A hidden line", symbol: ">|", typed: ">| The answer is forty-two.", words: "The answer is forty-two.", looks: "spoilerLine", icon: "eye-off", say: "“hidden line: …”"),
      MarkRow(name: "Progress", symbol: "#", typed: "## Packing\n- [x] Tent\n- [ ] Stove", words: "1 of 2", looks: "progress", icon: "list-checks"),
      MarkRow(name: "A dividing line", symbol: "---", typed: "---", words: "", looks: "rule", icon: "minus", say: "“divider”"),
    ],
  ),
  MarkGroup(
    title: "Pointing somewhere",
    lead: "At another note, at a line of this one, at a place on a map, or at the small print underneath.",
    rows: [
      MarkRow(name: "Another note", symbol: "[[ ]]", typed: "the deposit is in [[The cabin trip]]", words: "The cabin trip", looks: "wiki", icon: "square-arrow-out-up-right", say: "“note link The cabin trip end link”"),
      MarkRow(name: "A name for an item", symbol: "^", typed: "- [ ] Ship the pricing page ^ship-page\n- Ask Sam about the copy ^ask-sam", words: "ship-page", looks: "anchor", icon: "anchor", say: "“anchor ship page end anchor”"),
      MarkRow(name: "That item, from the words", symbol: "[[#^ ]]", typed: "the page is waiting on [[#^ask-sam]]\n\n- Ask Sam about the copy ^ask-sam", words: "ask-sam", looks: "itemRef", icon: "link", say: "“item link ask Sam end link”"),
      MarkRow(name: "The bookmark", symbol: "§§", typed: "the deposit is four hundred §§", words: "the deposit is four hundred", looks: "bookmark", icon: "bookmark", say: "“… bookmark this”"),
      MarkRow(name: "A place", symbol: "[ ](geo: )", typed: "[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)", words: "Cais do Sodré, Lisbon", looks: "place", icon: "map-pin"),
      MarkRow(name: "A footnote", symbol: "[^ ]", typed: "four hundred[^sam]\n\n[^sam]: Sam said so.", words: "four hundred", looks: "foot", icon: "asterisk", say: "“footnote Sam said so end footnote”"),
      MarkRow(name: "A comment", symbol: "[^c1]", typed: "Call the band[^c1]\n\n```comments\nc1 sam 2026-10-04T19:00:12Z\nWhich band?\n  resolved sam 2026-10-04T19:06:02Z\n```", words: "Call the band", looks: "comment", icon: "message-square"),
    ],
  ),
  MarkGroup(
    title: "Raised and lowered",
    lead: "Around one part of a word, the way the rest of markdown writes them.",
    rows: [
      MarkRow(name: "Raised", symbol: "^ ^", typed: "the 2^nd^ of June", words: "nd", looks: "sup", icon: "superscript", say: "“superscript” … “end superscript”"),
      MarkRow(name: "Lowered", symbol: "~ ~", typed: "H~2~O", words: "2", looks: "sub", icon: "subscript", say: "“subscript” … “end subscript”"),
    ],
  ),
  MarkGroup(
    title: "Blocks",
    lead: "A few lines that work together.",
    rows: [
      MarkRow(name: "A definition", symbol: ":", typed: "Deposit\n: what you pay up front", words: "what you pay up front", looks: "definition", icon: "text-align-start", say: "“define deposit as what you pay up front”"),
      MarkRow(name: "Maths", symbol: "\$", typed: "when \$x^2 + y\$ holds", words: "\$x^2 + y\$", looks: "maths", icon: "sigma", say: "“maths x squared plus y end maths”"),
      MarkRow(name: "An emoji", symbol: ": :", typed: "shipped :tada:", words: "🎉", looks: "emoji", icon: "sticker", say: "“emoji party popper”"),
      MarkRow(name: "A table", symbol: "| |", typed: "| What | Packed |\n| --- | --- |\n| Tent | Yes |", words: "", looks: "table", icon: "table"),
      MarkRow(name: "A picture", symbol: "![ ]( )", typed: "![A cassette](image/sample-tape.svg)", words: "A cassette", looks: "picture", icon: "image"),
      MarkRow(name: "A video", symbol: "[![ ]( )]( )", typed: "[![video 0:12](image/sample-tape.svg)](video/a1b2c3.mp4)", words: "video 0:12", looks: "picture", icon: "film"),
      MarkRow(name: "A block of code", symbol: "```", typed: "```js\nconst note = \"hello\";\n```", words: "const note = \"hello\";", looks: "fence", icon: "square-code", say: "“code block in bash” … “end code block”"),
      MarkRow(name: "A callout", symbol: "[! ]", typed: "> [!NOTE]\n> The deposit comes back in full.", words: "The deposit comes back in full.", looks: "callout", icon: "info", say: "“info box: …”, “warning callout: …”"),
      MarkRow(name: "A diagram", symbol: "```mermaid", typed: "```mermaid\nflowchart TD\n  A[Speak] --> B[Note]\n  B --> C[Board]\n```", words: "flowchart TD", looks: "diagram", icon: "workflow"),
      MarkRow(name: "A board", symbol: "```board", typed: "```board\nTo do: ship-page\nDone: pick-date\n```\n\n- [ ] Ship the pricing page ^ship-page\n- [x] Pick a launch date ^pick-date", words: "ship-page", looks: "board", icon: "layout-grid"),
      MarkRow(name: "A ticket", symbol: "type: ticket", typed: "---\ntype: ticket\nid: GHO-12\nstatus: In progress\nassignee: Sam\n---\n# Fix the login loop", words: "GHO-12", looks: "ticket", icon: "ticket"),
      MarkRow(name: "A query", symbol: "```query", typed: "```query\nfrom: tickets #bug\nwhere: status != Done\nshow: board\n```", words: "from: tickets #bug", looks: "query", icon: "database"),
    ],
  ),
  MarkGroup(
    title: "Ghost.md’s own",
    lead: "Marks the app adds, all from the Marks plugin, which the Market can switch off.",
    rows: [
      MarkRow(name: "Spoiler", symbol: "||", typed: "||the cabin key||", words: "the cabin key", looks: "wisp", icon: "eye-off", say: "“spoiler” … “end spoiler”"),
      MarkRow(name: "Highlight", symbol: "==", typed: "==highlight this==", words: "highlight this", looks: "style", icon: "highlighter", say: "“highlight” … “end highlight”"),
      MarkRow(name: "Aside", symbol: "%%", typed: "%%aside this%%", words: "aside this", looks: "style", icon: "message-square-dashed", say: "“aside” … “end aside”"),
      MarkRow(name: "Unsure", symbol: "??", typed: "??unsure this??", words: "unsure this", looks: "style", icon: "circle-question-mark", say: "“unsure” … “end unsure”"),
      MarkRow(name: "Redact", symbol: "@@", typed: "@@redact this@@", words: "redact this", looks: "style", icon: "eraser", say: "“redact” … “end redact”"),
      MarkRow(name: "Shout", symbol: "^^", typed: "^^shout this^^", words: "shout this", looks: "style", icon: "megaphone", say: "“shout” … “end shout”"),
      MarkRow(name: "Added", symbol: "++", typed: "++added this++", words: "added this", looks: "style", icon: "plus", say: "“added” … “end added”"),
      MarkRow(name: "Heat", symbol: "🔥🔥", typed: "The air above wavers\n🔥🔥heat this🔥🔥", words: "heat this", looks: "effect", icon: "flame", say: "“heated” … “end heated”"),
      MarkRow(name: "Frost", symbol: "❄️❄️", typed: "❄️❄️frost this❄️❄️", words: "frost this", looks: "effect", icon: "snowflake", say: "“frosted” … “end frosted”"),
      MarkRow(name: "Wave", symbol: "🌊🌊", typed: "🌊🌊wave this🌊🌊", words: "wave this", looks: "effect", icon: "waves-horizontal", say: "“wavy” … “end wavy”"),
      MarkRow(name: "Shimmer", symbol: "✨✨", typed: "✨✨shimmer this✨✨", words: "shimmer this", looks: "effect", icon: "sparkles", say: "“shimmering” … “end shimmering”"),
      MarkRow(name: "Haunt", symbol: "👻👻", typed: "👻👻haunt this👻👻", words: "haunt this", looks: "effect", icon: "ghost", say: "“haunted” … “end haunted”"),
      MarkRow(name: "A colored highlight", symbol: "==( )", typed: "==the cabin key==(green) and ==the deadline==(red)", words: "the cabin key", looks: "tint", icon: "highlighter"),
      MarkRow(name: "A note on a mark", symbol: "( )", typed: "??four hundred??(Sam said 400)", words: "four hundred", looks: "note", icon: "info", say: "“… end unsure, note Sam said 400, end note”"),
    ],
  ),
];
