package com.pocketcinema.app.platform

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class OrganizerPlatform(context: Context, messenger: BinaryMessenger) {
    private val resolver = context.contentResolver
    private val channel = MethodChannel(messenger, "com.pocketcinema.app/organizer")
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "applicationId" -> result.success(context.packageName)
                "checkWriteAccess" -> {
                    val tree = call.argument<String>("treeUri")
                    if (tree == null) result.error("INVALID_ARGUMENT", "Missing media folder.", null)
                    else execute(result) {
                        runCatching { AndroidOrganizerDocumentGateway(resolver, tree).hasWritePermission() }
                            .getOrDefault(false)
                    }
                }
                "organizeFiles" -> {
                    val tree = call.argument<String>("treeUri")
                    val items = parseItems(call)
                    if (tree == null || items == null) {
                        result.error("INVALID_ARGUMENT", "Missing media folder or valid organize requests.", null)
                    } else execute(result) {
                        val outcomes = try {
                            MediaFileOrganizer(AndroidOrganizerDocumentGateway(resolver, tree)).organize(items)
                        } catch (_: Exception) {
                            items.map { OrganizeFileResult(it.storageKey, it.destinationRelativePath, "failed",
                                "The media folder is unavailable. Choose the folder again before organizing.") }
                        }
                        mapOf("items" to outcomes.map { it.toMap() })
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun parseItems(call: MethodCall): List<OrganizeFileRequest>? {
        val values = call.argument<List<Any?>>("items") ?: return null
        if (values.size > 10000) return null
        return values.map { value ->
            val fields = value as? Map<*, *> ?: return null
            OrganizeFileRequest(
                fields["storageKey"] as? String ?: return null,
                fields["parentStorageKey"] as? String ?: return null,
                fields["sourceRelativePath"] as? String ?: return null,
                fields["destinationRelativePath"] as? String ?: return null,
                fields["videoStorageKey"] as? String,
            )
        }
    }

    private fun execute(result: MethodChannel.Result, action: () -> Any?) {
        executor.execute {
            if (closed) {
                main.post { result.error("ORGANIZER_CLOSED", "File organizer is closed.", null) }
                return@execute
            }
            val outcome = runCatching(action)
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error("ORGANIZER_FAILED", "The storage provider could not organize files.", null) },
                )
            }
        }
    }

    fun close() {
        closed = true
        channel.setMethodCallHandler(null)
        // Let any active move finish; interrupting between move and rename can strand a file.
    }

    companion object {
        // Serialize batches even when Android recreates the activity during an operation.
        private val executor = Executors.newSingleThreadExecutor()
    }
}
