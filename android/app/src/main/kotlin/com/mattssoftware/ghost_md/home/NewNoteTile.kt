package com.mattssoftware.ghost_md.home

import android.annotation.SuppressLint
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * New note, a tile in the notification shade's quick settings (docs/FEATURES_2_1.md): a tap puts the shade away and
 * opens a new note with the keyboard up (`ghostmd://new`, Doors.kt). Over a locked phone it asks to be unlocked
 * first, since a note is the person's own. Bound only by the system (BIND_QUICK_SETTINGS_TILE).
 */
class NewNoteTile : TileService() {
  override fun onStartListening() {
    super.onStartListening()
    // A button, not a switch: never lit.
    qsTile?.apply {
      state = Tile.STATE_INACTIVE
      updateTile()
    }
  }

  @SuppressLint("StartActivityAndCollapseDeprecated")
  override fun onClick() {
    super.onClick()
    val open = {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        startActivityAndCollapse(Doors.press(this, Doors.NEW, 7_300))
      } else {
        @Suppress("DEPRECATION")
        startActivityAndCollapse(Doors.intent(this, Doors.NEW))
      }
    }
    if (isLocked) unlockAndRun { open() } else open()
  }
}
