# WeChatPlugins

开源 iOS 越狱插件集合（MobileSubstrate tweaks）。

> ⚠️ **免责声明**：本仓库所有内容仅供**个人学习、技术研究与合法的互操作性研究**之用，
> 按「现状」提供，不含任何担保。使用者须自行遵守所在国家/地区的法律法规及相关软件的用户协议，
> **严禁**用于任何违法、侵权或损害他人合法权益的用途；一切风险与后果由使用者自行承担。
> 本仓库为独立第三方开源项目，与任何第三方应用的开发者或权利人均无隶属、赞助或背书关系，
> 所涉第三方名称、商标归其各自权利人所有。

## 插件

### [MomentsTagFilter](MomentsTagFilter/) — 按好友标签分类筛选信息流
- 在「第三方插件管理」注册设置页（启用开关 + 标签多选）
- 启用后在信息流页提供悬浮筛选入口，按好友标签过滤
- 详见子目录 [README](MomentsTagFilter/README.md)

## 自动构建

推送后 GitHub Actions（macOS runner + Theos）会自动编译，
产物在对应 Actions 运行页的 **Artifacts → `MomentsTagFilter-deb`**。

## 许可证

[MIT License](MomentsTagFilter/LICENSE) · Copyright (c) 2026 MomentsTagFilter contributors.
