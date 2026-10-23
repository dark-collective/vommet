Pod::Spec.new do |s|
  s.name             = 'vommet_hinge'
  s.version          = '0.1.0'
  s.summary          = 'Hinge state of foldable iPhones for Vommet.'
  s.description      = <<-DESC
Reports UIHingeInteraction updates (iOS 27.1+) to Dart over an event channel.
                       DESC
  s.homepage         = 'https://nether.codes/nether/vommet'
  s.license          = { :type => 'AGPL-3.0' }
  s.author           = { 'Vommet contributors' => 'https://nether.codes/nether/vommet' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
