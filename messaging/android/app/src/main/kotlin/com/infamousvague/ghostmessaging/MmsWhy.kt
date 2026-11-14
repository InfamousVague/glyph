package com.infamousvague.ghostmessaging

/**
 * Why a picture message did not go or did not come, in plain words (Matt, 2026-11-13: "It seems like picture sending
 * is also not working at all almost like MMS isn't working"). On an emulator with a stand-in for a carrier both ways
 * work, so what stops one on a phone is the phone's or the carrier's: this is how the app says which, under the
 * message and in Settings › Android, where it used to say only "Not sent". Pure, so it is tested on the JVM.
 */
object MmsWhy {
    /**
     * Why Android could not send one: [code] is SmsManager's MMS_ERROR_* (what the sent broadcast's result is when it
     * is not OK), [http] the carrier's HTTP answer where there was one. Each reads after "Not sent: ".
     */
    fun send(code: Int, http: Int = 0): String = when (code) {
        2 -> "this phone has no picture-message settings (APN) for its SIM"
        3 -> "the carrier's picture-message service couldn't be reached. Check mobile data"
        4 -> if (http > 0) "the carrier's server refused it (HTTP $http)" else "the carrier's server couldn't be reached. Check mobile data"
        5 -> "Android couldn't read the message from this app"
        6 -> "the carrier asked for it to be tried again later"
        7 -> "this phone's picture-message settings are incomplete"
        8 -> "there is no mobile data connection. Picture messages need mobile data, even on Wi-Fi"
        9, 10 -> "the SIM it would go from isn't active"
        11 -> "mobile data is off. Picture messages need it, even on Wi-Fi"
        12 -> "the carrier has picture messaging switched off for this SIM"
        13 -> "it is too large for the carrier"
        else -> "Android gave no reason (code $code)"
    }

    /** Why Android could not fetch one that was announced. Reads after "Couldn't download a picture message: ". */
    fun download(code: Int, http: Int = 0): String = when (code) {
        4 -> if (http == 404 || http == 410) "the carrier no longer has it (it kept it for a few days)" else if (http > 0) "the carrier's server refused (HTTP $http)" else "the carrier's server couldn't be reached. Check mobile data"
        5 -> "Android couldn't write the message for this app"
        13 -> "it is too large"
        else -> send(code, http)
    }

    /**
     * A carrier's refusal of a message it took delivery of: X-Mms-Response-Status in its answer (OMA MMS encapsulation
     * 7.3.48), with its own words where it gave any. Null where the answer says the message was accepted (or says
     * nothing). Android reports such a message as sent; it is not.
     */
    fun refused(status: Int?, text: String?): String? {
        if (status == null || status == 0x80) return null
        val what = when (status) {
            0x82, 0xE1 -> "the carrier denied the service (this line may not have picture messaging)"
            0x83, 0xE2 -> "the carrier couldn't read the message"
            0x84, 0xC1, 0xE3 -> "the carrier doesn't know the number it is for"
            0x86, 0xC3 -> "the carrier had a network problem"
            0x87, 0xE5 -> "the carrier won't carry what is in it"
            0x88 -> "the carrier doesn't support this kind of message"
            0xEB -> "the line has no credit for it"
            in 0xC0..0xDF -> "the carrier couldn't take it just now"
            else -> "the carrier refused it"
        }
        val said = text?.trim().orEmpty()
        return if (said.isEmpty()) "$what (status ${"0x%02X".format(status)})" else "$what: \"$said\""
    }
}
