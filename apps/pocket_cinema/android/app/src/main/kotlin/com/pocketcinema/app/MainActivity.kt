package com.pocketcinema.app

import com.pocketcinema.app.platform.CatalogPlatform
import com.pocketcinema.app.platform.PlayerControlsPlatform
import com.pocketcinema.app.platform.RenderingPerformancePlatform
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.KeyEvent
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.activity.result.contract.ActivityResultContracts
import com.pocketcinema.app.platform.AndroidRootPermissionStore
import com.pocketcinema.app.platform.AndroidProbeBackend
import com.pocketcinema.app.platform.AuthorizedRootMessage
import com.pocketcinema.app.platform.FlutterError
import com.pocketcinema.app.platform.MediaProbeService
import com.pocketcinema.app.platform.PlaybackLeaseRegistry
import com.pocketcinema.app.platform.ScanSessionRegistry
import com.pocketcinema.app.platform.SmallFileReader
import com.pocketcinema.app.platform.STORAGE_SCAN_EVENT_CHANNEL
import com.pocketcinema.app.platform.StorageHostApi
import com.pocketcinema.app.platform.StorageHostApiImpl
import com.pocketcinema.app.platform.StorageScanEventHandler
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.io.FileNotFoundException
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enterImmersiveMode()
    }

    override fun onResume() {
        super.onResume()
        renderingPerformance?.resume()
        enterImmersiveMode()
    }

    override fun onPause() {
        renderingPerformance?.pause()
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) enterImmersiveMode()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (playerControls?.shouldConsume(event.keyCode) == true) return true
        return super.dispatchKeyEvent(event)
    }

    private fun enterImmersiveMode() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    private var catalogPlatform: CatalogPlatform? = null
    private var playerControls: PlayerControlsPlatform? = null
    private var renderingPerformance: RenderingPerformancePlatform? = null
    private lateinit var rootPermissionStore: AndroidRootPermissionStore
    private lateinit var scanSessionRegistry: ScanSessionRegistry
    private lateinit var scanEventHandler: StorageScanEventHandler
    private lateinit var scanEventChannel: EventChannel
    private lateinit var playbackLeaseRegistry: PlaybackLeaseRegistry
    private var pendingDirectoryChoice:
        CancellableContinuation<AuthorizedRootMessage>? = null

    private val directoryPicker =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            val continuation = pendingDirectoryChoice ?: return@registerForActivityResult
            pendingDirectoryChoice = null
            if (!continuation.isActive) {
                return@registerForActivityResult
            }

            val uri = result.data?.data
            if (uri == null) {
                continuation.resumeWith(
                    Result.failure(
                        FlutterError(
                            code = "USER_CANCELLED",
                            message = "No media folder was selected.",
                        ),
                    ),
                )
                return@registerForActivityResult
            }

            val outcome = runCatching {
                rootPermissionStore.persistReadPermission(
                    treeUri = uri,
                    returnedFlags = result.data?.flags ?: 0,
                )
            }
            continuation.resumeWith(outcome)
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        catalogPlatform = CatalogPlatform(this, flutterEngine.dartExecutor.binaryMessenger)
        playerControls = PlayerControlsPlatform(flutterEngine.dartExecutor.binaryMessenger)
        renderingPerformance = RenderingPerformancePlatform(this, flutterEngine.dartExecutor.binaryMessenger)
        rootPermissionStore = AndroidRootPermissionStore(contentResolver)
        scanSessionRegistry = ScanSessionRegistry()
        playbackLeaseRegistry = PlaybackLeaseRegistry()
        scanEventHandler = StorageScanEventHandler()
        scanEventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STORAGE_SCAN_EVENT_CHANNEL,
        ).also { channel ->
            channel.setStreamHandler(scanEventHandler)
        }
        val smallFileReader = SmallFileReader { uri ->
            contentResolver.openInputStream(Uri.parse(uri))
                ?: throw FileNotFoundException("The requested sidecar is unavailable.")
        }
        StorageHostApi.setUp(
            flutterEngine.dartExecutor.binaryMessenger,
            StorageHostApiImpl(
                chooseDirectoryAction = ::chooseDirectory,
                rootPermissionStore = rootPermissionStore,
                contentResolver = contentResolver,
                scanSessionRegistry = scanSessionRegistry,
                scanEventHandler = scanEventHandler,
                smallFileReader = smallFileReader,
                mediaProbeService = MediaProbeService {
                    AndroidProbeBackend(contentResolver)
                },
                playbackLeaseRegistry = playbackLeaseRegistry,
            ),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        playerControls?.close()
        playerControls = null
        renderingPerformance?.close()
        renderingPerformance = null
        catalogPlatform?.close()
        catalogPlatform = null
        StorageHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        scanSessionRegistry.close()
        playbackLeaseRegistry.closeAll()
        scanEventHandler.endOfStream()
        scanEventChannel.setStreamHandler(null)
        pendingDirectoryChoice?.cancel()
        pendingDirectoryChoice = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private suspend fun chooseDirectory(): AuthorizedRootMessage =
        suspendCancellableCoroutine { continuation ->
            if (pendingDirectoryChoice != null) {
                continuation.resumeWith(
                    Result.failure(
                        FlutterError(
                            code = "PICKER_ALREADY_ACTIVE",
                            message = "A folder picker is already active.",
                        ),
                    ),
                )
                return@suspendCancellableCoroutine
            }

            pendingDirectoryChoice = continuation
            continuation.invokeOnCancellation {
                if (pendingDirectoryChoice === continuation) {
                    pendingDirectoryChoice = null
                }
            }
            directoryPicker.launch(directoryPickerIntent())
        }

    private fun directoryPickerIntent(): Intent =
        Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
}

