package io.github.tganzerli.ble_shield

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanSettings
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.LinkedList

private const val NUM_SCAN_DURATIONS_KEPT = 5
private const val EXCESSIVE_SCANNING_PERIOD_MS = 30 * 1000L
private const val TAG = "BleShieldPlugin"

/**
 * A safe wrapper for Bluetooth LE scanning operations that prevents excessive scanning.
 *
 * This class manages BLE scanning while adhering to Android's scanning frequency limits by:
 * - Tracking scan start times over a 30-second window
 * - Limiting to 5 scan operations within this window
 * - Automatically scheduling delayed scans when frequency limits are exceeded
 * - Providing safe start/stop scan operations with error handling
 *
 * The scanner will automatically delay new scan requests if the frequency limit is reached,
 * and will retry once sufficient time has passed. This helps prevent scan failure errors
 * and ensures compliance with Android's scanning restrictions.
 *
 * @property bluetoothManager The system's BluetoothManager used for scanning operations
 * @property handler Runs the delayed retry; injectable for unit tests
 * @property reportsThrottle Whether a throttled start is reported as SCANNING_TOO_FREQUENTLY
 *   (Android 13+, matching the platform); injectable for unit tests
 */
@SuppressLint("MissingPermission")
class SafeScanner(
    private val bluetoothManager: BluetoothManager,
    private val handler: Handler = Handler(Looper.myLooper()!!),
    private val reportsThrottle: Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU,
) {
    private val startTimes = LinkedList<Long>()
    private var awaitingScan = false
    private var isScanning = false

    fun startScan(filters: List<ScanFilter>, settings: ScanSettings, callback: ScanCallback) {
        val now = System.currentTimeMillis()
        startTimes.removeAll { now - it > EXCESSIVE_SCANNING_PERIOD_MS }

        if (startTimes.size >= NUM_SCAN_DURATIONS_KEPT) {
            if (awaitingScan) {
                Log.e(TAG, "startScan: too frequent, awaiting scan..")
                return
            }

            // Set before reporting, so the callback can tell this throttle from a real failure.
            awaitingScan = true
            if (reportsThrottle) {
                callback.onScanFailed(ScanCallback.SCAN_FAILED_SCANNING_TOO_FREQUENTLY)
            }

            val delay = startTimes.first() + EXCESSIVE_SCANNING_PERIOD_MS - now + 2_000
            Log.e(TAG, "startScan: too frequent, schedule auto-start after $delay ms $startTimes")

            handler.postDelayed({
                Log.d(TAG, "Retrying scan after delay")
                awaitingScan = false
                startScan(filters, settings, callback)
            }, delay)
        } else {
            awaitingScan = false
            startTimes.addLast(now)
            try {
                bluetoothManager.adapter.bluetoothLeScanner?.startScan(filters, settings, callback)
                isScanning = true
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start Scan : $e")
                isScanning = false
                // Report it instead of leaving the caller with a scan that never runs.
                callback.onScanFailed(ScanCallback.SCAN_FAILED_INTERNAL_ERROR)
            }
        }
    }

    fun stopScan(callback: ScanCallback) {
        awaitingScan = false
        handler.removeCallbacksAndMessages(null)
        bluetoothManager.adapter.bluetoothLeScanner?.stopScan(callback)
        isScanning = false
    }

    /** A throttled start is scheduled to retry by itself. */
    fun isRetryPending(): Boolean = awaitingScan

    fun isScanning(): Boolean {
        return isScanning || awaitingScan
    }
}