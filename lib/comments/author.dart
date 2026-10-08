/// Who a comment is by. A port of `src/app/core/comments/author.ts`.
///
/// The account's handle, or `me` on a device with no account, as a version's author is
/// (lib/core/versions_record.dart). Tracked per person (docs/SHARED.md, S8: "make sure replies and comments are
/// tracked per user in the organization"): every line of the fence names its author, so a member's comments can be
/// counted and an organization's log can say who commented.
///
/// What differs: the page reads the account as a module; here it is handed in ([AccountSource],
/// lib/account/session.dart), null for a build with no account at all.
library;

import '../account/session.dart';
import 'format.dart';

/// The handle a comment written here is by (`commentHandle`).
String commentHandle(AccountSource? account) => account?.session?.handle ?? 'me';

/// This person, now: what a new comment, a reply or a resolution is stamped with (`stampHere`).
Stamp stampHere(AccountSource? account, [DateTime? now]) => Stamp(by: commentHandle(account), at: stampNow(now));
