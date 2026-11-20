# 离线缓存：UP 主文件夹

## 行为

- 同一 UP 主有两个及以上缓存稿件时，主页只显示一个文件夹；只有一个稿件时直接显示视频卡片。
- 文件夹使用列表首个实际视频的封面。封面右下角显示稿件数量，右侧以 UP 主名为标题，下方显示缓存总大小。
- 同一稿件的多个分 P 计为一个视频，所有分 P 的大小均计入总大小；重复 CID 不重复统计。
- 点击文件夹进入作者缓存列表，保留合集与分 P 层级、播放入口、多选、删除及更新操作。
- 新增或删除缓存后刷新封面、数量及大小。剩一个稿件时主页恢复原视频卡片，文件夹删空后显示空列表。
- 优先按 UP 主 ID 分组；同名不同 ID 不合并。没有 ID 时回退到作者名，完全缺失作者信息的缓存保留原卡片。
- 搜索覆盖全部缓存，支持标题、分 P 标题、作者名及合集作者名的部分匹配，忽略大小写和查询首尾空格。

该功能只组织界面展示，不移动缓存文件，不改变缓存文件格式。

## 验证

11 个聚焦测试覆盖混合普通视频/多分 P/合集的收纳、作者隔离、数量及总大小、首封面、实际卡片尺寸与大字体、主页到文件夹导航、单视频和空列表刷新、点击及长按菜单。

准备项目指定的 Flutter SDK、依赖和上游要求的补丁后，可执行标准测试：

```sh
flutter test test/pages/download/download_owner_test.dart test/pages/download/download_owner_widget_test.dart
```

项目的原生依赖可能要求主机 C++ 编译环境。对不调用这些原生 API 的上述缓存测试，另提供隔离入口。使用 Flutter SDK 自带的 Dart，并将下方 `<FLUTTER_ROOT>` 替换为 SDK 目录：

```sh
<FLUTTER_ROOT>/bin/cache/dart-sdk/bin/dart --packages=<FLUTTER_ROOT>/packages/flutter_tools/.dart_tool/package_config.json tool/test_download_cache.dart
```

该入口使用固定 Flutter 版本的内部测试工具，跳过无关桌面 FFI 构建和应用资源构建；测试提供占位图及无着色器触摸主题。它不验证原生接口或真机播放行为，也不改变 APK 构建流程。

本地已通过缓存模块静态检查、上述 11 个聚焦测试、Android Release 构建和 APK 签名校验。文件夹版仍需真机复验。

## Android 打包

沿用上游工作流准备 SDK 补丁和依赖，使用完整 Java 17 JDK。测试包可使用上游已有的开发包选项：

```sh
flutter build apk --release --build-number=2 --android-project-arg dev=1 --no-pub
```

开发包身份为 `com.example.piliplus.dev`。覆盖安装时必须使用相同签名。签名文件、本地依赖覆盖配置、SDK 和 APK 不应提交到源码仓库。
