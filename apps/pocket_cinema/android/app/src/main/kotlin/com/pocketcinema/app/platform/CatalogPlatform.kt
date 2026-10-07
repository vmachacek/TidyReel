package com.pocketcinema.app.platform

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.DocumentsContract
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Local catalog presentation data. Video access remains scoped to the granted SAF tree. */
class CatalogPlatform(context: Context, messenger: BinaryMessenger) {
    private val resolver = context.contentResolver
    private val preferences = context.getSharedPreferences("cinema_catalog", Context.MODE_PRIVATE)
    private val metadataPreferences = context.getSharedPreferences("cinema_metadata_credentials", Context.MODE_PRIVATE)
    private val executor = Executors.newFixedThreadPool(2)
    private val metadataExecutor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "com.pocketcinema.app/catalog")
    @Volatile private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "loadPreferences" -> result.success(preferences.getString("library", "{}"))
                "savePreferences" -> {
                    val value = call.argument<String>("value")
                    if (value == null) result.error("INVALID_ARGUMENT", "Missing preferences.", null)
                    else { preferences.edit().putString("library", value).apply(); result.success(null) }
                }
                "loadMetadataToken" -> metadataResult(result) { loadMetadataToken() }
                "saveMetadataToken" -> {
                    val value = call.argument<String>("value")
                    if (value == null) result.error("INVALID_ARGUMENT", "Missing metadata token.", null)
                    else metadataResult(result) { saveMetadataToken(value); null }
                }
                "openMetadataHelp" -> runCatching {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.themoviedb.org/settings/api"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }.fold(
                    onSuccess = { result.success(null) },
                    onFailure = { result.error("METADATA_HELP_UNAVAILABLE", "Could not open TMDB API setup.", null) },
                )
                "thumbnail" -> {
                    val treeValue = call.argument<String>("treeUri")
                    val key = call.argument<String>("storageKey")
                    if (treeValue == null || key == null) result.error("INVALID_ARGUMENT", "Missing file identifier.", null)
                    else executor.execute {
                        val bytes = runCatching {
                            val tree = Uri.parse(treeValue)
                            val separator = key.indexOf('|')
                            require(separator > 0 && separator < key.length - 1)
                            require(key.substring(0, separator) == tree.authority)
                            val documentId = key.substring(separator + 1)
                            val rootId = DocumentsContract.getTreeDocumentId(tree)
                            require(documentId == rootId || DocumentsContract.isChildDocument(resolver,
                                DocumentsContract.buildDocumentUriUsingTree(tree, rootId),
                                DocumentsContract.buildDocumentUriUsingTree(tree, documentId)))
                            val document = DocumentsContract.buildDocumentUriUsingTree(tree, documentId)
                            val retriever = MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(context, document)
                                val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
                                val sampleUs = durationMs?.let { (it * 0.15).toLong().coerceIn(0L, 120_000L) * 1000L } ?: 3_000_000L
                                val frame = retriever.getScaledFrameAtTime(sampleUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 640, 360)
                                    ?: retriever.getScaledFrameAtTime(0L, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 640, 360)
                                frame?.let {
                                    try { ByteArrayOutputStream().use { output ->
                                        it.compress(Bitmap.CompressFormat.JPEG, 85, output)
                                        output.toByteArray()
                                    } } finally { it.recycle() }
                                }
                            } finally { retriever.release() }
                        }.getOrNull()
                        main.post { if (!closed) result.success(bytes) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun metadataResult(result: MethodChannel.Result, operation: () -> Any?) {
        metadataExecutor.execute {
            val outcome = runCatching(operation)
            main.post {
                if (!closed) outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error("METADATA_TOKEN_ERROR", "Could not access the saved metadata token.", null) },
                )
            }
        }
    }

    private fun loadMetadataToken(): String? {
        val encrypted = metadataPreferences.getString("token_v1", null) ?: return null
        val encodedIv = metadataPreferences.getString("iv_v1", null)
            ?: error("Missing encrypted credential IV.")
        val key = metadataKey(create = false) ?: return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, Base64.decode(encodedIv, Base64.NO_WRAP)))
        cipher.updateAAD(METADATA_KEY_ALIAS.toByteArray(Charsets.UTF_8))
        val plaintext = cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP))
        return try { plaintext.toString(Charsets.UTF_8) } finally { plaintext.fill(0) }
    }

    private fun saveMetadataToken(value: String) {
        if (value.isBlank()) {
            check(metadataPreferences.edit().clear().commit())
            val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            if (keyStore.containsAlias(METADATA_KEY_ALIAS)) keyStore.deleteEntry(METADATA_KEY_ALIAS)
            return
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        // The Keystore generates a fresh IV. Never supply one for encryption.
        cipher.init(Cipher.ENCRYPT_MODE, metadataKey(create = true))
        cipher.updateAAD(METADATA_KEY_ALIAS.toByteArray(Charsets.UTF_8))
        val plaintext = value.trim().toByteArray(Charsets.UTF_8)
        val encrypted = try { cipher.doFinal(plaintext) } finally { plaintext.fill(0) }
        check(metadataPreferences.edit()
            .putString("token_v1", Base64.encodeToString(encrypted, Base64.NO_WRAP))
            .putString("iv_v1", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .commit())
    }

    private fun metadataKey(create: Boolean): SecretKey? {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(METADATA_KEY_ALIAS, null) as? SecretKey)?.let { return it }
        if (!create) return null
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(METADATA_KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build())
            generateKey()
        }
    }

    fun close() { closed = true; channel.setMethodCallHandler(null); executor.shutdownNow(); metadataExecutor.shutdownNow() }

    private companion object {
        const val METADATA_KEY_ALIAS = "com.pocketcinema.app.tmdb_token.v1"
    }
}
