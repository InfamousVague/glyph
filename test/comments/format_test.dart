import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/comments/format.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;

/// Comments in the markdown (docs/SHARED.md, S8): the anchor in the prose, the fence at the end, read without
/// rewriting and changed by a few edits, so an unchanged note comes back as the same text and a hand-edited fence
/// keeps its lines. The web's `src/app/core/comments/format.test.ts`, case for case.
final spec = [
  '# Barn dance',
  '',
  'The ==venue==[^c1] is booked.',
  '',
  '```comments',
  'c1 matt 2026-10-04T19:00:12Z',
  'The venue needs confirming - the hall or the barn?',
  '  sam 2026-10-04T19:05:40Z',
  '  The hall. Confirmed this morning.',
  '  resolved sam 2026-10-04T19:06:02Z',
  '```',
  '',
].join('\n');

const matt = Stamp(by: 'matt', at: '2026-10-05T09:00:00Z');
const sam = Stamp(by: 'sam', at: '2026-10-05T09:10:00Z');

/// The note after [edits], failing the test where an operation answered nothing (`after`).
String after(String body, List<Edit>? edits) {
  expect(edits, isNotNull);
  return applyEdits(body, edits!);
}

void expectNone(NoteComments read) {
  expect(read.fence, isNull);
  expect(read.threads, isEmpty);
  expect(read.anchors, isEmpty);
  expect(read.strays, isEmpty);
}

