package com.mattssoftware.ghost_md.wear

import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture

/**
 * The tile: "Record a note" at one tap (docs/WATCH.md). The whole tile is the button: a microphone in an ink
 * ring, the words under it, and a tap opens the app with a take started ([MainActivity.EXTRA_RECORD]). The tile
 * itself never opens the microphone: the screen does, at the tap.
 */
class RecordTileService : TileService() {
    companion object {
        private const val RESOURCES = "2"
        private const val MIC = "mic"
        private const val INK = 0xFFF3F3F0.toInt()
        private const val INK_2 = 0xFF9A9A96.toInt()
    }

    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> =
        CallbackToFutureAdapter.getFuture { done ->
            done.set(
                TileBuilders.Tile.Builder()
                    .setResourcesVersion(RESOURCES)
                    .setTileTimeline(TimelineBuilders.Timeline.fromLayoutElement(layout()))
                    .build(),
            )
            "ghost-tile"
        }

    override fun onTileResourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> =
        CallbackToFutureAdapter.getFuture { done ->
            done.set(
                ResourceBuilders.Resources.Builder()
                    .setVersion(RESOURCES)
                    .addIdToImageMapping(
                        MIC,
                        ResourceBuilders.ImageResource.Builder()
                            .setAndroidResourceByResId(ResourceBuilders.AndroidImageResourceByResId.Builder().setResourceId(R.drawable.ghost_ic_mic).build())
                            .build(),
                    )
                    .build(),
            )
            "ghost-tile-resources"
        }

    private fun layout(): LayoutElementBuilders.LayoutElement {
        val record = ModifiersBuilders.Clickable.Builder()
            .setId("record")
            .setOnClick(
                ActionBuilders.LaunchAction.Builder()
                    .setAndroidActivity(
                        ActionBuilders.AndroidActivity.Builder()
                            .setPackageName(packageName)
                            .setClassName(MainActivity::class.java.name)
                            .addKeyToExtraMapping(MainActivity.EXTRA_RECORD, ActionBuilders.AndroidBooleanExtra.Builder().setValue(true).build())
                            .build(),
                    )
                    .build(),
            )
            .build()
        val ring = LayoutElementBuilders.Box.Builder()
            .setWidth(dp(84f))
            .setHeight(dp(84f))
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setClickable(record)
                    .setBorder(ModifiersBuilders.Border.Builder().setWidth(dp(2f)).setColor(argb(INK)).build())
                    .setBackground(ModifiersBuilders.Background.Builder().setCorner(ModifiersBuilders.Corner.Builder().setRadius(dp(42f)).build()).build())
                    .setSemantics(ModifiersBuilders.Semantics.Builder().setContentDescription("Record a note").build())
                    .build(),
            )
            .addContent(
                LayoutElementBuilders.Image.Builder()
                    .setResourceId(MIC)
                    .setWidth(dp(40f))
                    .setHeight(dp(40f))
                    .setColorFilter(LayoutElementBuilders.ColorFilter.Builder().setTint(argb(INK)).build())
                    .build(),
            )
            .build()
        val words = LayoutElementBuilders.Text.Builder()
            .setText("Record a note")
            .setFontStyle(LayoutElementBuilders.FontStyle.Builder().setSize(sp(15f)).setColor(argb(INK)).build())
            .build()
        val hint = LayoutElementBuilders.Text.Builder()
            .setText("Ghost.md")
            .setFontStyle(LayoutElementBuilders.FontStyle.Builder().setSize(sp(12f)).setColor(argb(INK_2)).build())
            .build()
        return LayoutElementBuilders.Box.Builder()
            .setWidth(expand())
            .setHeight(expand())
            .setModifiers(ModifiersBuilders.Modifiers.Builder().setClickable(record).build())
            .addContent(
                LayoutElementBuilders.Column.Builder()
                    .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
                    .addContent(ring)
                    .addContent(LayoutElementBuilders.Spacer.Builder().setHeight(dp(8f)).build())
                    .addContent(words)
                    .addContent(hint)
                    .build(),
            )
            .build()
    }
}
