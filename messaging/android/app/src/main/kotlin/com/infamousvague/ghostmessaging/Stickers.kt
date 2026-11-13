package com.infamousvague.ghostmessaging

/**
 * How one of the app's stickers is named as it travels (Matt, 2026-11-13: "generate 4 sticker packs using our ghost
 * mascot"). A sticker goes as a picture message like any other, so that every phone can show it; its file's name,
 * `ghost-sticker-<pack>-<number>.png`, is all that tells this app to draw it as a sticker (small, on the page, with
 * no bubble) and to call it one in the list of conversations. To any other app it is a picture.
 */
object Stickers {
    private const val MARK = "ghost-sticker"

    /** The file name for the sticker [name] (its pack and number, `love-03`), with nothing in it a header could choke on. */
    fun file(name: String): String {
        val safe = name.filter { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' }.take(40).ifEmpty { "sticker" }
        return "$MARK-$safe.png"
    }

    /** Whether a picture part called [name] is one of the app's stickers. */
    fun isSticker(name: String?): Boolean = name != null && name.substringAfterLast('/').startsWith(MARK)
}
