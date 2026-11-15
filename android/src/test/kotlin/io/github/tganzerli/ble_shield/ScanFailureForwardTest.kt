package io.github.tganzerli.ble_shield

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanSettings
import android.os.Handler
import android.util.Log
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyList
import org.mockito.ArgumentMatchers.anyLong
import org.mockito.MockedStatic
import org.mockito.Mockito

/*
 * A real scanner failure reaches Dart through the Pigeon onScanFailed, so
 * ble_shield can end the scan session instead of relying on a watchdog. The
 * SCANNING_TOO_FREQUENTLY that SafeScanner reports for its own throttle is not
 * a failure: the scan retries by itself. These tests drive the real SafeScanner
 * wired to the plugin's ScanCallback, so the ordering contract between
 * SafeScanner (awaitingScan set before the report) and the callback
 * (isRetryPending) is exercised, not mocked.
 */
internal class ScanFailureForwardTest {
    private val scanFailures = mutableListOf<Long>()
    private val callbackChannel: BleShieldNativeCallbackChannel =
        Mockito.mock(BleShieldNativeCallbackChannel::class.java) { invocation ->
            if (invocation.method.name == "onScanFailed") {
                scanFailures.add(invocation.arguments[0] as Long)
            }
            null
        }

    private val leScanner: BluetoothLeScanner = Mockito.mock(BluetoothLeScanner::class.java)
    private val settings: ScanSettings = Mockito.mock(ScanSettings::class.java)
    private val filters = emptyList<ScanFilter>()

    // The retry SafeScanner schedules; never run unless a test asks.
    private val retryHandler: Handler = Mockito.mock(Handler::class.java)

    // SafeScanner logs through android.util.Log, which the unit-test android.jar does not implement.
    private lateinit var log: MockedStatic<Log>

    @BeforeTest
    fun mockLog() {
        log = Mockito.mockStatic(Log::class.java)
    }

    @AfterTest
    fun releaseLog() {
        log.close()
    }

    private fun plugin(): Pair<BleShieldPlugin, SafeScanner> {
        val plugin = BleShieldPlugin()
        val mainHandler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { invocation ->
            invocation.getArgument<Runnable>(0).run()
            true
        }.`when`(mainHandler).post(any())
        plugin.setField("mainThreadHandler", mainHandler)
        plugin.setField("callbackChannel", callbackChannel)

        val adapter = Mockito.mock(BluetoothAdapter::class.java)
        Mockito.`when`(adapter.bluetoothLeScanner).thenReturn(leScanner)
        val manager = Mockito.mock(BluetoothManager::class.java)
        Mockito.`when`(manager.adapter).thenReturn(adapter)
        Mockito.`when`(retryHandler.postDelayed(any(), anyLong())).thenReturn(true)

        val scanner = SafeScanner(manager, retryHandler, reportsThrottle = true)
        plugin.setField("safeScanner", scanner)
        return plugin to scanner
    }

    private fun BleShieldPlugin.scanCallback(): ScanCallback = getField("scanCallback")

    @Test
    fun platformScanFailureReachesDart() {
        val (plugin, _) = plugin()

        plugin.scanCallback().onScanFailed(ScanCallback.SCAN_FAILED_INTERNAL_ERROR)

        assertEquals(listOf(ScanCallback.SCAN_FAILED_INTERNAL_ERROR.toLong()), scanFailures)
    }

    @Test
    fun anExceptionStartingTheScanReachesDart() {
        val (plugin, scanner) = plugin()
        Mockito.`when`(leScanner.startScan(anyList(), any(ScanSettings::class.java), any(ScanCallback::class.java)))
            .thenThrow(IllegalStateException("BT adapter is not turned ON"))

        scanner.startScan(filters, settings, plugin.scanCallback())

        assertEquals(listOf(ScanCallback.SCAN_FAILED_INTERNAL_ERROR.toLong()), scanFailures)
        assertFalse(scanner.isScanning())
    }

    @Test
    fun throttledStartIsNotAFailureForDart() {
        val (plugin, scanner) = plugin()
        repeat(5) { scanner.startScan(filters, settings, plugin.scanCallback()) }
        assertTrue(scanFailures.isEmpty())

        // The sixth start inside 30 s is throttled: SafeScanner reports
        // SCANNING_TOO_FREQUENTLY and schedules its own retry.
        scanner.startScan(filters, settings, plugin.scanCallback())

        assertTrue(scanner.isRetryPending())
        Mockito.verify(retryHandler).postDelayed(any(), anyLong())
        assertTrue(scanFailures.isEmpty(), "the throttle report must not end the Dart session")
    }

    @Test
    fun systemScanningTooFrequentlyWithoutAPendingRetryReachesDart() {
        val (plugin, scanner) = plugin()
        assertFalse(scanner.isRetryPending())

        plugin.scanCallback().onScanFailed(ScanCallback.SCAN_FAILED_SCANNING_TOO_FREQUENTLY)

        assertEquals(listOf(ScanCallback.SCAN_FAILED_SCANNING_TOO_FREQUENTLY.toLong()), scanFailures)
    }
}
