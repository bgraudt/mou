#!/usr/bin/env ruby
# Генерирует Mou.xcodeproj (iOS-приложение, SwiftUI).
require 'xcodeproj'

root = File.dirname(File.expand_path(__FILE__))
proj_path = File.join(root, 'Mou.xcodeproj')
require 'fileutils'; FileUtils.rm_rf(proj_path)

project = Xcodeproj::Project.new(proj_path)
target = project.new_target(:application, 'Mou', :ios, '17.0')

group = project.main_group.new_group('Mou', 'Mou')

# Swift-исходники
Dir.glob(File.join(root, 'Mou', '*.swift')).sort.each do |f|
  ref = group.new_reference(f)
  target.add_file_references([ref])
end

# Ресурсы (JSON + изображения)
res_group = group.new_group('Resources', 'Mou/Resources')
Dir.glob(File.join(root, 'Mou', 'Resources', '*')).select { |f| File.file?(f) }.sort.each do |f|
  ref = res_group.new_reference(f)
  target.add_resources([ref])
end

# Настройки сборки
target.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.mou.valencia'
  bs['PRODUCT_NAME'] = 'Mou'
  bs['MARKETING_VERSION'] = '0.1'
  bs['CURRENT_PROJECT_VERSION'] = '1'
  bs['GENERATE_INFOPLIST_FILE'] = 'YES'
  bs['INFOPLIST_KEY_UILaunchScreen_Generation'] = 'YES'
  bs['INFOPLIST_KEY_CFBundleDisplayName'] = 'Mou'
  bs['INFOPLIST_KEY_UISupportedInterfaceOrientations'] = 'UIInterfaceOrientationPortrait'
  bs['INFOPLIST_KEY_NSLocationWhenInUseUsageDescription'] = 'Per a mostrar la teua posició al mapa i les parades més pròximes.'
  bs['SWIFT_VERSION'] = '5.0'
  bs['TARGETED_DEVICE_FAMILY'] = '1'
  bs['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  # подпись под реальное устройство (личная команда разработчика)
  bs['DEVELOPMENT_TEAM'] = 'H237LXJ3U6'
  bs['CODE_SIGN_STYLE'] = 'Automatic'
  bs['CODE_SIGN_IDENTITY'] = 'Apple Development'
end

project.save

# общая схема, чтобы xcodebuild видел таргет
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.save_as(proj_path, 'Mou', true)

puts "wrote #{proj_path}"
