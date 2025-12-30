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
  # Note: Add dependency on synheart-behavior-ios SDK when available
  # s.dependency 'SynheartBehavior', '~> 1.0'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end

