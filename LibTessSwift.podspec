#
# Be sure to run `pod lib lint LibTessSwift.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'LibTessSwift'
  s.version          = '0.4.3'
  s.summary          = 'A Tesselation/Triangulation Library Written in Swift.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
A Tesselation/triangulation library for Swift.

Based on LibTess2 (https://github.com/memononen/Libtess2), with a nice Swift wrapper API on top.
                       DESC

  s.homepage         = 'https://github.com/LuizZak/LibTessSwift'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'LuizZak' => 'luizinho_mack@yahoo.com.br' }
  s.source           = { :git => 'https://github.com/LuizZak/LibTessSwift.git', :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/LuizZak'

  s.ios.deployment_target = '8.0'

  s.xcconfig = { 'SWIFT_INCLUDE_PATHS' => '$(SRCROOT)/LibTessSwift/LibTessSwift/libtess2/**' }
  s.pod_target_xcconfig = { 'SWIFT_INCLUDE_PATHS' => '$(SRCROOT)/LibTessSwift/LibTessSwift/libtess2/**' }
  s.source_files = 'LibTessSwift/**/*{swift,h,c}'
#s.preserve_paths = 'LibTessSwift/libtess2/module.modulemap'
end
