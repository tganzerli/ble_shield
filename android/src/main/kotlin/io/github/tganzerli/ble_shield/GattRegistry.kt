package io.github.tganzerli.ble_shield

import android.bluetooth.BluetoothGatt
import java.util.concurrent.ConcurrentHashMap

/**
 * GATT clients owned by one [BleShieldPlugin]. This must stay per plugin
 * instance (one per FlutterEngine) rather than process-wide: a `connect()` must
 * not reuse a client whose callbacks are wired to another (possibly destroyed)
 * engine, and detaching one engine must release only its own clients.
 */
internal class GattRegistry {
    private val clients = ConcurrentHashMap<String, BluetoothGatt>()

    fun find(deviceId: String): BluetoothGatt? = clients[deviceId]

    fun isKnown(deviceId: String): Boolean = find(deviceId) != null

    fun get(deviceId: String): BluetoothGatt =
        find(deviceId) ?: throw createFlutterError(
            BleShieldNativeErrorCode.DEVICE_NOT_FOUND,
            "Unknown deviceId: $deviceId",
        )

    /** Registers [gatt] and returns the client it replaced for the same address, if any. */
    fun put(gatt: BluetoothGatt): BluetoothGatt? = clients.put(gatt.device.address, gatt)

    /**
     * Removes [gatt] only while it is still the registered client; a newer
     * `connect()` may have replaced it for the same address.
     */
    fun remove(gatt: BluetoothGatt) {
        clients.remove(gatt.device.address, gatt)
    }

    /** Snapshot of the registered clients, safe to iterate while releasing them. */
    fun snapshot(): List<BluetoothGatt> = clients.values.toList()
}
