package com.tidyreel.local_media_hub

import android.content.Intent
import android.net.Uri
import androidx.activity.result.contract.ActivityResultContracts
import com.tidyreel.local_media_hub.platform.AndroidRootPermissionStore
import com.tidyreel.local_media_hub.platform.AuthorizedRootMessage
import com.tidyreel.local_media_hub.platform.FlutterError
import com.tidyreel.local_media_hub.platform.ScanSessionRegistry
import com.tidyreel.local_media_hub.platform.SmallFileReader
import com.tidyreel.local_media_hub.platform.STORAGE_SCAN_EVENT_CHANNEL
import com.tidyreel.local_media_hub.platform.StorageHostApi
import com.tidyreel.local_media_hub.platform.StorageHostApiImpl
import com.tidyreel.local_media_hub.platform.StorageScanEventHandler
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import java.io.FileNotFoundException
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine

class MainActivity : FlutterFragmentActivity() {
    private lateinit var rootPermissionStore: AndroidRootPermissionStore
    private lateinit var scanSessionRegistry: ScanSessionRegistry
    private lateinit var scanEventHandler: StorageScanEventHandler
    private lateinit var scanEventChannel: EventChannel
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
        rootPermissionStore = AndroidRootPermissionStore(contentResolver)
        scanSessionRegistry = ScanSessionRegistry()
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
            ),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        StorageHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, null)
        scanSessionRegistry.close()
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
