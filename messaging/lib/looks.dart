import 'art/app_icon.dart' show LucideIcon;
import 'art/lucide.g.dart';
import 'art/lucide_more.dart';
import 'app_state.dart';
import 'custom_theme.dart';

/// Looks for the whole app, chosen in Settings › Appearance (Matt, 2026-11-16: "spend some time making a few themes
/// for ghost, base one of them heavily on the old AOL chatrooms").
///
/// A look is a block of rules at the end of assets/css/app.css, keyed on `data-theme-preset`: its own twelve greys
/// (which ink.css copies onto the page's paper and ink), its accent and the colour of your own bubbles. The page is
/// told which with [ghostAttrs], so the app, the computer's app and every test that draws a screen stamp the same
/// attributes from the same choice. Ghost is the app's own and stamps no preset at all, so it is drawn exactly as it
/// was before there were looks.
///
/// [after] is a note for whoever works on it, never shown: the visible names stay the app's own (no other company's
/// name or marks, as the store listings ask).
enum Look {
  ghost('Ghost', '', 'The app\'s own: white paper and black ink, or the reverse, and your bubbles in the colour you choose.', Lucide.ghost, light: true, dark: true, keyboard: 'white'),
  mist('Mist', 'morning fog on pale water', 'A pale aqua page with deep teal ink, and deep teal bubbles of your own.', LucideMore.cloud, light: true, dark: false, keyboard: 'ghost'),
  lamplight('Lamplight', 'a reading lamp late at night: warm, low on blue', 'Warm parchment words on a brown-black page, and amber bubbles. For reading late.', Lucide.lightbulb, light: false, dark: true, keyboard: 'orange'),
  sharp('Sharp', 'high contrast, every grey above WCAG AA; its dark half is the true-black OLED choice', 'Black on white or white on black, lines you can see, and teal bubbles.', Lucide.square, light: true, dark: true, keyboard: 'ghost'),
  phosphor('Phosphor', 'a green-screen terminal (P1 phosphor)', 'Glowing green letters on a black screen, square corners, a terminal\'s type.', Lucide.terminal, light: false, dark: true, keyboard: 'green'),
  // Modelled on AOL's late-90s chat rooms, and Windows 95's High Contrast Black for After Hours; the names stay here
  // in a comment, out of the binary's strings.
  dialup(
    'Dial-Up',
    'a late-90s online service\'s chat room, and the era\'s high-contrast black scheme for After Hours; nothing of theirs is copied',
    'Silver windows, navy title bars and a white page where each line is a name and what they said.',
    Lucide.globe,
    light: true,
    dark: true,
    keyboard: 'blue',
    lightName: 'Daytime',
    darkName: 'After Hours',
    rounding: 'square',
    // Arimo, bundled (assets/fonts/ArimoVariable.ttf): Arial's measures without Arial, which may not be shipped.
    font: 'arimo',
  );

  const Look(
    this.label,
    this.after,
    this.description,
    this.icon, {
    required this.light,
    required this.dark,
    required this.keyboard,
    this.lightName = 'Light',
    this.darkName = 'Dark',
    this.rounding,
    this.font,
  });

  /// Its name, what it is modelled on (in code only), and a line on what it looks like.
  final String label;
  final String after;
  final String description;
  final LucideIcon icon;

  /// Which brightness it has: both, or only one, which it is then always drawn in whatever Theme says.
  final bool light, dark;

  /// The names of its two halves where it has both (Dial-Up's are Daytime and After Hours).
  final String lightName, darkName;

  /// The id among Ghost Keyboard's colours (lib/backgrounds.dart's `bubbleColors`) nearest this look's own bubbles,
  /// told to the keyboard while your bubbles are the look's ('theme'): the keyboard knows only those ids.
  final String keyboard;

  /// `data-rounding` (ink.css: square, soft, rounder), where the look stamps one.
  final String? rounding;

  /// `data-font`, where the look draws in a face of its own: one bundled in pubspec, hung with the emoji set in
  /// ghostTypography's fallbacks, and loaded by every test that draws a screen.
  final String? font;

  /// Offered in Settings › Appearance: every look is now; a look still being built can say false here.
  bool get ready => true;

  /// The choice the look is kept under, as its enum name.
  static const pref = 'look';

  /// The look chosen in [app]: Ghost where none was, or one no longer known.
  static Look of(AppState app) => named(app.choice(pref, 'ghost'));

  static Look named(String name) {
    for (final l in values) {
      if (l.name == name) return l;
    }
    return ghost;
  }

  /// The brightness it is always drawn in, or null where it follows Theme.
  String? get forced => light && dark ? null : (light ? 'light' : 'dark');

  /// The page's `data-` attributes for this look on [platform], with [theme] ('light', 'dark', or null to follow the
  /// phone) where the look has both halves.
  Map<String, String> attrs({required String platform, String? theme}) {
    final shown = forced ?? theme;
    return {
      'platform': platform,
      'theme': ?shown,
      if (this != ghost) 'theme-preset': name,
      'rounding': ?rounding,
      'font': ?font,
    };
  }
}

/// The page's `data-` attributes for [s]'s choices on [platform] ('mobile' or 'desktop'): the look, and the theme
/// where it is not the phone's own ('system'). The app (lib/main.dart, lib/desktop/main.dart) and every test that
/// draws a screen take them from here, so a choice in AppState is all a look needs.
///
/// A look of the person's own in use (lib/custom_theme.dart) stamps its own preset and brightness in place of the
/// look's; the Readable font (GMFB-41) stamps `data-font` over any look's own face.
Map<String, String> ghostAttrs(AppState s, String platform) {
  final custom = CustomTheme.used(s);
  final attrs = custom != null ? custom.attrs(platform: platform) : Look.of(s).attrs(platform: platform, theme: s.theme == 'system' ? null : s.theme);
  if (s.font == 'readable') attrs['font'] = 'readable';
  return attrs;
}
