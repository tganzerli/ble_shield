package io.github.tganzerli.ble_shield

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.os.Handler
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.Mockito

/*
 * Every successful MTU reaches Dart through the Pigeon onMtuChanged, requested
 * or not: Android 14+ negotiates on its own after connecting, and that value
 * used to stay in the plugin's cache. A failed negotiation and a stale client
 * report nothing.
 */
internal class MtuPushTest {
    private val address = "AA:BB:CC:DD:EE:FF"
    private val pushed = mutableListOf<Pair<String, Long>>()
    private val callbackChannel: BleShieldNativeCallbackChannel =
        Mockito.mock(BleShieldNativeCallbackChannel::class.java) { invocation ->
            if (invocation.method.name == "onMtuChanged") {
                pushed.add(invocation.arguments[0] as String to invocation.arguments[1] as Long)
            }
            null
        }
    private val plugin = BleShieldPlugin().also {
        val handler = Mockito.mock(Handler::class.java)
        Mockito.doAnswer { call ->
            call.getArgument<Runnable>(0).run()
            true
        }.`when`(handler).post(Mockito.any())
        it.setField("mainThreadHandler", handler)
        it.setField("callbackChannel", callbackChannel)
    }

    private fun gatt(register: Boolean = true): BluetoothGatt {
        val device = Mockito.mock(BluetoothDevice::class.java)
        Mockito.`when`(device.address).thenReturn(address)
        return Mockito.mock(BluetoothGatt::class.java).also {
            Mockito.`when`(it.device).thenReturn(device)
            Mockito.`when`(it.requestMtu(Mockito.anyInt())).thenReturn(true)
            if (register) plugin.gattRegistry().put(it)
        }
    }

    @AfterTest
    fun clearConnections() {
        plugin.gattRegistry().snapshot().forEach { plugin.gattRegistry().remove(it) }
    }

    @Test
    fun unsolicitedMtuIsPushed() {
        val gatt = gatt()
        plugin.onMtuChanged(gatt, 517, BluetoothGatt.GATT_SUCCESS)
        assertEquals(listOf(address to 517L), pushed)
    }

    @Test
    fun requestedMtuIsPushedAndStillAnswersTheRequest() {
        val gatt = gatt()
        val values = mutableListOf<Result<Long>>()
        plugin.requestMtu(address, 247L) { values.add(it) }
        plugin.onMtuChanged(gatt, 247, BluetoothGatt.GATT_SUCCESS)
        assertEquals(listOf(address to 247L), pushed)
        assertEquals(247L, values.single().getOrThrow())
    }

    @Test
    fun failedNegotiationIsNotPushed() {
        val gatt = gatt()
        plugin.onMtuChanged(gatt, 23, BluetoothGatt.GATT_FAILURE)
        assertTrue(pushed.isEmpty())
    }

    @Test
    fun staleClientIsNotPushed() {
        gatt()
        val stale = gatt(register = false)
        plugin.onMtuChanged(stale, 247, BluetoothGatt.GATT_SUCCESS)
        assertTrue(pushed.isEmpty())
    }
}
