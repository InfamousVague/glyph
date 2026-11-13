package com.infamousvague.ghostmessaging

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StickersTest {
    @Test
    fun aStickerIsNamedForItsPackAndNumber() {
        assertEquals("ghost-sticker-love-03.png", Stickers.file("love-03"))
        assertTrue(Stickers.isSticker(Stickers.file("sweet-16")))
    }

    @Test
    fun aNameCarriesNothingAHeaderCouldChokeOn() {
        assertEquals("ghost-sticker-love03.png", Stickers.file("lo\"ve\r\n/0 3"))
        assertEquals("ghost-sticker-sticker.png", Stickers.file("../\u0000"))
        assertTrue(Stickers.file("x".repeat(500)).length < 64)
    }

    @Test
    fun anyOtherPictureIsNotASticker() {
        assertFalse(Stickers.isSticker(null))
        assertFalse(Stickers.isSticker("image0.jpg"))
        assertFalse(Stickers.isSticker("my-ghost-sticker.png"))
        // A part's name may arrive with a folder before it.
        assertTrue(Stickers.isSticker("parts/ghost-sticker-party-01.png"))
    }
}
