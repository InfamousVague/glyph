package com.mattssoftware.ghost_md.wear

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.wear.compose.foundation.lazy.AutoCenteringParams
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Colors
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Typography
import kotlinx.coroutines.delay
import java.text.DateFormat
import java.util.Date

/**
 * The watch app's one screen (docs/WATCH.md, "On the watch"): Ghost.md's black and ink. Idle, the listening ghost in a
 * ring is the button, "Tap to record" under it, and the last takes under that with where each is (on the phone, sent,
 * waiting for the phone). Recording, the button is Stop, ringed by the voice's level, with the take's clock above it.
 * A take that stops says where it went ("Sent to Ghost.md", or "Queued" until the phone is near) and goes back to the
 * list.
 *
 * A launch for a recording ([ACTION_RECORD]: the tile, the complication, the shortcut) starts one at once, which is a
 * tap all the same: the microphone opens on a tap and nothing else. A stem button the watch lets apps have (not the
 * home key) starts and stops a take as the button does.
 */
class MainActivity : ComponentActivity() {
    companion object {
        const val ACTION_RECORD = "com.mattssoftware.ghost_md.wear.RECORD"

        /** The same ask as an extra, for a tile, whose launch can carry extras but no action. */
        const val EXTRA_RECORD = "record"
    }

    /** A launch asked for a recording, not yet started; read by the screen. */
    private val recordAsked = mutableStateOf(false)

    /** A stem button's press, counted, for the screen to toggle on. */
    private val stemPresses = mutableLongStateOf(0L)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) takeLaunch(intent)
        setContent { GhostWatch(recordAsked, stemPresses) }
        offerShortcut()
    }

    /** "Record a note" on the launcher's long press: a take at once, as the tile and the complication start one. */
    private fun offerShortcut() {
        try {
            val record = Intent(this, MainActivity::class.java).setAction(ACTION_RECORD)
            val shortcut = ShortcutInfoCompat.Builder(this, "record")
                .setShortLabel(getString(R.string.record_note_short))
                .setLongLabel(getString(R.string.record_note))
                .setIcon(IconCompat.createWithResource(this, R.drawable.ghost_ic_mic))
                .setIntent(record)
                .build()
            ShortcutManagerCompat.pushDynamicShortcut(this, shortcut)
        } catch (_: Exception) {
            // A launcher with no shortcuts: the tile and the complication remain.
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeLaunch(intent)
    }

    override fun onResume() {
        super.onResume()
        Sender.kick(this)
    }

    private fun takeLaunch(intent: Intent?) {
        if (intent?.action == ACTION_RECORD || intent?.getBooleanExtra(EXTRA_RECORD, false) == true) recordAsked.value = true
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (event.repeatCount == 0 && (keyCode == KeyEvent.KEYCODE_STEM_1 || keyCode == KeyEvent.KEYCODE_STEM_2 || keyCode == KeyEvent.KEYCODE_STEM_3)) {
            stemPresses.longValue += 1
            return true
        }
        return super.onKeyDown(keyCode, event)
    }
}

private val Ink = Color(0xFFF3F3F0)
private val Ink2 = Color(0xFF9A9A96)
private val Faint = Color(0xFF2A2A28)

/** Inter, as the app sets its words: one variable file at three weights. */
@OptIn(ExperimentalTextApi::class)
private val Inter = FontFamily(
    Font(R.font.inter, FontWeight.Normal, variationSettings = FontVariation.Settings(FontVariation.weight(400))),
    Font(R.font.inter, FontWeight.Medium, variationSettings = FontVariation.Settings(FontVariation.weight(500))),
    Font(R.font.inter, FontWeight.SemiBold, variationSettings = FontVariation.Settings(FontVariation.weight(600))),
)

@Composable
private fun GhostTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colors = Colors(primary = Ink, onPrimary = Color.Black, secondary = Ink, onSecondary = Color.Black, background = Color.Black, onBackground = Ink, surface = Faint, onSurface = Ink, onSurfaceVariant = Ink2),
        typography = Typography(defaultFontFamily = Inter),
        content = content,
    )
}

