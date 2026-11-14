# Picture messages on an emulator

An emulator has no carrier, so a picture message (MMS) neither leaves it nor reaches it. These three files stand in
for one, so that sending and receiving run end to end with nothing but the Mac (Matt, 2026-11-13: "It seems like
picture sending is also not working at all almost like MMS isn't working"). They are how 0.6.2 was tested; none of
them ships in the app. Use a throwaway emulator (`emulator -avd ghostflutter2 -read-only -no-window -port 5590`):
this changes its carrier settings as root.

## The stand-in carrier

    python3 -u tool/mms/fake_mmsc.py /tmp/mms        # listens on 18765; keeps what is posted in /tmp/mms/post-N.bin

It answers a message sent with the carrier's acceptance (m-send-conf), and serves `/tmp/mms/serve/<name>` to a phone
fetching one. `touch /tmp/mms/refuse` makes it take a message and refuse it ("Unknown subscriber"), which Android
reports as sent; `touch /tmp/mms/down` makes it refuse fetches (HTTP 503).

## Pointing the emulator at it

    adb -s emulator-5590 root
    adb -s emulator-5590 shell 'sqlite3 /data/user_de/0/com.android.providers.telephony/databases/telephony.db \
        "update carriers set mmsc=\"http://10.0.2.2:18765/mms\", mmsproxy=\"\", mmsport=\"\" where numeric=\"310260\""'
    adb -s emulator-5590 shell 'kill $(pidof com.android.phone)'        # it starts again and reads the settings
    adb -s emulator-5590 shell cmd phone cc set-value enabledMMS true   # the emulator's carrier has MMS off (result 12)
    adb -s emulator-5590 shell setprop log.tag.MmsService VERBOSE       # Android's side, in `logcat -b all`

Then send a sticker or a photo from the app. `10.0.2.2` is the Mac as the emulator sees it.

## Checking what was sent with Android's own parser

    J=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
    $J/bin/javac --release 8 PduCheck.java Inject.java
    JAVA_HOME=$J ~/Library/Android/sdk/build-tools/36.0.0/d8 --min-api 26 --output . PduCheck.class Inject.class
    adb push classes.dex /data/local/tmp/pducheck.dex && adb push /tmp/mms/post-1.bin /data/local/tmp/
    adb shell 'CLASSPATH=/data/local/tmp/pducheck.dex app_process / PduCheck /data/local/tmp/post-1.bin'

`PduCheck` reads a message with `com.google.android.mms.pdu.PduParser`, the parser every Android phone has, and
says what it found: a second opinion on `Pdu.kt`, whose own tests only read what it wrote itself.

## Receiving

A message to fetch is an m-retrieve-conf in `serve/`; it is announced by an m-notification-ind inside a WAP push
inside an SMS. `Inject` hands that SMS to the phone as if the radio had received it
(`ISms.injectSmsPduForSubscriber`, as root): `app_process / Inject /data/local/tmp/push.pdu 1`. The SMS must be
class 1 (data coding 0x15) or the phone refuses it ("injectSmsPdu: not class 1").

    python3 tool/mms/make_incoming.py /tmp/mms/post-1.bin /tmp/mms m1     # from a message the app sent
    adb push /tmp/mms/m1.push.pdu /data/local/tmp/ && adb shell 'CLASSPATH=/data/local/tmp/pducheck.dex app_process / Inject /data/local/tmp/m1.push.pdu 1'

The app fetches `m1` from the stand-in carrier, stores it and raises its notification.
