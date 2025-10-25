
手机调试常见问题：
手机不能访问电脑：手机WIFI网络设置中，有个“WLAN直连”，需要打开

ipad开发调试, 出现:
1. The Dart VM Service was not discovered after 60 seconds. This is taking much longer than expected...
Open the Xcode window the project is opened in to ensure the app is running. If the app is not running, try selecting "Product > Run" to fix the problem.
ipad数据线重新插拔一下, 就好了

2. Launching lib/main.dart on iPad in debug mode... Developer identity "Apple Development: mmyybb3000@icloud.com (8Z9GN4TMV8)" selected for iOS code signing Xcode build done. 60.6s Failed to build iOS app Could not build the precompiled application for the device. Uncategorized (Xcode): Timed out waiting for all destinations matching the provided destination specifier to become available 2 Ineligible destinations for the "Runner" scheme: { platform:iOS, arch:arm64, id:00008120-000A7C523EC2601E, name:iPad, error:Device is busy (Waiting to reconnect to iPad) } 2 Error launching application on iPad. Exited (1).
打开xcode, 在某个页面, 可以看到:
Previous preparation error: The developer disk image could not be mounted on this device.; Unable to contact Apple's activation servers to personalize the developer disk image.
然后停掉翻墙, 就好了, 似乎是不翻墙才能访问Apple's activation server 
(不确定是否需要打开xcode)

生产数据库导入到本地后:
bdc数据库sys_param在本机的特殊配置:
imgBaseDir	/opt/homebrew/opt/nginx/html/img
create database bdc CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;