@Composable
private fun GhostWatch(recordAsked: androidx.compose.runtime.MutableState<Boolean>, stemPresses: androidx.compose.runtime.MutableLongState) {
    val context = LocalContext.current
    val queue = remember { WatchApp.takes(context) }
    var takes by remember { mutableStateOf(queue.all()) }
    DisposableEffect(queue) {
        val heard: (List<Take>) -> Unit = { now -> ContextCompat.getMainExecutor(context).execute { takes = now } }
        queue.addListener(heard)
        takes = queue.all()
        onDispose { queue.removeListener(heard) }
    }
    val recording by RecordService.recording.collectAsState()
    val confirming by Confirmation.take.collectAsState()
    var refused by remember { mutableStateOf(false) }

    val permissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
        if (granted[Manifest.permission.RECORD_AUDIO] == true) {
            refused = false
            RecordService.start(context)
        } else {
            refused = true
        }
    }
    fun toggle() {
        if (recording.id != null) {
            RecordService.stop(context)
            return
        }
        Confirmation.dismiss()
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            RecordService.start(context)
        } else {
            val asked = mutableListOf(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= 33) asked.add(Manifest.permission.POST_NOTIFICATIONS)
            permissions.launch(asked.toTypedArray())
        }
    }
    LaunchedEffect(recordAsked.value) {
        if (recordAsked.value) {
            recordAsked.value = false
            if (recording.id == null) toggle()
        }
    }
    LaunchedEffect(stemPresses.longValue) {
        if (stemPresses.longValue > 0) toggle()
    }

    GhostTheme {
        val list = rememberScalingLazyListState(initialCenterItemIndex = 0)
        Scaffold(
            modifier = Modifier.background(Color.Black),
            // The take's own clock stands where the time would while it runs.
            timeText = { if (recording.id == null) TimeText() },
            positionIndicator = { if (recording.id == null && confirming == null) PositionIndicator(scalingLazyListState = list) },
        ) {
            if (recording.id != null) {
                Recorder(recording, onStop = ::toggle)
            } else {
                ScalingLazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    state = list,
                    autoCentering = AutoCenteringParams(itemIndex = 0),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    item { GhostButton(onClick = ::toggle) }
                    item {
                        val problem = if (refused) "Allow the microphone to record a note." else recording.problem
                        Text(
                            text = problem ?: "Tap to record",
                            color = if (problem != null) Ink else Ink2,
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center,
                            modifier = Modifier.padding(horizontal = 12.dp),
                        )
                    }
                    val recent = takes.filter { it.state != TakeState.RECORDING }.take(5)
                    if (recent.isNotEmpty()) {
                        item { Spacer(Modifier.height(6.dp)) }
                        items(recent, key = { it.id }) { take -> TakeRow(take) }
                    }
                }
            }
            confirming?.let { id -> Confirm(takes.firstOrNull { it.id == id }) }
        }
    }
}

/** The idle button: the listening ghost in an ink ring. */
@Composable
private fun GhostButton(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .padding(top = 18.dp, bottom = 4.dp)
            .size(92.dp)
            .clip(CircleShape)
            .border(2.dp, Ink, CircleShape)
            .clickable(onClick = onClick)
            .semantics { contentDescription = "Record a note" },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(R.drawable.ghost_listening),
            contentDescription = null,
            colorFilter = ColorFilter.tint(Ink),
            modifier = Modifier.size(60.dp),
        )
    }
}