void main() {
  group('reading the comments', () {
    test('reads the example in SHARED.md: a thread, its reply, its resolution and its anchor round a selection', () {
      final read = readComments(spec);
      expect(read.threads, hasLength(1));
      final thread = read.threads[0];
      expect(thread.id, 'c1');
      expect(thread.head, const Comment(by: 'matt', at: '2026-10-04T19:00:12Z', words: 'The venue needs confirming - the hall or the barn?', line: 6));
      expect(thread.replies, const [Comment(by: 'sam', at: '2026-10-04T19:05:40Z', words: 'The hall. Confirmed this morning.', line: 8)]);
      expect(thread.resolved, (by: 'sam', at: '2026-10-04T19:06:02Z', line: 10));
      expect([thread.from, thread.to], [6, 10]);
      expect(read.anchors, hasLength(1));
      final anchor = read.anchors[0];
      expect(spec.substring(anchor.from, anchor.to), '[^c1]');
      expect(spec.substring(anchor.wash!.from, anchor.wash!.to), '==venue==');
      expect(read.strays, isEmpty);
    });

    test('reads an anchor after the words with no wash, and words over several lines', () {
      const body = 'Call the caterer[^c2]\n\n```comments\nc2 me 2026-10-05T08:00:00Z\nWhich one?\nThe cheap one fell through.\n```';
      final read = readComments(body);
      expect(read.anchors[0].wash, isNull);
      expect(read.threads[0].head.words, 'Which one?\nThe cheap one fell through.');
      expect((read.fence!.open, read.fence!.close), (3, 7));
    });

    test('reads a note with no fence as no comments, and an anchor with no thread as no anchor', () {
      expectNone(readComments('Just words[^c1]'));
      const body = 'a[^c9] b[^c1]\n\n```comments\nc1 me 2026-10-05T08:00:00Z\nHi\n```\n';
      expect([for (final anchor in readComments(body).anchors) anchor.id], ['c1']);
    });

    test('keeps lines it does not understand as strays, and a malformed head as the words above it', () {
      final body = [
        '```comments',
        'a note to self before any thread',
        'c1 me 2026-10-05T08:00:00Z',
        'First.',
        'c2 me yesterday',
        '  sam 2026-10-05T08:01:00Z',
        '  Reply.',
        'unindented after a reply',
        '```',
      ].join('\n');
      final read = readComments(body);
      expect([for (final thread in read.threads) thread.id], ['c1']);
      // "c2 me yesterday" has no time it can read, so it is words - kept, never dropped.
      expect(read.threads[0].head.words, 'First.\nc2 me yesterday');
      expect(read.threads[0].replies[0].words, 'Reply.');
      expect(read.strays, [2, 8]);
    });

    test('reads a fence never closed to the end of the note', () {
      final read = readComments('Hi[^c1]\n\n```comments\nc1 me 2026-10-05T08:00:00Z\nStill typing');
      expect(read.fence, isNotNull);
      expect(read.fence!.close, isNull);
      expect(read.threads[0].head.words, 'Still typing');
    });

    test('takes the last comments fence, and no anchor inside another code block', () {
      final body = ['```', 'x[^c1]', '```', 'y[^c1]', '', '```comments', 'c1 me 2026-10-05T08:00:00Z', 'Real', '```'].join('\n');
      final read = readComments(body);
      expect(read.anchors, hasLength(1));
      expect(body.substring(read.anchors[0].from - 1, read.anchors[0].to), 'y[^c1]');
    });

    test('does not read a comments fence shown inside another block, as the Guide shows one', () {
      final body = ['A comment looks like this:', '', '````', 'The ==venue==[^c1]', '', '```comments', 'c1 me 2026-10-05T08:00:00Z', 'Hi', '```', '````', ''].join('\n');
      expectNone(readComments(body));
    });

    test('does not take a footnote’s definition for an anchor', () {
      const body = 'a[^c1]\n[^c1]: a footnote\n\n```comments\nc1 me 2026-10-05T08:00:00Z\nHi\n```';
      expect(readComments(body).anchors, hasLength(1));
    });
  });

  group('a new thread', () {
    test('washes a selection and anchors it, and makes the fence at the end with a blank line before it', () {
      const body = '# Plan\n\nBook the barn for Saturday.\n';
      final from = body.indexOf('the barn');
      final next = after(body, addThread(body, Target.span(from, from + 'the barn'.length), matt, 'Which barn?', 'c1'));
      expect(next, '# Plan\n\nBook ==the barn==[^c1] for Saturday.\n\n```comments\nc1 matt 2026-10-05T09:00:00Z\nWhich barn?\n```\n');
      expect(readComments(next).anchors[0].wash, isNotNull);
    });

    test('anchors after a line’s words, its trailing spaces aside', () {
      const body = '# Plan  \nwords';
      expect(after(body, addThread(body, const Target.line(1), matt, 'Rename it?', 'c1')), '# Plan[^c1]  \nwords\n\n```comments\nc1 matt 2026-10-05T09:00:00Z\nRename it?\n```\n');
    });

    test('adds a second thread at the end of the fence that is there', () {
      final next = after(spec, addThread(spec, const Target.line(1), sam, 'Good title.', 'c2'));
      final read = readComments(next);
      expect([for (final thread in read.threads) thread.id], ['c1', 'c2']);
      expect(next, endsWith('  resolved sam 2026-10-04T19:06:02Z\nc2 sam 2026-10-05T09:10:00Z\nGood title.\n```\n'));
    });

    test('anchors a selection over several lines after its last line’s words, with no wash', () {
      const body = 'one\ntwo\nthree';
      final next = after(body, addThread(body, const Target.span(1, 6), matt, 'Hm', 'c1'));
      expect(next, startsWith('one\ntwo[^c1]\nthree'));
    });

    test('trims the selection’s spaces, and takes a highlight inside or whole as the wash', () {
      const body = 'a ==big words== here';
      // Inside the highlight: anchored after its closing marks, no highlight opened inside another.
      final inside = body.indexOf('words');
      expect(after(body, addThread(body, Target.span(inside, inside + 5), matt, 'x', 'c1')).split('\n')[0], 'a ==big words==[^c1] here');
      // The highlight picked whole, with a space either side.
      final whole = body.indexOf(' ==big');
      expect(after(body, addThread(body, Target.span(whole, whole + ' ==big words== '.length), matt, 'x', 'c1')).split('\n')[0], 'a ==big words==[^c1] here');
    });

    test('writes words over several lines, drops empty ones, and escapes a line that would read as a head', () {
      const body = 'x';
      final next = after(body, addThread(body, const Target.line(1), matt, 'First line\n\n  c9 sam 2026-10-04T19:00:00Z\n```\n\\back', 'c1'));
      expect(next, contains('c1 matt 2026-10-05T09:00:00Z\nFirst line\n\\c9 sam 2026-10-04T19:00:00Z\n\\```\n\\\\back\n```'));
      expect(readComments(next).threads, hasLength(1));
      expect(readComments(next).threads[0].head.words, 'First line\nc9 sam 2026-10-04T19:00:00Z\n```\n\\back');
      // What the page's own helper gets wrong and the editor's dispatch does not: on a note's last line, with no
      // fence yet, the anchor stays with the words and the fence comes after it.
      expect(next, startsWith('x[^c1]\n\n```comments\n'));
      expect(readComments(next).anchors, hasLength(1));
    });

    test('says no to empty words, a line past the note, and a place inside the fence', () {
      expect(addThread('x', const Target.line(1), matt, '  \n '), isNull);
      expect(addThread('x', const Target.line(4), matt, 'hi'), isNull);
      expect(addThread('x', const Target.line(0), matt, 'hi'), isNull);
      final inFence = spec.indexOf('The venue needs');
      expect(addThread(spec, Target.span(inFence, inFence + 3), matt, 'hi'), isNull);
    });

    test('writes a handle with no space in it, so the head reads back', () {
      final next = after('x', addThread('x', const Target.line(1), Stamp(by: 'two words', at: matt.at), 'hi', 'c1'));
      expect(readComments(next).threads[0].head.by, 'two-words');
    });
  });

  group('replies, resolving and reopening', () {
    const open = 'x[^c1]\n\n```comments\nc1 matt 2026-10-05T09:00:00Z\nWhich?\n```\n';

    test('puts a reply under the thread’s last comment, indented two', () {
      final next = after(open, addReply(open, 'c1', sam, 'This one.\nAnd that.'));
      expect(next, 'x[^c1]\n\n```comments\nc1 matt 2026-10-05T09:00:00Z\nWhich?\n  sam 2026-10-05T09:10:00Z\n  This one.\n  And that.\n```\n');
      expect(readComments(next).threads[0].replies[0].words, 'This one.\nAnd that.');
    });

    test('escapes a reply’s line that would read as a reply’s head', () {
      final next = after(open, addReply(open, 'c1', sam, 'matt 2026-10-05T09:00:00Z'));
      final thread = readComments(next).threads[0];
      expect(thread.replies, hasLength(1));
      expect(thread.replies[0].words, 'matt 2026-10-05T09:00:00Z');
    });

    test('resolves, reopens, and puts a reply to a closed thread before its resolution', () {
      final resolved = after(open, resolveThread(open, 'c1', sam));
      expect(resolved, contains('Which?\n  resolved sam 2026-10-05T09:10:00Z\n```'));
      expect(readComments(resolved).threads[0].resolved?.by, 'sam');
      expect(resolveThread(resolved, 'c1', sam), isNull);
      final replied = after(resolved, addReply(resolved, 'c1', matt, 'Late word'));
      expect(replied, contains('Which?\n  matt 2026-10-05T09:00:00Z\n  Late word\n  resolved sam'));
      expect(after(resolved, reopenThread(resolved, 'c1')), open);
      expect(reopenThread(open, 'c1'), isNull);
    });

    test('answers nothing for a thread that is not there', () {
      expect(addReply(open, 'c7', sam, 'hi'), isNull);
      expect(resolveThread(open, 'c7', sam), isNull);
      expect(deleteThread(open, 'c7'), isNull);
    });
  });

  group('deleting a thread', () {
    test('takes the last thread, its anchor and its wash, and the fence with it, back to the words as they were', () {
      const body = '# Plan\n\nBook the barn for Saturday.\n';
      final from = body.indexOf('the barn');
      final commented = after(body, addThread(body, Target.span(from, from + 8), matt, 'Which barn?', 'c1'));
      expect(after(commented, deleteThread(commented, 'c1')), body);
      final onLine = after(body, addThread(body, const Target.line(1), matt, 'Name?', 'c1'));
      expect(after(onLine, deleteThread(onLine, 'c1')), body);
    });

    test('takes one thread of two, leaving the other and the fence', () {
      final two = after(spec, addThread(spec, const Target.line(1), sam, 'Good title.', 'c2'));
      final next = after(two, deleteThread(two, 'c1'));
      expect(next, '# Barn dance[^c2]\n\nThe venue is booked.\n\n```comments\nc2 sam 2026-10-05T09:10:00Z\nGood title.\n```\n');
      expect(after(next, deleteThread(next, 'c2')), '# Barn dance\n\nThe venue is booked.\n');
    });

    test('keeps the fence while lines that are no thread’s are in it', () {
      const body = 'x[^c1]\n\n```comments\nmy own note\nc1 me 2026-10-05T08:00:00Z\nHi\n```';
      expect(after(body, deleteThread(body, 'c1')), 'x\n\n```comments\nmy own note\n```');
    });
  });

  group('ids, counts and labels', () {
    test('makes a fresh id this note has not used, for a thread, an anchor or a footnote', () {
      const tails = ['0', '0', '0', '0', '1', '1', '1', '1'];
      var i = 0;
      double random() => int.parse(tails[i++ % tails.length], radix: 36) / 36;
      expect(freshId('nothing', random), 'c0000');
      i = 0;
      expect(freshId('x[^c0000]', random), 'c1111');
      i = 0;
      expect(freshId('```comments\nc0000 me 2026-10-05T08:00:00Z\n```', random), 'c1111');
      expect(freshId(''), matches(RegExp(r'^c[0-9a-z]{4}$')));
    });

    test('round-trips an unchanged note exactly, by never writing what it read', () {
      for (final body in [spec, '', 'x', 'a[^c1]\n```comments\nweird\n  c1\n```']) {
        expect(applyEdits(body, const []), body);
      }
    });

    test('counts threads and the open ones, and says them', () {
      final two = after(spec, addThread(spec, const Target.line(1), sam, 'Good title.', 'c2'));
      final threads = readComments(two).threads;
      expect(threadCounts(threads), (threads: 2, open: 1));
      expect(countWords(threads), '2 comments, 1 open');
      expect(countWords(readComments(spec).threads), '1 comment, resolved');
      expect(countWords(const []), isNull);
    });

    test('counts each person’s comments and replies from parsed threads', () {
      final two = after(spec, addThread(spec, const Target.line(1), sam, 'Good title.', 'c2'));
      final counts = countsBy(readComments(two).threads);
      expect(counts['matt'], (comments: 1, replies: 0));
      expect(counts['sam'], (comments: 1, replies: 1));
    });

    test('stamps the time to the second, in UTC', () {
      expect(stampNow(DateTime.utc(2026, 10, 5, 9, 1, 2, 345)), '2026-10-05T09:01:02Z');
      // Whatever zone the device keeps its clock in.
      expect(stampNow(DateTime.utc(2026, 10, 5, 9, 1, 2, 345).toLocal()), '2026-10-05T09:01:02Z');
    });

    test('keeps a title commented on called what it was', () {
      expect(withoutAnchors('Plan[^c1] and ==this==[^c22]'), 'Plan and ==this==');
      expect(noteTitle('# Plan[^c1]\n\nwords'), 'Plan');
      expect(threadOf(readComments(spec), 'c1')?.id, 'c1');
    });
  });
}
