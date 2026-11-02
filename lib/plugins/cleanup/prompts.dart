/// What the AI is told, and what it is sent (docs/CLEANUP.md, "The plan the AI answers with"): one system prompt for a
/// run, naming only the passes that are on and the JSON each answers with; a prompt per batch with its notes' titles,
/// folders and first characters under short refs; and Tidy's own prompt for one whole note.
///
/// The sizes are the page's promise of what is sent ([CleanupSizes]): a cloud model is sent 40 notes an ask and 600
/// characters of each, the device's model 12 and 400, since it reads about 20,000 characters at a time.
library;

import 'plan.dart';

/// How much of the folder goes in one ask.
class CleanupSizes {
  const CleanupSizes({required this.notesPerAsk, required this.charsPerNote});

  final int notesPerAsk;
  final int charsPerNote;

  /// A cloud model's.
  static const CleanupSizes cloud = CleanupSizes(notesPerAsk: 40, charsPerNote: 600);

  /// The on-device model's.
  static const CleanupSizes device = CleanupSizes(notesPerAsk: 12, charsPerNote: 400);
}

/// The system prompt for a run with [options].
String cleanupSystem(CleanupOptions options) {
  final on = options.passes;
  final shape = <String>[
    if (on.contains(CleanupPass.sort)) ...[
      '  "folders": [{"ref": "new1", "name": "Short folder name", "parent": "f0", "why": "…"}],',
      '  "moves": [{"note": "n3", "to": "f2 or new1", "why": "…"}],',
    ],
    if (on.contains(CleanupPass.titles)) '  "titles": [{"note": "n1", "title": "A better title", "why": "…"}],',
    if (on.contains(CleanupPass.duplicates)) '  "duplicates": [{"keep": "n4", "others": ["n5"], "why": "…"}],',
    if (on.contains(CleanupPass.tidy)) '  "tidy": [{"note": "n6", "why": "…"}],',
    if (on.contains(CleanupPass.links)) ...[
      '  "tags": [{"note": "n7", "tags": ["tag"], "why": "…"}],',
      '  "links": [{"note": "n7", "to": ["n8"], "why": "…"}],',
    ],
    if (on.contains(CleanupPass.stale)) '  "stale": [{"note": "n9", "why": "…"}],',
  ];
  final rules = <String>[
    if (on.contains(CleanupPass.sort))
      '- Sort: suggest which folder each note belongs in. Use the folders that exist (f0 is the folder being cleaned up, f1… are inside it) before making new ones. Make at most $cleanupMaxNewFolders new folders, each a short plain name, ${options.deeper ? 'inside f0 or one of its folders' : 'directly inside f0 (parent "f0")'}. Only move a note when the folder clearly fits it better than where it is; leave the rest alone.',
    if (on.contains(CleanupPass.titles))
      '- Titles: suggest a title only for a note with no title, "Untitled", a date alone, or a title that does not say what the note is about. A title is a few words, in the note\'s own language, with no "#", quotes or date unless the date is the point.',
    if (on.contains(CleanupPass.duplicates))
      '- Duplicates: group notes that are the same note more than once (the same meeting copied, a "(shared)" copy, the same paste twice). Not notes that are merely about the same subject. "keep" is the fullest one.',
    if (on.contains(CleanupPass.tidy))
      '- Tidy: list notes whose Markdown is broken or messy (a "#" with no words, headings that skip levels, list markers mixed, empty sections). You will be asked to fix each one separately; do not fix them here.',
    if (on.contains(CleanupPass.links))
      '- Tags and links: suggest up to $cleanupMaxTags short tags for a note (letters, digits, "-", "_", "/"; no "#"), and up to $cleanupMaxLinks notes of this list that a note should link to because they are about the same thing.',
    if (on.contains(CleanupPass.stale))
      '- Stale: list notes that look abandoned: empty, a few words with nothing to do, or a draft nobody came back to. They go to the Archive, not the Trash.',
  ];
  return [
    'You help someone tidy one folder of their notes. You are shown each note\'s ref (n1, n2, …), title, folder and first words, and the folders (f0, f1, …).',
    'You only suggest; the person reviews every suggestion before anything changes. Suggest little and only what clearly helps. When unsure, leave a note alone.',
    'Refer to notes and folders only by their refs. Never invent a ref. Leave out any list you have nothing for.',
    '',
    ...rules,
    '',
    'Answer with one JSON object and nothing else, in this shape:',
    '{',
    ...shape,
    '}',
  ].join('\n');
}

/// The first [chars] characters of [body], cut at a word, its front matter left out.
String notePeek(String body, int chars) {
  var text = body;
  if (text.startsWith('---')) {
    final end = text.indexOf('\n---', 3);
    if (end > 0) text = text.substring(end + 4);
  }
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  if (text.length <= chars) return text;
  final cut = text.lastIndexOf(RegExp(r'\s'), chars);
  return '${text.substring(0, cut > chars ~/ 2 ? cut : chars)}…';
}

/// What one batch is sent: the folders by ref with their paths, then each note by ref with its title, its folder, its
/// date and its first [CleanupSizes.charsPerNote] characters.
String cleanupBatchPrompt(CleanupBatch batch, CleanupSizes sizes, {DateTime Function()? now}) {
  final scope = batch.scope;
  String day(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  final lines = <String>[
    'Folder being cleaned up: f0, “${scope.root.path}”.',
    'Folders:',
    for (final folder in scope.folders) '- ${batch.refOfFolder(folder.id)}: ${folder.path}',
    '',
    'Notes (${batch.notes.length}):',
  ];
  for (final note in batch.notes) {
    lines
      ..add('')
      ..add('[${batch.refOfNote(note.id)}] ${note.title.isEmpty ? '(no title)' : '“${note.title}”'} · in ${batch.refOfFolder(note.folderId)} · edited ${day(note.updatedAt)}')
      ..add(notePeek(note.body, sizes.charsPerNote));
  }
  if (now != null) lines.insert(0, 'Today is ${day(now().millisecondsSinceEpoch)}.');
  return lines.join('\n');
}

/// Tidy's system prompt: formatting only, or (with [rewrite]) clearer words too.
String tidySystem({required bool rewrite}) => [
      'You fix the Markdown formatting of one note.',
      if (rewrite)
        'You may also rewrite sentences for clarity, keeping every fact, name, number, link and to-do, in the note\'s own language and voice.'
      else
        'Do not change, add, remove or reorder any of the person\'s words. Change only formatting: heading levels and stray "#", list markers, spacing, empty sections with no words under them.',
      'Keep front matter (between --- lines), links, tags, to-do boxes, code and tables exactly as they are.',
      'Answer with the whole note and nothing else: no explanation, no code fence round it.',
    ].join('\n');

/// What Tidy is sent for one note: the note whole.
String tidyPrompt(CleanupNote note, String why) => [
      if (why.isNotEmpty) 'What looked wrong: $why',
      'The note:',
      '',
      note.body,
    ].join('\n');

/// The page's sentence of what is sent, for [aiName] with [sizes] ([local] for the device's own model).
String sentWords(String aiName, CleanupSizes sizes, {required bool local, required CleanupOptions options}) {
  final where = local ? 'to the model on this device, and nothing leaves it' : 'to $aiName, with your key, through its plugin';
  final tidy = options.has(CleanupPass.tidy) ? ' A note’s whole text is sent only when Tidy asks to fix its formatting.' : '';
  return 'Each note’s title, the folder it is in and its first ${sizes.charsPerNote} characters go $where, ${sizes.notesPerAsk} notes at a time.$tidy Nothing is sent until you press Look for changes.';
}
