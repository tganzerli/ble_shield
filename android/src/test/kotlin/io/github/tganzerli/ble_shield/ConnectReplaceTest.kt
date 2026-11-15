package io.github.tganzerli.ble_shield

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Handler
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyBoolean
import org.mockito.Mockito

/*
 * One GATT client per device. A connect() that finds a registered client
 * which is neither CONNECTED nor CONNECTING (a pending autoConnect, or a client
 * between connections) must not orphan it: it reuses a live autoConnect request
 * for a new autoConnect, and otherwise closes the old client before opening the
 * new one. Without this, a field test saw 2-4 clients per device.
 */
internal class ConnectReplaceTest {
    private val address = "AA:BB:CC:DD:EE:FF"

    private val connectionChanges = mutableListOf<List<Any?>>()
    private val callbackChannel: BleShieldNativeCallbackChannel =
        Mockito.mock(BleShieldNativeCallbackChannel::class.java) { invocation ->
            if (invocation.method.name == "onConnectionChanged") {
                connectionChanges.add(invocation.arguments.take(5))
            }
            null
        }

    private val remoteDevice: BluetoothDevice = Mockito.mock(BluetoothDevice::class.java).also {
        Mockito.`when`(it.address).thenReturn(address)
    }
    private val opened = mutableListOf<BluetoothGatt>()

    private fun plugin(osState: Int = BluetoothGatt.STATE_DISCONNECTED): BleShieldPlugin {
        val plugin = BleShieldPlugin()
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { invocation ->
            invocation.getArgument<Runnable>(0).run()
            true
        }.`when`(handler).post(any())
        plugin.setField("mainThreadHandler", handler)
        plugin.setField("callbackChannel", callbackChannel)
        plugin.setField("context", Mockito.mock(Context::class.java))

        val adapter = Mockito.mock(BluetoothAdapter::class.java)
        Mockito.`when`(adapter.getRemoteDevice(address)).thenReturn(remoteDevice)
        val manager = Mockito.mock(BluetoothManager::class.java)
        Mockito.`when`(manager.adapter).thenReturn(adapter)
        Mockito.`when`(manager.getConnectionState(any(BluetoothDevice::class.java), Mockito.eq(BluetoothProfile.GATT)))
            .thenReturn(osState)
        plugin.setField("bluetoothManager", manager)

        // Unit tests run with SDK_INT 0, so connect() takes the pre-M connectGatt overload.
        Mockito.`when`(
            remoteDevice.connectGatt(any(Context::class.java), anyBoolean(), any(BluetoothGattCallback::class.java))
        ).thenAnswer {
            mockGatt().also { opened.add(it) }
        }
        return plugin
    }

    private fun mockGatt(): BluetoothGatt {
        val gatt = Mockito.mock(BluetoothGatt::class.java)
        Mockito.`when`(gatt.device).thenReturn(remoteDevice)
        return gatt
    }

    private fun autoConnectDevices(plugin: BleShieldPlugin): MutableSet<String> =
        plugin.getField("autoConnectDevices")

    @Test
    fun connectClosesADisconnectedClientBeforeOpeningANewOne() {
        val plugin = plugin()
        val old = mockGatt()
        plugin.gattRegistry().put(old)

        plugin.connect(address, false, null)

        val order = Mockito.inOrder(old, remoteDevice)
        order.verify(old).disconnect()
        order.verify(old).close()
        order.verify(remoteDevice).connectGatt(any(Context::class.java), anyBoolean(), any(BluetoothGattCallback::class.java))
        assertEquals(1, opened.size)
        assertSame(opened.single(), plugin.gattRegistry().find(address))
    }

    @Test
    fun autoConnectReusesAPendingAutoConnectClient() {
        val plugin = plugin()
        val pending = mockGatt()
        plugin.gattRegistry().put(pending)
        autoConnectDevices(plugin).add(address)

        plugin.connect(address, true, null)

        assertTrue(opened.isEmpty())
        Mockito.verify(pending, Mockito.never()).close()
        assertSame(pending, plugin.gattRegistry().find(address))
        assertTrue(autoConnectDevices(plugin).contains(address))
    }

    @Test
    fun directConnectReplacesAPendingAutoConnectClient() {
        val plugin = plugin()
        val pending = mockGatt()
        plugin.gattRegistry().put(pending)
        autoConnectDevices(plugin).add(address)

        plugin.connect(address, false, null)

        Mockito.verify(pending).close()
        assertEquals(1, opened.size)
        assertSame(opened.single(), plugin.gattRegistry().find(address))
        assertTrue(autoConnectDevices(plugin).isEmpty())
    }

    @Test
    fun autoConnectReplacesANonAutoConnectClient() {
        // systemDevices adoption: connect() without autoConnect, then a drop and the
        // Dart auto-reconnect asking for autoConnect. The adopted client must not survive.
        val plugin = plugin()
        val adopted = mockGatt()
        plugin.gattRegistry().put(adopted)

        plugin.connect(address, true, null)

        Mockito.verify(adopted).close()
        assertSame(opened.single(), plugin.gattRegistry().find(address))
    }

    @Test
    fun connectedClientShortCircuitsWithoutANewClient() {
        val plugin = plugin(osState = BluetoothGatt.STATE_CONNECTED)
        val live = mockGatt()
        plugin.gattRegistry().put(live)

        plugin.connect(address, false, null)

        assertTrue(opened.isEmpty())
        Mockito.verify(live, Mockito.never()).close()
        assertEquals(listOf(listOf<Any?>(address, true, null, null, null)), connectionChanges)
    }

    @Test
    fun aLateEventFromAReplacedClientIsIgnored() {
        val plugin = plugin()
        val old = mockGatt()
        plugin.gattRegistry().put(old)
        plugin.connect(address, false, null)
        val current = opened.single()

        plugin.onConnectionStateChange(old, BluetoothGatt.GATT_FAILURE, BluetoothGatt.STATE_DISCONNECTED)
        plugin.onConnectionStateChange(old, BluetoothGatt.GATT_SUCCESS, BluetoothGatt.STATE_CONNECTED)

        assertTrue(connectionChanges.isEmpty())
        assertSame(current, plugin.gattRegistry().find(address))
    }

    @Test
    fun putReturnsTheReplacedClient() {
        val registry = GattRegistry()
        val first = mockGatt()
        val second = mockGatt()

        assertNull(registry.put(first))
        assertSame(first, registry.put(second))
    }
}
