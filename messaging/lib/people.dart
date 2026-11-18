import 'account/account.dart';
import 'app_state.dart';
import 'circles/circles.dart';
import 'friends/buddies.dart';
import 'friends/friends.dart';
import 'friends/groups.dart';
import 'me/me.dart';
import 'net/net.dart';
import 'voice/channels.dart';

/// The app's own network, started where it runs here rather than on a paired phone: on the Android phone, on an
/// iPhone of its own, and on a computer with no phone linked (Matt, 2026-11-18: "a user can use the app without linking
/// the phone since some people may be joining just to enter circles or use telegram and signal but not SMS").
///
/// The routes to other phones (lib/net/net.dart), friends reached by them, groups, voice and the circles that ride
/// it, in that order; the accounts linked and the handles watched for (Settings › Me); and friends by username, heard
/// over the hub while any are kept or there is a username of one's own.
void startPeople(AppState app) {
  Net.instance.start(app).then((_) => Friends.instance.start(app)).then((_) => Groups.instance.start()).then((_) => Voice.instance.start(app)).then((_) => Circles.instance.start(app));
  // The accounts linked and the handles watched for (Settings › Me): spoken of to the relay server only once one has
  // been.
  Me.instance.start(AppMeStore(app), Net.instance, () => Net.instance.hub, needHub: (yes) => Net.instance.want('me', yes));
  // A Ghost account (lib/account; Matt, 2026-11-17: "We need to have a way to login to existing accounts"): where this
  // device is signed in to one, the relay is asked whether it still is.
  Account.instance.start(AppMeStore(app));
  // Friends by username (lib/friends/buddies.dart): heard over the hub, so it is dialled while any are kept, and from
  // the moment there is a username of your own, so a first friend request reaches you (Matt, 2026-11-16: "We need a
  // way to add friends on the network by username on the contacts page and see friend requests").
  void hearBuddies() {
    Net.instance.want('buddies', Buddies.instance.all.isNotEmpty || Me.instance.username != null);
    // Friends by username watched on the hub, so their faces say when they are on (lib/presence.dart).
    Net.instance.watchToo([for (final b in Buddies.instance.friends) b.id]);
  }

  Buddies.instance.start().then((_) {
    hearBuddies();
    Buddies.instance.addListener(hearBuddies);
    Me.instance.addListener(hearBuddies);
  });
}
