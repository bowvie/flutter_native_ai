#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_native_ai.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_native_ai'
  s.version          = '0.1.0-alpha.1'
  s.summary          = 'A Flutter plugin for on-device text generation with native platform AI models.'
  s.description      = <<-DESC
A Flutter plugin for on-device text generation with native platform AI models.
                       DESC
  s.homepage         = 'https://github.com/bowvie/flutter_native_ai'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'BowVie' => 'info@bowvie.com' }
  s.source           = { :path => '.' }
  s.source_files = 'flutter_native_ai/Sources/flutter_native_ai/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  s.resource_bundles = {'flutter_native_ai_privacy' => ['flutter_native_ai/Sources/flutter_native_ai/PrivacyInfo.xcprivacy']}
end
