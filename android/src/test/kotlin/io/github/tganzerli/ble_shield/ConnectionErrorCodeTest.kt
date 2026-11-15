package io.github.tganzerli.ble_shield

import android.bluetooth.BluetoothGatt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/*
 * The GATT status of onConnectionStateChange is delivered to Dart twice: as the
 * unified BleShieldNativeErrorCode and as the raw value (nativeErrorCode).
 */
internal class ConnectionErrorCodeTest {

    @Test
    fun successHasNoCodes() {
        assertNull(BluetoothGatt.GATT_SUCCESS.toGattErrorCode())
        assertNull(BluetoothGatt.GATT_SUCCESS.toConnectionErrorCode())
    }

    @Test
    fun rawCodeIsPassedThrough() {
        assertEquals(0x08L, 0x08.toGattErrorCode())
        assertEquals(257L, BluetoothGatt.GATT_FAILURE.toGattErrorCode())
    }

    @Test
    fun timeoutCodesMapToConnectionTimeout() {
        assertEquals(BleShieldNativeErrorCode.CONNECTION_TIMEOUT, 0x08.toConnectionErrorCode())
        assertEquals(BleShieldNativeErrorCode.CONNECTION_TIMEOUT, 0x93.toConnectionErrorCode())
    }

    @Test
    fun peerDisconnectCodesMapToDeviceDisconnected() {
        assertEquals(BleShieldNativeErrorCode.DEVICE_DISCONNECTED, 0x13.toConnectionErrorCode())
        assertEquals(
            BleShieldNativeErrorCode.DEVICE_DISCONNECTED,
            BluetoothGatt.GATT_FAILURE.toConnectionErrorCode()
        )
    }

    @Test
    fun localTerminationMapsToConnectionTerminated() {
        assertEquals(BleShieldNativeErrorCode.CONNECTION_TERMINATED, 0x16.toConnectionErrorCode())
    }

    @Test
    fun establishmentFailuresMapToConnectionFailed() {
        assertEquals(BleShieldNativeErrorCode.CONNECTION_FAILED, 0x3E.toConnectionErrorCode())
        assertEquals(BleShieldNativeErrorCode.CONNECTION_FAILED, 0x85.toConnectionErrorCode())
        assertEquals(
            BleShieldNativeErrorCode.CONNECTION_FAILED,
            BluetoothGatt.GATT_CONNECTION_CONGESTED.toConnectionErrorCode()
        )
    }

    @Test
    fun hciLimitExistsAndRejectedReasonsMapToTheirEnumValues() {
        assertEquals(BleShieldNativeErrorCode.CONNECTION_LIMIT_EXCEEDED, 0x09.toConnectionErrorCode())
        assertEquals(BleShieldNativeErrorCode.CONNECTION_ALREADY_EXISTS, 0x0B.toConnectionErrorCode())
        assertEquals(BleShieldNativeErrorCode.CONNECTION_REJECTED, 0x0D.toConnectionErrorCode())
        assertEquals(BleShieldNativeErrorCode.CONNECTION_REJECTED, 0x0E.toConnectionErrorCode())
        assertEquals(BleShieldNativeErrorCode.CONNECTION_REJECTED, 0x0F.toConnectionErrorCode())
    }

    @Test
    fun anyFailureBeforeConnectIsConnectionFailed() {
        assertEquals(BleShieldNativeErrorCode.CONNECTION_FAILED, BluetoothGatt.GATT_FAILURE.toConnectionErrorCode(wasConnected = false))
        assertEquals(BleShieldNativeErrorCode.CONNECTION_FAILED, 0x08.toConnectionErrorCode(wasConnected = false))
        assertNull(BluetoothGatt.GATT_SUCCESS.toConnectionErrorCode(wasConnected = false))
        assertEquals(BleShieldNativeErrorCode.DEVICE_DISCONNECTED, BluetoothGatt.GATT_FAILURE.toConnectionErrorCode(wasConnected = true))
    }

    @Test
    fun otherCodesMapToUnknownError() {
        assertEquals(BleShieldNativeErrorCode.UNKNOWN_ERROR, 0x22.toConnectionErrorCode())
        assertEquals(BleShieldNativeErrorCode.UNKNOWN_ERROR, 0x3B.toConnectionErrorCode())
    }
}
