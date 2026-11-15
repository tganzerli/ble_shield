package io.github.tganzerli.ble_shield

/**
 * Shared access to [BleShieldPlugin]'s private state for unit tests. Kept in
 * one place so a renamed field breaks a single helper instead of every test.
 */
internal fun BleShieldPlugin.setField(name: String, value: Any?) {
    val field = BleShieldPlugin::class.java.getDeclaredField(name)
    field.isAccessible = true
    field.set(this, value)
}

@Suppress("UNCHECKED_CAST")
internal fun <T> BleShieldPlugin.getField(name: String): T {
    val field = BleShieldPlugin::class.java.getDeclaredField(name)
    field.isAccessible = true
    return field.get(this) as T
}

internal fun BleShieldPlugin.gattRegistry(): GattRegistry = getField("gattRegistry")
