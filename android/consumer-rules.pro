# Consumer ProGuard rules shipped with the ble_shield Android plugin. They are
# packaged in the AAR and applied by the app's code shrinker when it minifies a
# release build.

# BluetoothGattCallback.onConnectionUpdated is @hide (absent from the public
# android.jar), so BleShieldPlugin implements it without `override`. Nothing in
# the app calls it, and the shrinker would strip it: the framework would then
# call the empty base method and ShieldDevice.connectionParameters would never emit.
# Keep it unremoved and unrenamed. ConsumerRulesTest ties this line to the
# real signature.
-keepclassmembers class io.github.tganzerli.ble_shield.BleShieldPlugin {
    public void onConnectionUpdated(android.bluetooth.BluetoothGatt, int, int, int, int);
}
