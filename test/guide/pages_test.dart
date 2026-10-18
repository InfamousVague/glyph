import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/guide/pages.dart';

/// Which pages the walkthrough has (GHST-103): the mode page after the theme, and the model page gone for someone
/// who chose Simple, as for an iPhone.
void main() {
  test('asks simple or advanced after the theme, and the model after that', () {
    expect(walkthroughPagesFor(ios: false, prefs: const Preferences()), [GuidePage.welcome, GuidePage.theme, GuidePage.mode, GuidePage.model, GuidePage.start]);
  });

  test('drops the model page once Simple is chosen, as an iPhone always does', () {
    const simple = Preferences(experience: 'simple', experienceChosen: true);
    expect(walkthroughPagesFor(ios: false, prefs: simple), [GuidePage.welcome, GuidePage.theme, GuidePage.mode, GuidePage.start]);
    expect(walkthroughPagesFor(ios: true, prefs: const Preferences()), [GuidePage.welcome, GuidePage.theme, GuidePage.mode, GuidePage.start]);
  });

  test('keeps the model page for Advanced, chosen or not yet', () {
    const advanced = Preferences(experience: 'advanced', experienceChosen: true);
    expect(walkthroughPagesFor(ios: false, prefs: advanced), GuidePage.values);
    // Simple is lit on the page before anything is tapped, but the count does not shrink until it is chosen.
    expect(walkthroughPagesFor(ios: false, prefs: const Preferences(experience: 'simple')), GuidePage.values);
  });
}
