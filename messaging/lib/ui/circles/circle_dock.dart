/// The dock while a circle is open (Matt, 2026-11-17: "add a 'home' button on the dock while on the space and
/// transform all the icons inside the dock to be related to the circle instead of the whole app"): Home first, back
/// to the conversations with the circle closed, then the circle's own places. The frame (lib/ui/shell.dart) swaps
/// these in for the app's own rings while a circle is in the list's place, on a phone and a computer alike, and
/// answers them (AppShellState's circle dock). It wears the circle's face at its head and the circle's hue on the
/// ring shown, so it reads as the circle's at a glance and not as the app's own pill with other icons (Dial-Up's
/// taskbar stays as it is).
library;

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../circles/circles.dart';
import '../nav_bar.dart';

/// Lucide's house (lucide-static 1.70.0, ISC licence), which Ghost.md's set has not: Home on the circle's dock.
const houseIcon = LucideIcon('house', [
  'M15 21v-8a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v8',
  'M3 10a2 2 0 0 1 .709-1.528l7-5.999a2 2 0 0 1 2.582 0l7 5.999A2 2 0 0 1 21 10v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z',
], [1]);

/// The rings' ids, which the frame answers.
abstract final class CircleDock {
  static const home = 'home';
  static const spaces = 'circle-spaces';
  static const members = 'circle-members';
  static const newSpace = 'circle-new';
  static const settings = 'circle-settings';
  static const invite = 'circle-invite';

  /// The rings for [c]: Home, its spaces, its members (the drawer), a new space where this device may add one, and the
  /// app's Settings. Read by the name the circle's own menu gives them.
  static List<NavItem> items(Circle c, {required bool canEdit}) => [
        const NavItem(id: home, icon: houseIcon, label: 'Home'),
        const NavItem(id: spaces, icon: Lucide.layoutList, label: 'Spaces'),
        const NavItem(id: members, icon: Lucide.users, label: 'Members'),
        // In the room the circle's face had at the dock's head (Matt, 2026-11-17: "replace the circle icon with the home page
        // ... find some other icon to fill the missing space").
        const NavItem(id: invite, icon: Lucide.userPlus, label: 'Invite people', short: 'Invite'),
        // "New" on Dial-Up's taskbar, where "New space" was drawn smaller than the other words to fit.
        if (canEdit) const NavItem(id: newSpace, icon: Lucide.plus, label: 'New space', short: 'New'),
        // The app's Settings (Matt, 2026-11-18); the circle's own are in its menu, under its name.
        const NavItem(id: settings, icon: Lucide.settings, label: 'Settings'),
      ];
}
