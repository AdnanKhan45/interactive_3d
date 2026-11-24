#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint interactive_3d.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'interactive_3d'
  s.version          = '2.6.0'
  s.summary          = 'A plugin to render interactive 3D model in .gLTF or .glb using Filament Engine'
  s.description      = <<-DESC
A plugin to render interactive 3D model in .gLTF or .glb
                       DESC
  s.homepage         = 'https://github.com/AdnanKhan45/interactive_3d/blob/main/lib/interactive_3d.dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Muhammad Adnan' => 'ak187429@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'interactive_3d/Sources/interactive_3d/**/*'
  s.dependency 'Flutter'
  s.dependency 'GLTFSceneKit', '~> 0.3.0'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
  'DEFINES_MODULE' => 'YES',
  'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'}

  s.swift_version = '5.0'
  # The manifest sits next to the Swift sources so Swift Package Manager bundles
  # it (see Package.swift); this path mirrors that layout.
  s.resource_bundles = {'interactive_3d_privacy' => ['interactive_3d/Sources/interactive_3d/PrivacyInfo.xcprivacy']}
end
