import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/ai/blanks.dart' show blankHooks, editorBlanks;
import 'package:ghost_md/editor/state/state.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/root/iphone_wiring.dart';

/// The answers the real iPhone app's page gives where no other platform's does (lib/root/iphone_wiring.dart): each
/// is the page's own rule, and each is nothing at all anywhere but an iPhone.
void main() {
  test('About is told the App Store updates the app, on an iPhone alone', () {
    final told = appStoreUpdates(platform: TargetPlatform.iOS);
    expect(told, isNotNull);
    expect(told!.store, 'appstore');
    // Nothing to check and nothing to install: the store does that.
    expect(told.onCheck, isNull);
    expect(told.onInstall, isNull);
    expect(appStoreUpdates(platform: TargetPlatform.android), isNull);
    expect(appStoreUpdates(platform: TargetPlatform.macOS), isNull);
  });

  test('the + beside a line offers no picture on an iPhone', () {
    expect(plusOffersPicture(platform: TargetPlatform.iOS), isFalse);
    expect(plusOffersPicture(platform: TargetPlatform.android), isTrue);
    expect(plusOffersPicture(platform: TargetPlatform.macOS), isTrue);
  });

  test('no link’s preview is fetched on an iPhone', () {
    expect(iPhoneLinkPreviews(platform: TargetPlatform.iOS), isFalse);
    expect(iPhoneLinkPreviews(platform: TargetPlatform.android), isTrue);
  });

  test('the AI’s rows say why not, in the page’s words', () {
    expect(aiNotOnIPhone, 'The AI is not on iOS yet.');
    final said = <String>[];
    final rows = iPhoneAiRows(said.add, platform: TargetPlatform.iOS)!;
    final plain = EditorView(state: EditorState.create(doc: 'A note with nothing to fill.'));
    final blank = EditorView(state: EditorState.create(doc: 'The capital of France is {?what is the capital of France}.'));
    rows(plain, 'summarize');
    rows(plain, 'ask', 'make it shorter');
    // Fill the blanks says there are none before the model is asked for, as the page's does.
    rows(plain, 'fill');
    rows(blank, 'fill');
    expect(said, ['The AI is not on iOS yet.', 'The AI is not on iOS yet.', 'No blanks for the model in this note.', 'The AI is not on iOS yet.']);
    // Anywhere else a desk with no AI draws no rows.
    expect(iPhoneAiRows(said.add, platform: TargetPlatform.android), isNull);
    expect(iPhoneAiRows(said.add, platform: TargetPlatform.macOS), isNull);
  });

  test('a note’s blanks are drawn on an iPhone with no Fill, and nowhere else are they this file’s', () {
    final said = <String>[];
    final extensions = iPhoneBlanks(noteId: () => 'a-note', say: said.add, platform: TargetPlatform.iOS);
    expect(extensions, isNotEmpty);
    final state = EditorState.create(doc: 'The capital of France is {?what is the capital of France}.', extensions: Extension.list(extensions));
    // The blank is known to the editor, which is what draws it as one.
    expect(editorBlanks(state), hasLength(1));
    final hooks = state.facet(blankHooks)!;
    // No Fill pill; a press that would fill says why not.
    expect(hooks.canFill(), isFalse);
    hooks.fill(const []);
    expect(said, ['The AI is not on iOS yet.']);
    // A note with an AI brings its own blanks, and a note without one has none: nothing from here.
    expect(iPhoneBlanks(noteId: () => 'a-note', say: said.add, platform: TargetPlatform.android), isEmpty);
    expect(iPhoneBlanks(noteId: () => 'a-note', say: said.add, platform: TargetPlatform.macOS), isEmpty);
  });
}
