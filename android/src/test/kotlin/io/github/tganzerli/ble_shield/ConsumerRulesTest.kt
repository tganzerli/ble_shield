package io.github.tganzerli.ble_shield

import android.bluetooth.BluetoothGattCallback
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/*
 * android/consumer-rules.pro keeps BleShieldPlugin.onConnectionUpdated, a @hide
 * BluetoothGattCallback method the plugin implements without `override`. The code
 * shrinker strips it otherwise, and ShieldDevice.connectionParameters never emits in release builds.
 * A keep rule names the method by text, so a rename or a signature change would
 * silently stop matching: these tests tie each kept member to the real class.
 */
internal class ConsumerRulesTest {
    private val pluginClass = "io.github.tganzerli.ble_shield.BleShieldPlugin"

    /** Unit tests run with the module directory (android/) as the working directory. */
    private fun rules(): String = File("consumer-rules.pro").readText()

    /** Member lines of the `-keepclassmembers class BleShieldPlugin { ... }` block. */
    private fun keptMembers(): List<String> {
        val block = Regex(
            """-keepclassmembers\s+class\s+${Regex.escape(pluginClass)}\s*\{([^}]*)\}"""
        ).find(rules())
        assertTrue(block != null, "consumer-rules.pro has no -keepclassmembers block for $pluginClass")
        return block.groupValues[1].lines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") }
    }

    private fun jvmType(name: String): Class<*> = when (name) {
        "int" -> Int::class.javaPrimitiveType!!
        "long" -> Long::class.javaPrimitiveType!!
        "boolean" -> Boolean::class.javaPrimitiveType!!
        "void" -> Void.TYPE
        else -> Class.forName(name)
    }

    @Test
    fun `every kept member exists on BleShieldPlugin with the declared signature`() {
        val members = keptMembers()
        assertTrue(members.isNotEmpty())
        val pattern = Regex("""public\s+(\S+)\s+(\w+)\(([^)]*)\);""")
        for (line in members) {
            val match = pattern.matchEntire(line)
            assertTrue(match != null, "unexpected rule line: $line")
            val (returnType, name, params) = match.destructured
            val types = params.split(',').map { it.trim() }.filter { it.isNotEmpty() }
                .map(::jvmType).toTypedArray()
            val method = BleShieldPlugin::class.java.getMethod(name, *types)
            assertEquals(jvmType(returnType), method.returnType, line)
        }
    }

    @Test
    fun `build gradle ships consumer-rules pro in the AAR`() {
        // Without this line the rules file is never packaged and the tests above
        // would stay green while release builds lose the callback again.
        val gradle = File("build.gradle").readText()
        assertTrue(
            Regex("""consumerProguardFiles\s+['"]consumer-rules\.pro['"]""").containsMatchIn(gradle),
            "android/build.gradle does not declare consumerProguardFiles 'consumer-rules.pro'",
        )
    }

    @Test
    fun `onConnectionUpdated is kept and is not an override of the public android jar`() {
        assertTrue(keptMembers().any { it.contains(" onConnectionUpdated(") })
        // If the public SDK ever exposes it, the method becomes an override and the shrinker
        // keeps it on its own; until then the rule is what keeps it alive.
        assertFailsWith<NoSuchMethodException> {
            BluetoothGattCallback::class.java.getDeclaredMethod(
                "onConnectionUpdated",
                android.bluetooth.BluetoothGatt::class.java,
                Int::class.javaPrimitiveType, Int::class.javaPrimitiveType,
                Int::class.javaPrimitiveType, Int::class.javaPrimitiveType,
            )
        }
    }
}
