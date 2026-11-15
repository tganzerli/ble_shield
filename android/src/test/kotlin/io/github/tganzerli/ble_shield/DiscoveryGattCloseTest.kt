package io.github.tganzerli.ble_shield

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.content.Context
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.mockito.ArgumentCaptor
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyBoolean
import org.mockito.Mockito

/*
 * systemDevices(withServices) discovers the services of a device this engine
 * has no client for by opening a discovery-only GATT client. That client is
 * never registered, so nothing else would close it: it must be closed on every
 * path, or it stays behind as an extra client for the device.
 */
internal class DiscoveryGattCloseTest {
    private val address = "AA:BB:CC:DD:EE:FF"
    private val device: BluetoothDevice = Mockito.mock(BluetoothDevice::class.java).also {
        Mockito.`when`(it.address).thenReturn(address)
    }
    private val discoveryGatt: BluetoothGatt = Mockito.mock(BluetoothGatt::class.java).also {
        Mockito.`when`(it.device).thenReturn(device)
    }
    private val results = mutableListOf<List<String>?>()

    /** Starts the discovery and returns the callback of the discovery-only client. */
    private fun startDiscovery(): BluetoothGattCallback {
        val plugin = BleShieldPlugin()
        plugin.setField("context", Mockito.mock(Context::class.java))
        val captor = ArgumentCaptor.forClass(BluetoothGattCallback::class.java)
        // Unit tests run with SDK_INT 0: the pre-M connectGatt overload.
        Mockito.`when`(device.connectGatt(any(Context::class.java), anyBoolean(), captor.capture()))
            .thenReturn(discoveryGatt)

        val method = BleShieldPlugin::class.java.getDeclaredMethod(
            "discoverServicesOffAlreadyConnectedDevice",
            BluetoothDevice::class.java,
            Function1::class.java,
        )
        method.isAccessible = true
        method.invoke(plugin, device, { uuids: List<String>? -> results.add(uuids); Unit })
        return captor.value
    }

    @Test
    fun aFailedConnectionClosesTheDiscoveryClient() {
        val callback = startDiscovery()

        callback.onConnectionStateChange(
            discoveryGatt, BluetoothGatt.GATT_FAILURE, BluetoothGatt.STATE_DISCONNECTED
        )

        Mockito.verify(discoveryGatt).disconnect()
        Mockito.verify(discoveryGatt).close()
        assertEquals(listOf<List<String>?>(null), results)
    }

    @Test
    fun aDiscoveryThatCannotStartClosesTheDiscoveryClient() {
        val callback = startDiscovery()
        Mockito.`when`(discoveryGatt.discoverServices()).thenReturn(false)

        callback.onConnectionStateChange(
            discoveryGatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_CONNECTED
        )

        Mockito.verify(discoveryGatt).close()
        assertNull(results.single())
    }

    @Test
    fun theDiscoveryResultClosesTheDiscoveryClient() {
        val callback = startDiscovery()
        Mockito.`when`(discoveryGatt.discoverServices()).thenReturn(true)
        callback.onConnectionStateChange(
            discoveryGatt, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_CONNECTED
        )
        Mockito.verify(discoveryGatt, Mockito.never()).close()

        // A failed discovery status skips the service cache (SharedPreferences).
        callback.onServicesDiscovered(discoveryGatt, BluetoothGatt.GATT_FAILURE)

        Mockito.verify(discoveryGatt).close()
    }
}
