package com.mattssoftware.glyph.media

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * A picked film's rules (media/VideoPick.kt): the answer the page reads, the room kept free, the frame its poster is
 * made from and how far that is turned, and the backup rules that keep films out of the cloud. The page reads the
 * answer's keys out of VideoPick.kt (core/videos.test.ts), and Rust its extensions (videos.rs).
 */
class VideoPickTest {
  @Test
  fun the_answers_are_the_json_the_page_reads() {
    assertEquals(
      """{"path":"/cache/picked/a.mp4","poster":"/cache/picked/a.jpg","ms":12345,"width":1080,"height":1920}""",
      VideoPick.picked("/cache/picked/a.mp4", "/cache/picked/a.jpg", 12_345, 1080, 1920),
    )
    assertEquals("""{"cancelled":true}""", VideoPick.cancelled())
    assertEquals("""{"error":"There isn’t room on this phone for that video."}""", VideoPick.failed(VideoPick.NO_ROOM))
    assertEquals("""{"error":"This video can’t be read."}""", VideoPick.failed(VideoPick.UNREADABLE))
  }

  @Test
  fun what_it_writes_is_json_whatever_the_words() {
    assertEquals("""{"error":"a \"quoted\" \\ line\u000abreak"}""", VideoPick.json("error" to "a \"quoted\" \\ line\nbreak"))
  }

  @Test
  fun a_film_is_kept_under_its_types_name_or_its_own() {
    assertEquals("mp4", VideoPick.extensionFor("video/mp4", "clip.bin"))
    assertEquals("mov", VideoPick.extensionFor("video/quicktime", null))
    assertEquals("m4v", VideoPick.extensionFor("VIDEO/X-M4V", null))
    assertEquals("webm", VideoPick.extensionFor("application/octet-stream", "Walk.WEBM"))
    assertNull(VideoPick.extensionFor("video/x-matroska", "clip.mkv"))
    assertNull(VideoPick.extensionFor("video/3gpp", "clip.3gp"))
    assertNull(VideoPick.extensionFor(null, null))
  }

  @Test
  fun a_film_leaves_the_phone_five_hundred_megabytes() {
    val mb = 1024L * 1024
    assertTrue(VideoPick.fits(100 * mb, 600 * mb))
    assertFalse(VideoPick.fits(100 * mb + 1, 600 * mb))
    assertTrue("a size not said needs the spare room at least", VideoPick.fits(-1, 500 * mb))
    assertFalse(VideoPick.fits(-1, 499 * mb))
  }

  @Test
  fun the_poster_is_a_second_in_or_half_way_through_a_short_film() {
    assertEquals(1_000_000L, VideoPick.frameAtUs(12_000))
    assertEquals(1_000_000L, VideoPick.frameAtUs(2_000))
    assertEquals(600_000L, VideoPick.frameAtUs(1_200))
    assertEquals(0L, VideoPick.frameAtUs(1))
  }

  @Test
  fun a_frame_is_turned_only_when_it_still_lies_as_the_film_is_stored() {
    // A portrait film stored 1920x1080, to be turned a quarter.
    assertEquals(90, VideoPick.turnBy(90, 1920, 1080, 1920, 1080))
    assertEquals("already turned by the platform", 0, VideoPick.turnBy(90, 1080, 1920, 1920, 1080))
    assertEquals(270, VideoPick.turnBy(270, 1920, 1080, 1920, 1080))
    assertEquals("a half turn is the platform's", 0, VideoPick.turnBy(180, 1920, 1080, 1920, 1080))
    assertEquals(0, VideoPick.turnBy(0, 1920, 1080, 1920, 1080))
    assertEquals("a square cannot tell", 0, VideoPick.turnBy(90, 1080, 1080, 1080, 1080))
    assertEquals("a film that says nothing", 0, VideoPick.turnBy(90, 1920, 1080, 0, 0))
  }

  @Test
  fun a_film_is_as_wide_as_it_is_watched() {
    assertEquals(1080 to 1920, VideoPick.shown(90, 1920, 1080, 900, 1600))
    assertEquals(1920 to 1080, VideoPick.shown(0, 1920, 1080, 1600, 900))
    assertEquals(1600 to 900, VideoPick.shown(0, 0, 0, 1600, 900))
  }

  @Test
  fun the_manifest_keeps_films_out_of_the_cloud_and_in_a_move() {
    val main = File("src/main")
    val manifest = File(main, "AndroidManifest.xml").readText()
    assertTrue(manifest.contains("android:fullBackupContent=\"@xml/glyph_backup_rules\""))
    assertTrue(manifest.contains("android:dataExtractionRules=\"@xml/glyph_data_extraction_rules\""))
    val exclude = "<exclude domain=\"root\" path=\"video/\" />"
    assertTrue(File(main, "res/xml/glyph_backup_rules.xml").readText().contains(exclude))
    val rules = File(main, "res/xml/glyph_data_extraction_rules.xml").readText()
    val cloud = rules.substringAfter("<cloud-backup>").substringBefore("</cloud-backup>")
    assertTrue(cloud.contains(exclude))
    assertFalse("a move by cable carries the films", rules.substringAfter("<device-transfer").contains(exclude))
    assertFalse("no permission is asked for a film the person picks", manifest.contains("READ_MEDIA"))
  }
}
