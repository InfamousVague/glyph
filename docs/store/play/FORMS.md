# The Play Console's forms, answered

The answers for Play Console › Policy › App content, and for the store settings, as the Console asks them. Where a
form is a questionnaire, the question is given as the Console words it, then the answer, then why. Nothing here is a
secret: the test account for reviewers is a placeholder Matt fills in on the Console, never in this file.

## Store settings

| Field | Answer |
| --- | --- |
| App or game | App |
| Category | Productivity |
| Tags | Up to five from the Console's list. Take the nearest to notes, voice, Markdown and productivity |
| Email address | infamousvaguerat@gmail.com |
| Phone number | Leave blank |
| Website | https://ghostmarkdown.com |
| External marketing | Off |

## Privacy policy

`https://ghostmarkdown.com/privacy.html`. The page is live, says what the app does with data, names the contact
address, and is the page Settings › About › Privacy policy opens.

## App access

The Console asks: "Is any part of your app restricted based on login credentials, memberships, location, or other
forms of authentication?"

Answer: **All or some functionality is restricted.** Then add one instruction set:

- Name: `Optional account`
- Instructions, pasted:

```
Ghost.md works in full without an account: notes, voice notes, the on-device transcription, the AI runs, boards, books and canvases. An account is optional and adds sync between devices, live typing and read-only share links. To test those, sign in under Settings › Account with the handle and password below. Delete account is in the same place. The digital assistant role (Settings › Apps › Default apps › Digital assistant app) only makes the side key start a recording; it is not needed for any of the above.
```

- Username and password: a test account Matt makes on the live service for the review, with a throwaway handle
  and a password kept out of this repo. Play keeps them private to its reviewers.

Why not "All functionality is available without special access": that answer is true of the notes, and false of
sync, sharing and account deletion, which a reviewer may want to see. A test account costs nothing and removes the
question.

## Ads

"Does your app contain ads?" **No.** The app has no ad SDK, no ad code and no advertising id.

## Content rating

Start the questionnaire with the email address above. Category: **Utility, Productivity, Communication, or Other**.
Then, as the questionnaire asks:

| Question | Answer | Why |
| --- | --- | --- |
| Violence, sexual content, nudity, profanity, drugs, alcohol, tobacco, gambling, horror | No to each | A notes app with no content of its own beyond the sample note and the manual |
| Does the app allow users to interact or exchange content with other users? | No | Shared links are read-only pages anyone with the link can open. Nobody can write back, and there is no feed, chat or profile. If the questionnaire's wording counts a link a person can send as an exchange, answer Yes and then No to "unmoderated": the link is sent by the person, outside the app |
| Does the app share the user's current location with other users? | No | The app never reads location |
| Does the app allow users to purchase digital goods? | No | Nothing is paid |
| Does the app contain any Web browser or search engine features? | No | Links open in the phone's own browser |
| Does the app allow users to spend money, or is it for gambling? | No | |
| Does the app contain any affiliate marketing, sponsored content or ads? | No | |

Expected result: rated for everyone (IARC 3+, ESRB Everyone, PEGI 3, USK 0). Redo the questionnaire if a later
release adds a way for people to write to each other.

## Target audience and content

| Question | Answer |
| --- | --- |
| Target age groups | 13 to 15, 16 to 17, and 18 and over. Not any group under 13 |
| Does your app's store listing, or the app, appeal to children? | No |
| Are ads shown that could appeal to children? | Not asked, since there are no ads |

Why 13 and over rather than 18 only: the privacy policy says the app is not directed at children under 13, and
nothing in it needs an adult. Choosing an under-18 group makes the Console ask the child appeal question, answered
No above; it does not make the app a Families app. If Matt would rather answer nothing about minors, 18 and over
alone is also honest and skips the question.

## News apps

"Is your app a news app?" **No.**

## COVID-19 contact tracing and status apps

**My app is not a publicly available COVID-19 contact tracing or status app.**

## Data safety

The form's opening questions:

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes. Everything goes over HTTPS to glyph-api, attack.fm and ghostmarkdown.com |
| Do you provide a way for users to request that their data is deleted? | Yes |
| Account creation: does your app allow users to create an account? | Yes, by username and password inside the app |
| Do you provide a way for users to request that their account is deleted? | Yes. In the app: Settings › Account › Delete account. On the web: https://ghostmarkdown.com/delete-account.html |
| Can users request deletion of some data without deleting the account? | Yes: a person can stop any shared link (Settings › Account › Shared links), delete notes, and remove recordings and pictures from notes, and each is deleted from the server on the next sync |

