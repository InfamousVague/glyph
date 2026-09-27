# What Google Play asks for, and what Ghost.md answers

The map of the Play Console's requirements for Ghost.md, written 2026-09-27 from the Play Console help pages as they
read that day and from what is known of the Console. Each rule says how sure it is: **sure** means the help page says
it in those words; **check** means it is how the Console has worked, and the field itself will confirm the number
when it is opened. The Console's own text wins wherever the two differ.

The companion files: [LISTING.md](LISTING.md) is the copy, [FORMS.md](FORMS.md) the answers to the declarations,
[SCREENSHOTS.md](SCREENSHOTS.md) the pictures and how they were made, and [CHECKLIST.md](CHECKLIST.md) the order to
do it in.

## The listing's text

| Field | Limit | Sure? | Ghost.md's answer |
| --- | --- | --- | --- |
| App name | 30 characters | check (the help page for graphic assets does not restate it; the Console field counts it) | `Ghost.md` |
| Short description | 80 characters | sure | LISTING.md |
| Full description | 4,000 characters | check (the Console field counts it) | LISTING.md |
| Release notes ("What's new") | 500 characters per language | check | LISTING.md |
| Default language | Chosen once, translations optional | sure | English (United Kingdom), so the spelling in the copy is the store's own |

The metadata policy, sure: no unattributed or anonymous testimonials, no ranking or performance claims (a
number one, a superlative), no "free", "new" or "sale" in the name, no emoji or emoticons in the name, no repeated or irrelevant keywords,
and no text that is all capitals unless it is the brand. The full description may mention other platforms (a Mac app
and a web version); the store's one rule is that nothing in it may mislead about what the Android app does.

## The graphics

