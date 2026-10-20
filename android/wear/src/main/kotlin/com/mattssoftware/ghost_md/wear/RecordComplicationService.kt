package com.mattssoftware.ghost_md.wear

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.MonochromaticImageComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.SmallImage
import androidx.wear.watchface.complications.data.SmallImageComplicationData
import androidx.wear.watchface.complications.data.SmallImageType
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService

/**
 * A complication for any watch face that takes one: the microphone, which opens the app with a take started (docs/
 * WATCH.md). It never changes, so the watch face asks for it once ([UPDATE_PERIOD_SECONDS] is 0 in the manifest). The
 * microphone opens at the tap, on the app's screen, as with the tile.
 */
class RecordComplicationService : SuspendingComplicationDataSourceService() {
    override fun getPreviewData(type: ComplicationType): ComplicationData? = data(type)

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? = data(request.complicationType)

    private fun data(type: ComplicationType): ComplicationData? {
        val record = Intent(this, MainActivity::class.java).setAction(MainActivity.ACTION_RECORD).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tap = PendingIntent.getActivity(this, 0, record, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val said = PlainComplicationText.Builder("Record a note in Ghost.md").build()
        val mic = MonochromaticImage.Builder(Icon.createWithResource(this, R.drawable.ghost_ic_mic)).build()
        return when (type) {
            ComplicationType.SHORT_TEXT -> ShortTextComplicationData.Builder(PlainComplicationText.Builder("Note").build(), said).setMonochromaticImage(mic).setTapAction(tap).build()
            ComplicationType.MONOCHROMATIC_IMAGE -> MonochromaticImageComplicationData.Builder(mic, said).setTapAction(tap).build()
            ComplicationType.SMALL_IMAGE -> SmallImageComplicationData.Builder(SmallImage.Builder(Icon.createWithResource(this, R.drawable.ghost_ic_mic), SmallImageType.ICON).build(), said).setTapAction(tap).build()
            else -> null
        }
    }
}
