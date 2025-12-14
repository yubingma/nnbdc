Pod::Spec.new do |s|
  s.name         = 'WechatOpenSDK-XCFramework'
  s.version      = '2.0.5'
  s.summary      = '微信 OpenSDK 二进制 XCFramework（用于 fluwx）'
  s.description  = '用于 fluwx 的 WechatOpenSDK XCFramework。默认下载地址为腾讯官方域名；在 CI（如 Xcode Cloud）可通过环境变量替换为可访问镜像。'
  s.homepage     = 'https://open.weixin.qq.com/'
  s.license      = { :type => 'Proprietary' }
  s.author       = { 'Tencent' => 'https://open.weixin.qq.com/' }

  s.platform     = :ios, '12.0'

  # 默认使用官方地址；在 Xcode Cloud 等环境中如遇 DNS/网络限制，请设置 WECHAT_OPENSDK_ZIP_URL 指向可访问镜像
  zip_url = ENV['WECHAT_OPENSDK_ZIP_URL']
  if zip_url.nil? || zip_url.strip.empty?
    zip_url = 'https://dldir1.qq.com/WechatWebDev/opensdk/XCFramework/OpenSDK2.0.5.zip'
  end

  s.source = { :http => zip_url }

  # OpenSDK2.0.5.zip 解压后包含 WechatOpenSDK.xcframework
  s.vendored_frameworks = 'WechatOpenSDK.xcframework'

  # 参考 CocoaPods 安装后的 xcconfig（保持链接参数一致）
  s.libraries = 'c++', 'sqlite3.0', 'z'
  s.frameworks = 'CoreGraphics', 'Security', 'UIKit', 'WebKit'
end