| Asset | What Play asks for | Sure? | The file in the pack |
| --- | --- | --- | --- |
| App icon | 512 × 512, 32-bit PNG with alpha, at most 1,024 KB. Play draws its own rounded mask over it, so the picture is a full square with no rounding of its own | sure | `app-icon.png`, the Tauri set's 512, the mascot on lined paper, 462 KB, every pixel opaque |
| Feature graphic | 1,024 × 500, JPEG or 24-bit PNG with no alpha | sure (the help page); the Console accepts a PNG that has an alpha channel and flattens it, check | `feature-graphic.png`, written without an alpha channel |
| Phone screenshots | 2 to 8. JPEG or 24-bit PNG, no alpha. Each side between 320 and 3,840 px. The long side no more than twice the short side, which is where "16:9 to 9:16" comes from | sure | `phone-screenshot-01.png` to `-08.png`, each 1,242 × 2,208 (9:16) |
| 7-inch tablet screenshots | Up to 8, the same rules as the phone's | sure on the rules; check the count | `tablet-7-inch-screenshot-01.png` to `-03.png`, each 1,080 × 1,920 |
| 10-inch tablet screenshots | Up to 8, the same rules, and each side between 1,080 and 7,680 px | check (the 1,080 floor is the Console's wording) | `tablet-10-inch-screenshot-01.png` to `-03.png`, each 2,560 × 1,440 |
| Preview video | A YouTube URL, optional. Only the first 30 seconds autoplay | sure | None |
| Chromebook, Android TV, Wear OS | Only for apps that declare those form factors | sure | None: the manifest lost its TV entries (DESIGN §113) |

For the store to consider the app for its featured placements, sure from the same help page: at least four
screenshots, at least 1,080 px on the short side, 16:9 or 9:16, and no device frame or heavy text on them. The pack
meets all four for the phone.

## Text and claims in screenshots

What the metadata and store listing policies say, sure: a screenshot shows the app as it runs, and nothing on it
may mislead about what the app does. What the store listing quality guidance adds, check: keep any words on a
screenshot short and in the language of the listing, put the app's own screen in front, and avoid text that is
hard to read at the size a phone shows it. Each screenshot in the pack is a real screen of the build over an
invented library, with one short caption above it and nothing else drawn on it. The captions say what the screen
shows and nothing the app does not do.

The one screen that names something not built: none. The meetings feature of 1.9.0 has no screenshot because it
does not exist yet. The listing text describes it only in the paragraph marked for 1.9.0 in LISTING.md.

## Store settings

| Setting | Sure? | Answer |
| --- | --- | --- |
| App or game | sure | App |
| Category | sure | Productivity |
| Tags | check (up to five, from the Console's list) | Notes, Voice, Markdown if offered; otherwise Productivity's nearest |
| Contact email (shown on the listing) | sure, required | infamousvaguerat@gmail.com, the address on the privacy page |
| Contact phone and website | sure, optional | Website https://ghostmarkdown.com; no phone |
| External marketing | sure, optional | Off |

## Policy declarations (App content)

| Declaration | What it asks | Sure? | Ghost.md's answer |
| --- | --- | --- | --- |
| Privacy policy | A URL, required of every app | sure | https://ghostmarkdown.com/privacy.html |
| Ads | Whether the app shows ads | sure | No |
| App access | Whether any part needs a login, and if so, instructions or a test account | sure | See FORMS.md: everything works without an account; sync, live typing and sharing need one, and a test account is offered |
| Content rating | The IARC questionnaire | sure | See FORMS.md: a utility, no user interaction that reaches other people, rated for everyone |
| Target audience and content | The age groups the app is for, and whether it appeals to children | sure | 13 and over; not designed for children |
| News apps | Whether the app is a news app | sure | No |
| COVID-19 contact tracing and status | Whether the app is one | sure | No |
| Data safety | What is collected, shared, and how it is kept | sure | See FORMS.md |
| Government apps | Whether the app is made for or by a government | sure | No |
| Financial features | Whether the app offers loans, banking or the like | sure | No financial features |
| Health apps | Whether the app is a health app | sure | No |
| Advertising ID | Whether the app uses the advertising id (asked because targetSdk is 33 or above) | sure | No. The manifest has no `AD_ID` permission and nothing reads the id |
| Photo and video permissions | Whether the app reads the photo library broadly | sure | Not asked: the app has no `READ_MEDIA_IMAGES` or `READ_MEDIA_VIDEO`; pictures come through the picker |
| Foreground service permissions | For each foreground service type: what it does, what happens if the system stops it, and a link to a video showing the feature | sure for apps targeting Android 14 or later | Not needed by 1.8.0, which has no foreground service. Needed by 1.9.0 if a meeting records with the screen off through a foreground service of type `microphone`: see FORMS.md |
| Account deletion | An in-app path and a web page where a person can ask for the account and its data to be deleted, declared in the Data safety form's data deletion questions | sure | In the app: Settings › Account › Delete account. On the web: https://ghostmarkdown.com/delete-account.html |

## Data safety, in Play's words

The definitions the form uses, sure, quoted from the help page:

- Collection is transmitting data off the device. "User data that is sent off device, but that is unreadable by
  you or anyone other than the sender and recipient as a result of end-to-end encryption does not need to be
  disclosed."
- Data "that is only processed locally on the user's device and not sent off device does not need to be disclosed."
- Ephemeral processing, "accessed and used while the data is only stored in memory and retained for no longer than
  necessary to service the specific request in real-time", is declared in the form but not shown on the listing.
- Sharing is transferring data to a third party. A transfer the person starts themselves, to a service they
  chose, is not sharing.

So Ghost.md's notes, recordings and pictures, sealed on the device before they sync, are not collected in the
form's sense, and the answers in FORMS.md say so. The handle and each device's key are collected, for account
management, and not shared.

## Testing and release

| Rule | Sure? | What it means here |
| --- | --- | --- |
| A personal developer account made after 13 November 2023 must run a closed test with at least 12 testers opted in continuously for 14 days before it can apply for production | sure | The plan's step 4. An organisation account is not held to it |
| The production access application is a form in three parts: the closed test, the app, and readiness | sure | Answered from the closed test |
| Play refuses an upload signed with a debug certificate | sure | The upload key is Matt's step 2 |
| Play App Signing | sure, required for new apps | Enrol with a Google-generated app signing key; the upload key stays with Matt |
| A new app or an update must target the API level Play sets, which rises each August: 36 from 31 August 2026 | sure that the floor rises every August; check the number the Console shows | The build targets 36 |
| 16 KB page support for native libraries | sure, from 1 November 2025 for new apps and updates targeting Android 15 or later | Done: DESIGN §113 |
| The upload is an Android App Bundle | sure | `GLYPH_STORE=play npm run android:build -- --aab --target aarch64` |

## Not asked, and why

- **Sign in with Google, or any social login rule:** Ghost.md's accounts are its own; Notion, GitHub and Claude are
  connections, not ways to sign in.
- **In-app purchases and subscriptions:** nothing is paid.
- **Families policy:** the app is not for children and says so.
- **Permissions declaration for sensitive permissions:** `RECORD_AUDIO` is a runtime permission, not one of the ones
  the Console asks a declaration for. The digital assistant role and the voice interaction service can draw a
  reviewer's question; the review notes in FORMS.md say what they are for.
