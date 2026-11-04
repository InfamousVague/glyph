# Store disclosures for the anonymous usage stats (2.4.19)

What changes in App Store Connect and the Play Console now that the app sends anonymous usage stats to PostHog
(docs/ANALYTICS.md). Everything else in the existing answers (tauri/docs/store/APP_STORE.md,
tauri/docs/store/play/forms.md) stands. Drafted 2026-11-04; to be entered by hand with the 2.4.19 submissions.

What is collected, for both forms: events about how the app is used (screens, features, plugins switched on, jobs
finished or failed, durations and counts as buckets), uncaught errors counted by their type name alone (no message,
no stack), and a random install ID made on the device. Not linked to the account or to the person; no person
profiles; IP discarded; no GeoIP; not shared with anyone for their own use (PostHog is a processor); encrypted in
transit (HTTPS); on by default, and the person can turn it off (Settings › Privacy › Anonymous usage stats, or in the
walkthrough), and Local only sends none.

## Apple: App Privacy (iPhone and the Mac App Store, one set)

Add these four data types. Each: **Collected: yes. Linked to the user: No. Used for tracking: No. Purpose:
Analytics** (only Analytics; not App Functionality, not Product Personalization).

| Category › Type | Why |
|---|---|
| Usage Data › **Product Interaction** | `app_opened`, `screen_viewed`, `note_created`, `plugin_enabled`, … (docs/ANALYTICS.md, "The events") |
| Diagnostics › **Crash Data** | `error_caught`: an uncaught error's type name, once per type per run |
| Diagnostics › **Performance Data** | `app_opened.start` (cold start bucket), jobs' `took` buckets |
| Identifiers › **Device ID** | the random install ID (not IDFA, not IDFV) |

The answers already given (User ID, Other User Content, Photos or Videos, Audio Data, each linked, App Functionality)
are unchanged.

**The privacy manifest.** `ios/Runner/PrivacyInfo.xcprivacy` and `macos/Runner/PrivacyInfo.xcprivacy` (the Mac App
Store build's) now declare the same four, each `NSPrivacyCollectedDataTypeLinked` false,
`NSPrivacyCollectedDataTypeTracking` false, purpose `NSPrivacyCollectedDataTypePurposeAnalytics`:
`NSPrivacyCollectedDataTypeProductInteraction`, `NSPrivacyCollectedDataTypeCrashData`,
`NSPrivacyCollectedDataTypePerformanceData`, `NSPrivacyCollectedDataTypeDeviceID`. `NSPrivacyTracking` stays false
and `NSPrivacyTrackingDomains` empty: nothing is used for tracking, so us.i.posthog.com is not a tracking domain. No
new required-reason API: the client is Dart over the app's own HTTP, and the switch, ID and queue are in the
UserDefaults the manifest already declares (CA92.1). The two files stay identical below their comments
(test/core/mac_store_test.dart).

## Google Play: Data safety

The opening questions: *Does your app collect or share any of the required user data types?* Yes (as before). *Is all
of the user data collected by your app encrypted in transit?* Yes. *Do you provide a way for users to request that
their data is deleted?* Yes (as before; the stats are deleted by turning them off, which deletes the ID, and the
project keeps no person to delete).

Add, or change, these rows:

| Data type | Collected | Shared | Processed ephemerally | Required or optional | Purpose |
|---|---|---|---|---|---|
| App activity › **App interactions** | Yes | No | No | Optional (the user can turn it off) | Analytics |
| App info and performance › **Crash logs** | Yes | No | No | Optional | Analytics |
| App info and performance › **Diagnostics** | Yes | No | No | Optional | Analytics |
| Device or other IDs | Yes | No | No | Optional | Analytics, **in addition to** the existing Account management row (the device's public key, with an account) |

And the last row of forms.md's table (“Location, Name, Email address, … App activity, Web browsing, Crash logs,
Diagnostics, the advertising id | No | … Not collected. There is no analytics, crash reporting or advertising SDK.”)
becomes: “Location, Name, Email address, Financial info, Health and fitness, Calendar, Contacts, Web browsing, the
advertising id | No | Not collected. There is no advertising SDK; the anonymous usage stats are the rows above.”

`tauri/docs/store/PLAY_STORE.md` line 75 (“Anything else (contacts, analytics, crash logs) | No”) becomes “Anything
else (contacts, the advertising id) | No”, with the four rows above added to its table. Neither file was changed:
they are the form's record, and change when the form is sent.

## The listing copy

Every claim of "no analytics" in the store copy, and what it says now:

| File | Was | Now |
|---|---|---|
| `tauri/docs/store/play/copy/listing.md` (full description) | “No ads, no analytics, no tracking.” | “No ads, no tracking; usage stats are anonymous and can be turned off.” (**changed**) |
| `tauri/docs/store/play/FEATURES.md` | “No analytics, no crash reporting, no ads, no advertising id.” | “Anonymous usage stats only (features used, errors by type, never content), which can be turned off; no ads, no advertising id.” (**changed**) |
| `tauri/docs/store/play/forms.md` (Data safety record) | “There is no analytics, crash reporting or advertising SDK.” | as above (to change when the form is sent) |
| `tauri/docs/store/PLAY_STORE.md` (Data safety plan) | “Anything else (contacts, analytics, crash logs) \| No” | as above (to change when the form is sent) |
| `tauri/docs/store/play/copy/full-2026-10-05.txt` | (what was pasted on 2026-10-05; not a no-analytics claim, and a dated record) | unchanged |

The App Store copy (`tauri/docs/store/apple/listing.md`) makes no "no analytics" claim; its "No tracking." in
APP_STORE.md is still true (Apple's tracking means linking with other companies' data, and nothing is). One sentence
in both stores' descriptions is worth softening, though it does not name analytics: “Without one, your notes stay on
your iPhone and nothing of yours is on any server.” Suggested: “Without one, your notes stay on your iPhone and none
of them is on any server.” (iPhone, Mac, and the Play listing's “without one nothing of yours is on any server” →
“without one none of your notes is on any server”). Not changed.

**The Play full description was already over 4,000 characters on main** (4,059 by `copy/check.mjs`); with the
sentence above it is 4,094. Something else has to be cut before it is pasted.

### Description, a sentence to add (both stores)

> Ghost.md sends anonymous usage stats, counts of which features are used, never your notes or who you are. Turn them
> off in Settings › Privacy.

(Optional: the changed sentence above already says it on Play.)

### What's New, 2.4.19

App Store (4,000) and Play release notes (500):

> Anonymous usage stats: counts of which features are used, never your notes or who you are, to help make Ghost.md
> better. They're on by default, and you can turn them off in Settings › Privacy or on the walkthrough's privacy page.
> Also: choose Lovart's image model in its settings.

(218 characters; drop the last sentence if 2.4.18 already shipped with its own notes.)

## Terms of service

There is no terms page: landing/ has privacy.html and delete-account.html, and the app links only the privacy policy
(lib/settings/privacy_card.dart `privacyUrl`). Nothing to update.
