#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint synheart_behavior.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'synheart_behavior'
  s.version          = '1.0.0'
  s.summary          = 'A lightweight, privacy-preserving mobile SDK for behavioral signal collection'
  s.description      = <<-DESC
The Synheart Behavioral SDK collects digital behavioral signals from smartphones without collecting any text, content, or PII - only timing-based signals.
                       DESC
  s.homepage         = 'https://github.com/synheart-ai/synheart-behavior-dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Israel Goytom' => 'israel@synheart.ai' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Synheart Flux (Rust) XCFramework for HSI-compliant behavioral metrics
  # REQUIRED: The XCFramework must be placed at: ios/Frameworks/SynheartFlux.xcframework
  # Download from synheart-flux releases or build from source
  s.vendored_frameworks = 'Frameworks/SynheartFlux.xcframework'
  s.preserve_paths = 'Frameworks/SynheartFlux.xcframework'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # Link synheart-flux static library from XCFramework
    # Use -force_load to ensure all symbols are included from the static library
    # For simulator, use the simulator slice; for device, use the device slice
    'OTHER_LDFLAGS[sdk=iphonesimulator*]' => [
      '-L$(PODS_TARGET_SRCROOT)/Frameworks/SynheartFlux.xcframework/ios-arm64_x86_64-simulator',
      '-force_load $(PODS_TARGET_SRCROOT)/Frameworks/SynheartFlux.xcframework/ios-arm64_x86_64-simulator/libsynheart_flux.a'
    ].join(' '),
    'OTHER_LDFLAGS[sdk=iphoneos*]' => [
      '-L$(PODS_TARGET_SRCROOT)/Frameworks/SynheartFlux.xcframework/ios-arm64',
      '-force_load $(PODS_TARGET_SRCROOT)/Frameworks/SynheartFlux.xcframework/ios-arm64/libsynheart_flux.a'
    ].join(' ')
  }
  s.swift_version = '5.0'
end

