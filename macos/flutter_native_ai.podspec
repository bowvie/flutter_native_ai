#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_native_ai.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_native_ai'
  s.version          = '0.1.1'
  s.summary          = 'A Flutter plugin for on-device text generation with native platform AI models.'
  s.description      = <<-DESC
A Flutter plugin for on-device text generation with native platform AI models.
                       DESC
  s.homepage         = 'https://github.com/bowvie/flutter_native_ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'BowVie' => 'info@bowvie.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.resource_bundles = {
    'flutter_native_ai_privacy' => ['Classes/PrivacyInfo.xcprivacy']
  }
end