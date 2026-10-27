import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/guide/pages.dart';

/// Which pages the walkthrough has: the tour of the app (2026-10-27), then simple or advanced (GHST-103), the model
/// page gone for someone who chose Simple, and an iPhone shown only what it has.
void main() {
  test('tours the app, asks simple or advanced, and the model after that', () {
    expect(walkthroughPagesFor(ios: false, prefs: const Preferences()), [
      GuidePage.welcome, GuidePage.speak, GuidePage.meetings, GuidePage.ai, GuidePage.sync, GuidePage.market, GuidePage.mode, GuidePage.model, GuidePage.start, //
    ]);
  });

  test('drops the model page once Simple is chosen', () {
    const simple = Preferences(experience: 'simple', experienceChosen: true);
    expect(walkthroughPagesFor(ios: false, prefs: simple), [
      GuidePage.welcome, GuidePage.speak, GuidePage.meetings, GuidePage.ai, GuidePage.sync, GuidePage.market, GuidePage.mode, GuidePage.start, //
    ]);
  });

  test('on an iPhone, which records nothing and runs no model, leaves out speaking, the AI and the model', () {
    expect(walkthroughPagesFor(ios: true, prefs: const Preferences()), [GuidePage.welcome, GuidePage.meetings, GuidePage.sync, GuidePage.market, GuidePage.mode, GuidePage.start]);
  });

  test('keeps the model page for Advanced, chosen or not yet', () {
    const advanced = Preferences(experience: 'advanced', experienceChosen: true);
    expect(walkthroughPagesFor(ios: false, prefs: advanced), GuidePage.values);
    // Simple is lit on the page before anything is tapped, but the count does not shrink until it is chosen.
    expect(walkthroughPagesFor(ios: false, prefs: const Preferences(experience: 'simple')), GuidePage.values);
  });
}
