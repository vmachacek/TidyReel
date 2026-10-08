package com.pocketcinema.app.platform

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.security.SecureRandom
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import org.json.JSONException
import org.json.JSONObject

/** Unpaired nearby Bluetooth control. Phone adverts continue while its activity is paused. */
@SuppressLint("MissingPermission")
class KillSwitchPlatform(
    context: Context,
    messenger: BinaryMessenger,
    private val requestPermissions: (MethodChannel.Result) -> Unit,
) {
    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences("cinema_kill_switch", Context.MODE_PRIVATE)
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "com.pocketcinema.app/kill_switch")
    private val events = EventChannel(messenger, "com.pocketcinema.app/kill_switch_events")
    private var sink: EventChannel.EventSink? = null
    private var scanner: BluetoothLeScanner? = null
    private var scanCallback: ScanCallback? = null
    private var scanGeneration = 0
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var broadcastGeneration = 0
    private var pendingBroadcast: MethodChannel.Result? = null
    private var broadcastTimeout: Runnable? = null
    private var broadcastActive: Boolean? = null
    private var session = SecureRandom().nextInt().toLong() and BluetoothKillSwitchPacket.MAX_UNSIGNED_INT
    private var revision = 0L
    @Volatile private var closed = false

    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != BluetoothAdapter.ACTION_STATE_CHANGED ||
                intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR) != BluetoothAdapter.STATE_OFF) return
            main.post {
                if (closed) return@post
                val usingBluetooth = scanCallback != null || advertiseCallback != null
                stopReceiving()
                stopBroadcast("Bluetooth was turned off.")
                if (usingBluetooth) sink?.error("BLUETOOTH_DISABLED", "Turn Bluetooth on, then reconnect nearby control.", null)
            }
        }
    }

    init {
        if (Build.VERSION.SDK_INT >= 33) {
            appContext.registerReceiver(bluetoothStateReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED), Context.RECEIVER_EXPORTED)
        } else {
            appContext.registerReceiver(bluetoothStateReceiver, IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED))
        }
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        channel.setMethodCallHandler { call, result ->
            if (closed) {
                result.error("KILL_SWITCH_CLOSED", "Nearby controls are unavailable.", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "loadPreferences" -> preferencesResult(result) { preferences.getString("settings", null) }
                "savePreferences" -> {
                    val value = (call.arguments as? Map<*, *>)?.get("value") as? String
                    if (value == null) result.error("INVALID_ARGUMENT", "savePreferences expects a JSON string in value.", null)
                    else preferencesResult(result) {
                        JSONObject(value)
                        check(preferences.edit().putString("settings", value).commit())
                        null
                    }
                }
                "requestPermissions" -> requestPermissions(result)
                "startReceiving" -> radioResult(result) { startReceiving() }
                "stopReceiving" -> radioResult(result) { stopReceiving() }
                "broadcast" -> {
                    val active = call.arguments as? Boolean
                    if (active == null) result.error("INVALID_ARGUMENT", "broadcast expects a boolean.", null)
                    else try { broadcast(active, result) } catch (error: Exception) { radioError(result, error) }
                }
                "stopBroadcast" -> radioResult(result) { stopBroadcast("Nearby broadcasting stopped.") }
                else -> result.notImplemented()
            }
        }
    }

    private fun availableAdapter(): BluetoothAdapter {
        check(hasPermissions(appContext)) { "Allow Nearby devices permission to use Bluetooth control." }
        val adapter = (appContext.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
            ?: error("This device does not support Bluetooth.")
        check(adapter.isEnabled) { "Turn Bluetooth on to use nearby control." }
        return adapter
    }

    private fun startReceiving() {
        if (scanCallback != null) return
        val adapter = availableAdapter()
        if (Build.VERSION.SDK_INT < 31) {
            val location = appContext.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
            check(location?.isLocationEnabled == true) { "Turn Location on for Bluetooth discovery on this Android version." }
        }
        val currentScanner = adapter.bluetoothLeScanner ?: error("Bluetooth scanning is unavailable on this device.")
        val generation = ++scanGeneration
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) { receive(result, generation) }
            override fun onBatchScanResults(results: MutableList<ScanResult>) { results.forEach { receive(it, generation) } }
            override fun onScanFailed(errorCode: Int) {
                main.post {
                    if (closed || scanGeneration != generation) return@post
                    stopReceiving()
                    sink?.error("KILL_SWITCH_SCAN_FAILED", scanError(errorCode), null)
                }
            }
        }
        scanner = currentScanner
        scanCallback = callback
        try {
            val filter = ScanFilter.Builder().setServiceData(SERVICE_UUID, byteArrayOf(BluetoothKillSwitchPacket.VERSION.toByte())).build()
            val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).setReportDelay(0).build()
            currentScanner.startScan(listOf(filter), settings, callback)
        } catch (error: Exception) {
            stopReceiving()
            throw error
        }
    }

    private fun receive(result: ScanResult, generation: Int) {
        val bytes = result.scanRecord?.getServiceData(SERVICE_UUID) ?: return
        val packet = BluetoothKillSwitchPacket.decode(bytes) ?: return
        main.post {
            if (!closed && scanCallback != null && scanGeneration == generation) {
                sink?.success(mapOf(
                    "active" to packet.active,
                    "sender" to packet.sender,
                    "session" to packet.sender,
                    "revision" to packet.revision,
                ))
            }
        }
    }

    private fun stopReceiving() {
        scanGeneration++
        val currentScanner = scanner
        val callback = scanCallback
        scanner = null
        scanCallback = null
        if (currentScanner != null && callback != null) runCatching { currentScanner.stopScan(callback) }
    }

    private fun broadcast(active: Boolean, result: MethodChannel.Result) {
        val adapter = availableAdapter()
        check(adapter.isMultipleAdvertisementSupported) { "This device cannot broadcast Bluetooth control. Use another phone." }
        val currentAdvertiser = adapter.bluetoothLeAdvertiser ?: error("Bluetooth advertising is unavailable on this device.")
        if (broadcastActive == active && advertiseCallback != null && pendingBroadcast == null) {
            result.success(null)
            return
        }
        stopBroadcast("Nearby broadcasting was replaced.")
        if (revision == BluetoothKillSwitchPacket.MAX_UNSIGNED_INT) {
            session = SecureRandom().nextInt().toLong() and BluetoothKillSwitchPacket.MAX_UNSIGNED_INT
            revision = 0
        }
        revision++
        val generation = broadcastGeneration
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                main.post {
                    if (closed || broadcastGeneration != generation || advertiseCallback !== this) {
                        runCatching { currentAdvertiser.stopAdvertising(this) }
                        return@post
                    }
                    broadcastActive = active
                    finishBroadcastSuccess()
                }
            }
            override fun onStartFailure(errorCode: Int) {
                main.post {
                    if (closed || broadcastGeneration != generation || advertiseCallback !== this) return@post
                    val pending = pendingBroadcast
                    pendingBroadcast = null
                    stopBroadcast("Nearby broadcasting failed.")
                    pending?.error("KILL_SWITCH_BROADCAST_FAILED", advertiseError(errorCode), null)
                }
            }
        }
        advertiser = currentAdvertiser
        advertiseCallback = callback
        pendingBroadcast = result
        val timeout = Runnable {
            if (closed || generation != broadcastGeneration || advertiseCallback !== callback) return@Runnable
            val pending = pendingBroadcast
            pendingBroadcast = null
            stopBroadcast("Bluetooth did not start broadcasting.")
            pending?.error("KILL_SWITCH_BROADCAST_TIMEOUT", "Bluetooth did not start broadcasting. Try reconnecting.", null)
        }
        broadcastTimeout = timeout
        main.postDelayed(timeout, 10_000)
        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .setConnectable(false)
            .setTimeout(0)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceData(SERVICE_UUID, BluetoothKillSwitchPacket(active, session, revision).encode())
            .build()
        try {
            currentAdvertiser.startAdvertising(settings, data, callback)
        } catch (error: Exception) {
            pendingBroadcast = null
            stopBroadcast("Nearby broadcasting failed.")
            throw error
        }
    }

    private fun finishBroadcastSuccess() {
        broadcastTimeout?.let { main.removeCallbacks(it) }
        broadcastTimeout = null
        val pending = pendingBroadcast
        pendingBroadcast = null
        pending?.success(null)
    }

    private fun stopBroadcast(reason: String) {
        broadcastGeneration++
        broadcastTimeout?.let { main.removeCallbacks(it) }
        broadcastTimeout = null
        val callback = advertiseCallback
        val currentAdvertiser = advertiser
        advertiseCallback = null
        advertiser = null
        broadcastActive = null
        val pending = pendingBroadcast
        pendingBroadcast = null
        if (currentAdvertiser != null && callback != null) runCatching { currentAdvertiser.stopAdvertising(callback) }
        pending?.error("KILL_SWITCH_BROADCAST_CANCELLED", reason, null)
    }

    private fun radioResult(result: MethodChannel.Result, operation: () -> Unit) {
        try { operation(); result.success(null) } catch (error: Exception) { radioError(result, error) }
    }

    private fun radioError(result: MethodChannel.Result, error: Exception) {
        val message = when (error) {
            is SecurityException -> "Allow Nearby devices permission to use Bluetooth control."
            is IllegalStateException -> error.message ?: "Bluetooth control is unavailable."
            else -> "Bluetooth control could not start. Turn Bluetooth on, then reconnect."
        }
        result.error("KILL_SWITCH_BLUETOOTH_ERROR", message, null)
    }

    private fun preferencesResult(result: MethodChannel.Result, operation: () -> Any?) {
        try {
            executor.execute {
                val outcome = runCatching(operation)
                main.post {
                    if (!closed) outcome.fold(
                        onSuccess = { result.success(it) },
                        onFailure = { error ->
                            if (error is JSONException) result.error("INVALID_ARGUMENT", "Preferences must be a valid JSON object.", null)
                            else result.error("KILL_SWITCH_PREFERENCES_ERROR", "Could not access nearby control settings.", null)
                        },
                    )
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("KILL_SWITCH_CLOSED", "Nearby controls are unavailable.", null)
        }
    }

    fun close() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        events.setStreamHandler(null)
        sink = null
        runCatching { appContext.unregisterReceiver(bluetoothStateReceiver) }
        stopReceiving()
        stopBroadcast("Nearby controls closed.")
        executor.shutdown()
    }

    companion object {
        val SERVICE_UUID: ParcelUuid = ParcelUuid(UUID.fromString("625f9fb1-6609-4a1b-9b0c-0ac291e34d91"))

        fun requiredPermissions(): Array<String> = if (Build.VERSION.SDK_INT >= 31) arrayOf(
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

        fun hasPermissions(context: Context): Boolean = requiredPermissions().all {
            context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }

        private fun scanError(code: Int): String = when (code) {
            ScanCallback.SCAN_FAILED_FEATURE_UNSUPPORTED -> "This device does not support Bluetooth scanning."
            ScanCallback.SCAN_FAILED_SCANNING_TOO_FREQUENTLY -> "Bluetooth discovery restarted too often. Wait a moment, then reconnect."
            else -> "Bluetooth discovery could not start. Turn Bluetooth on, then reconnect."
        }

        private fun advertiseError(code: Int): String = when (code) {
            AdvertiseCallback.ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "This phone cannot broadcast Bluetooth control."
            AdvertiseCallback.ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Bluetooth is busy. Close other nearby-sharing apps, then reconnect."
            AdvertiseCallback.ADVERTISE_FAILED_DATA_TOO_LARGE -> "Bluetooth control could not fit its broadcast message."
            else -> "Bluetooth broadcasting could not start. Turn Bluetooth on, then reconnect."
        }
    }
}