/** While a take runs: its clock, and Stop ringed by the voice's level. */
@Composable
private fun Recorder(recording: Recording, onStop: () -> Unit) {
    var now by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    LaunchedEffect(recording.id) {
        while (true) {
            now = SystemClock.elapsedRealtime()
            delay(250)
        }
    }
    val level = recording.level
    Column(modifier = Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text(clock(now - recording.startedAt), fontSize = 26.sp, fontWeight = FontWeight.Medium, color = Ink)
        Spacer(Modifier.height(8.dp))
        Box(modifier = Modifier.size(112.dp), contentAlignment = Alignment.Center) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val base = size.minDimension / 2 * 0.74f
                val reach = size.minDimension / 2 - base
                // Three rings, the outer ones fainter, spreading as the voice is louder.
                for (ring in 0 until 3) {
                    val r = base + reach * level * (ring + 1) / 3f
                    drawCircle(color = Ink.copy(alpha = (0.55f - ring * 0.17f) * (0.35f + 0.65f * level)), radius = r, style = Stroke(width = 2.dp.toPx()))
                }
            }
            Box(
                modifier = Modifier
                    .size(78.dp)
                    .clip(CircleShape)
                    .background(Ink)
                    .clickable(onClick = onStop)
                    .semantics { contentDescription = "Stop and send to your phone" },
                contentAlignment = Alignment.Center,
            ) {
                Box(Modifier.size(24.dp).clip(RoundedCornerShape(4.dp)).background(Color.Black))
            }
        }
        Spacer(Modifier.height(8.dp))
        Text("Tap to stop", fontSize = 13.sp, color = Ink2)
    }
}

/** One take in the list: when, how long, and where it is. */
@Composable
private fun TakeRow(take: Take) {
    val context = LocalContext.current
    val time = remember(take.recordedAt) { DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(take.recordedAt)) }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp, vertical = 2.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(Faint)
            .clickable { if (take.state == TakeState.QUEUED) Sender.kick(context) }
            .padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text("$time · ${clock(take.durationMs)}", fontSize = 14.sp, color = Ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(stateWords(take.state), fontSize = 12.sp, color = Ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.width(8.dp))
        Box(Modifier.size(8.dp).clip(CircleShape).background(if (take.state == TakeState.ON_PHONE) Ink else Color.Transparent).border(1.5.dp, Ink, CircleShape))
    }
}

/** Where a stopped take went, until it is clear or a tap sends it away. */
@Composable
private fun Confirm(take: Take?) {
    val near by PhoneNear.near.collectAsState()
    val arrived = take != null && (take.state == TakeState.SENT || take.state == TakeState.ON_PHONE)
    var waited by remember(take?.id) { mutableStateOf(false) }
    LaunchedEffect(take?.id) {
        delay(4000)
        waited = true
    }
    LaunchedEffect(arrived, waited) {
        if (arrived || waited) {
            delay(if (arrived) 1800 else 3200)
            Confirmation.dismiss()
        }
    }
    val words = when {
        take == null -> "Too short to keep"
        arrived -> "Sent to Ghost.md"
        waited || near == false -> "Queued. Sends when your phone is near."
        else -> "Sending to your phone"
    }
    Box(
        modifier = Modifier.fillMaxSize().background(Color.Black).clickable { Confirmation.dismiss() },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(horizontal = 24.dp)) {
            Image(painter = painterResource(R.drawable.ghost_listening), contentDescription = null, colorFilter = ColorFilter.tint(Ink), modifier = Modifier.size(54.dp))
            Spacer(Modifier.height(10.dp))
            Text(words, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Ink, textAlign = TextAlign.Center)
        }
    }
}

private fun stateWords(state: TakeState): String = when (state) {
    TakeState.RECORDING -> "Recording"
    TakeState.QUEUED -> "Queued"
    TakeState.SENDING -> "Sending"
    TakeState.SENT -> "Sent"
    TakeState.ON_PHONE -> "On your phone"
}

/** 0:42, 12:05, 1:02:09. */
internal fun clock(ms: Long): String {
    val s = (ms / 1000).coerceAtLeast(0)
    val h = s / 3600
    val m = (s % 3600) / 60
    val sec = s % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, sec) else "%d:%02d".format(m, sec)
}
