Pod::Spec.new do |s|
  s.name             = 'inappify_sdk'
  s.version          = '0.2.7'
  s.summary          = 'Inappify Flutter SDK for offerings, entitlements and purchases.'
  s.description      = 'Flutter integration with the Inappify Kotlin SDK on Android, Dart V2 on iOS, and the Inappify JavaScript SDK on Web.'
  s.homepage         = 'https://github.com/InappifyLabs/flutter-sdk'
  s.license          = { :type => 'Apache-2.0', :file => '../LICENSE' }
  s.author           = 'InappifyLabs'
  s.source           = { :git => 'https://github.com/InappifyLabs/flutter-sdk.git', :tag => 'v0.2.7' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform        = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
