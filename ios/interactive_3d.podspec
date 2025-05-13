#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint interactive_3d.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'interactive_3d'
  s.version          = '0.0.2'
  s.summary          = 'A plugin to render interactive 3D model in .gLTF or .glb using Filament Engine'
  s.description      = <<-DESC
A plugin to render interactive 3D model in .gLTF or .glb
                       DESC
  s.homepage         = 'https://github.com/AdnanKhan45/interactive_3d/blob/main/lib/interactive_3d.dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Muhammad Adnan' => 'ak187429@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'GLTFSceneKit', '~> 0.3.0'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
  'DEFINES_MODULE' => 'YES',
  'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'}

  s.swift_version = '5.0'
  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'interactive_3d_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
