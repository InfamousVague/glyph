package com.mattssoftware.ghost_md

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * The two sums behind a picture drawn smaller (Pictures.kt): the sample size it is decoded at, and what it is then
 * scaled by. The drawing itself is Android's (`BitmapFactory`, `Bitmap.compress`), which a JVM test has none of.
 */
class PicturesTest {
  @Test
  fun decodes_at_the_smallest_half_that_is_still_at_least_what_is_drawn() {
    // A phone's photograph, 4000 on its long side, for a share's 1024: decoded at a half (2000), never a quarter (1000).
    assertEquals(2, Pictures.sampleFor(4000, 1024))
    assertEquals(4, Pictures.sampleFor(4096, 1024))
    assertEquals(8, Pictures.sampleFor(12000, 1024))
    assertEquals(1, Pictures.sampleFor(2047, 1024))
    assertEquals(1, Pictures.sampleFor(800, 1024))
    // A picked picture, kept at 1600.
    assertEquals(2, Pictures.sampleFor(4000, 1600))
    assertEquals(1, Pictures.sampleFor(3199, 1600))
    // A picture whose size would not read.
    assertEquals(1, Pictures.sampleFor(0, 1024))
    assertEquals(1, Pictures.sampleFor(-1, 1024))
  }

  @Test
  fun scales_the_long_side_down_to_the_cap_and_never_up() {
    assertEquals(0.512f, Pictures.scaleFor(2000, 1500, 1024), 0.0001f)
    assertEquals(0.512f, Pictures.scaleFor(1500, 2000, 1024), 0.0001f)
    assertEquals(1f, Pictures.scaleFor(1024, 768, 1024), 0f)
    assertEquals(1f, Pictures.scaleFor(640, 480, 1024), 0f)
    assertEquals(1f, Pictures.scaleFor(0, 0, 1024), 0f)
  }
}
