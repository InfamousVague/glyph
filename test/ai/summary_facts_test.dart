import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summary_keep.dart';
import 'package:ghost_md/core/front_matter.dart' show frontMatterValue;
import 'package:ghost_md/core/stored.dart';

/// The summary's facts written into the note's own front matter (lib/ai/summary_keep.dart `withSummaryFacts`;
/// docs/MARKDOWN_FIRST.md §5, gap 13), and read back where the device's record is gone: the section named by its
/// hash rather than its text, since the text is in the note.
void main() {
  const section = '## Summary\nWhat the call settled.\n\n- Launch is in March.\n\n- [ ] Book the venue.';
  const body = '# March launch\n\n$section\n\nThat is the March launch settled.';
  const kept = KeptSummary(text: section, model: 'qwen3.5-4b', at: 1793196000000, forMs: 4000);

  setUp(() => useStored(MemoryStored()));

  test('are four flat keys: the model, when, the tape’s length and the section’s hash', () {
    final written = withSummaryFacts(body, kept);
    expect(written, startsWith('---\nsummary-model: qwen3.5-4b\nsummary-at: 2026-10-28T14:00:00.000Z\nsummary-for-ms: 4000\nsummary-sha: '));
    expect(frontMatterValue(written, 'summary-sha'), summarySha(section));
    expect(frontMatterValue(written, 'summary-sha'), hasLength(64));
    expect(written, endsWith('---\n$body'));
    // Written again, the keys are replaced where they are; no tape, and a model unnamed, leave their keys off.
    expect(withSummaryFacts(written, kept), written);
    final bare = withSummaryFacts(body, const KeptSummary(text: section, model: '', at: 0, forMs: 0));
    expect(frontMatterValue(bare, 'summary-model'), isNull);
    expect(frontMatterValue(bare, 'summary-for-ms'), isNull);
    expect(withoutSummaryFacts(written), body);
  });

  test('read back as the record, with the section’s text where the note still holds it as written', () {
    final facts = summaryFactsOf(withSummaryFacts(body, kept));
    expect(facts, kept);
    expect(summaryFactsOf(body), isNull, reason: 'a note that says nothing');
    // The section edited: the note no longer holds what the app wrote, so there is no record to stand on.
    expect(summaryFactsOf(withSummaryFacts(body.replaceFirst('Launch is in March', 'Launch is in May'), kept)), isNull);
    // A list of the person's straight under the section is theirs: the section is still found, less those lines.
    final followed = withSummaryFacts('# March launch\n\n$section\n- [ ] My own to-do.\n- Another of mine.\n\nWords.', kept);
    expect(summaryFactsOf(followed)?.text, section);
    // The section gone altogether.
    expect(summaryFactsOf(withSummaryFacts('# March launch\n\nWords.', kept)), isNull);
  });

  test('the device’s record first, the note’s facts where it has none, for a release', () {
    final written = withSummaryFacts(body, kept);
    expect(readSummaryIn('n1', written), kept);
    expect(keptTextIn('n1', written), section);
    expect(summaryUnchangedIn('n1', written, section), isTrue);
    expect(summaryUnchangedIn('n1', written, '## Summary\nOther words.'), isFalse);
    expect(summaryBehindIn('n1', written, 9000), isTrue);
    expect(summaryBehindIn('n1', written, 4000), isFalse);
    // The device's record wins where it differs: it is what this device wrote last.
    const newer = KeptSummary(text: '## Summary\nNewer.', model: 'm', at: 2, forMs: 8000);
    keepSummary('n1', newer);
    expect(readSummaryIn('n1', written), newer);
    expect(readSummaryIn('n2', written), kept);
    expect(readSummaryIn('n2', body), isNull);
  });
}
