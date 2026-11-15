#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ble_shield.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ble_shield'
  s.version          = '0.0.1'
  s.summary          = 'Native layer of ble_shield, a defensive BLE central for Flutter.'
  s.description      = <<-DESC
CoreBluetooth central for ble_shield. Derived from universal_ble 3.2.0 (BSD 3-Clause); see NOTICE.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'ble_shield/Sources/ble_shield/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.1'
  s.osx.deployment_target = '10.15'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'
end