The data types. Every type not in this table is **not collected and not shared**.

| Type | Collected | Shared | Optional or required | Ephemeral | Purposes | Why |
| --- | --- | --- | --- | --- | --- | --- |
| Personal info › User IDs | Yes | No | Optional: only with an account | No | Account management | The handle, kept with the account with the time it was made and last signed in to |
| Device or other IDs | Yes | No | Optional: only with an account, except the access log line, which any request leaves | No | Account management; Fraud prevention, security, and compliance | Each signed-in device registers a public key and says what kind of device it is. The web server also keeps ordinary access logs with the IP address, time and address requested, as the privacy page says. The sync service holds an IP address in memory only, to rate-limit sign-in attempts |

What is declared as not collected, and the rule that makes it so:

| What | Why not collected |
| --- | --- |
| Notes and their text (Files and docs), recordings (Audio files), pictures (Photos), settings | Sealed on the device with AES-256-GCM before they sync, under a key the server never holds. Play's rule: data "unreadable by you or anyone other than the sender and recipient as a result of end-to-end encryption does not need to be disclosed" |
| Voice, transcription, the AI's work | Processed on the device only, never sent |
| Shared links | The copy uploaded is sealed, and the key is in the link after the `#`, which browsers never send to a server |
| Live typing | Sealed the same way, relayed and never stored |
| Notion and GitHub | Sent by the person's device straight to the service they chose, which the form counts as the person's own action, not sharing. Notion's sign-in tokens pass through glyph-api for at most ten minutes in memory, which is ephemeral |
| The hosted Claude connection | While connected, the server holds the account key in memory and decrypts notes per request for Claude. Each request is served from memory and nothing is stored, so it is ephemeral processing under the form's definition. Whether to declare Files and docs as ephemerally processed for it is the one judgement call: declaring it costs nothing on the listing (ephemeral data is not shown) and is the safer answer. What Claude reads then goes to Anthropic under its own policy, by the person's own action |
| Location, contacts, calendar, messages, health, financial, web browsing, app activity, crash logs, analytics | The app has none of these. No analytics or crash reporting SDK |

Security practices, the last section: encrypted in transit, Yes; deletion mechanism, Yes; independent security
review, No.

## Government apps

**No**, not developed by or for a government.

## Financial features

**My app doesn't provide any financial features.**

## Health apps

**My app does not have any health features.**

## Advertising ID

"Does your app use advertising ID?" **No.** The manifest declares no `com.google.android.gms.permission.AD_ID`, and
nothing in the app reads the id.

## Foreground service permissions (1.9.0 only)

Asked once the uploaded bundle declares a foreground service type, which 1.8.0 does not. If 1.9.0 records a meeting
with the screen off through a foreground service of type `microphone`, the Console asks, per type:

- Type: **Microphone**
- Use case: Voice recording (or "Other" with the description below if the preset does not fit)
- Description, pasted:

```
Ghost.md records a meeting the person starts by hand, by tapping Record a meeting in the app, and keeps recording after the screen goes off, which is the only reason for a foreground service. A persistent notification shows while it records, and the person ends it from the notification or the app. When the recording ends, the app transcribes and summarises it on the device, in the same service, and posts one notification saying the summary is ready. If the system stops the service, the recording so far is saved as a note and nothing is lost but the rest of the meeting. Audio never leaves the phone.
```

- Video link: a YouTube or Drive link to a short screen recording that shows: starting a meeting, the screen
  turning off, the notification, ending it, and the summary arriving. Matt records this on the Fold once 1.9.0 runs.

Also check on the build: `FOREGROUND_SERVICE` and `FOREGROUND_SERVICE_MICROPHONE` in the manifest, the service's
`android:foregroundServiceType="microphone"`, and, on Android 14 and later, that the service is started while the
app is in the foreground, since a microphone service cannot be started from the background.

## Review notes

The Console offers a free text field for reviewers under App access, and the release itself has none. Paste this
under the App access instructions if the field takes it:

```
Two things in the manifest may look unusual. Ghost.md registers a voice interaction service and the assistant intent so that it can be chosen as the phone's digital assistant; that makes a held side key open the recorder. The recognition service beside it is required by the assistant role and does nothing. Nothing listens in the background: the microphone opens only when a recording is started. The app also updates its web bundle over the air from attack.fm, signed with a key compiled into the app; the Play build never installs an APK. Voice transcription and the AI run on the device with models the app downloads once (Whisper, and a Qwen or Gemma model), and the first launch downloads the 60 MB voice model.
```
