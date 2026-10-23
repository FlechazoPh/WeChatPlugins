# MomentsTagFilter — 按好友标签分类筛选信息流

一个独立开源的 MobileSubstrate (`.deb`) tweak：为支持「好友标签 / 分组」的即时通讯客户端，
在其信息流页面提供「按标签筛选」能力。

> ⚠️ **免责声明（请先阅读）**
> 本项目仅供**个人学习、技术研究与合法的互操作性研究**之用，按「现状」提供，不含任何担保。
> 使用者须自行遵守所在国家/地区的法律法规，以及相关软件的用户协议与条款；
> **严禁**用于任何违法、侵权、破坏数据安全或损害他人合法权益的用途。
> 因使用或无法使用本软件造成的任何风险与后果（包括但不限于账号受限、数据丢失、服务中断）
> 均由使用者自行承担，作者与贡献者不承担任何责任。
> 本项目为独立的第三方开源项目，与任何第三方应用的开发者或权利人均无隶属、赞助或背书关系，
> 所涉第三方名称、商标归其各自权利人所有。

## 功能

1. **设置入口**：在「第三方插件管理」列表中注册设置页，含：
   - 「启用筛选」总开关；
   - 读取本地通讯录中真实的好友标签，支持多选。
2. **信息流入口**：启用后，信息流页面右上角出现悬浮筛选按钮；
   关闭开关则不显示入口，也不进行任何过滤。
3. 选中标签后，信息流只保留「作者属于所选标签成员集合」的条目。

## 实现要点

- 过滤采用**非破坏性投影**：对数据门面的「条目计数 / 按序取值」做重索引，
  仅保留匹配作者的条目，不改动宿主的差分与渲染流程，稳定且可随时还原。
- 标签与成员数据来自客户端本地的标签管理接口；本项目**不采集、不上传任何用户数据**，
  所有状态仅保存在客户端自身的本地偏好存储中。

## 目录

```
MomentsTagFilter/
├── Tweak.xm                 # 全部逻辑（hook + 设置页 + 筛选引擎）
├── Makefile                 # Theos 构建脚本（arm64 + arm64e）
├── control                  # deb 包元信息
├── MomentsTagFilter.plist   # MobileSubstrate 注入过滤器
├── LICENSE                  # MIT 许可证
├── build_on_linux.sh        # Linux/macOS 一键编译+打包
├── pack_deb.py              # 纯 Python 打包器（dylib → deb，无需 dpkg）
└── README.md
```

## 构建

本项目在装有 **Theos + iOS SDK** 的 macOS/Linux 上编译：

```bash
# 安装 Theos: https://theos.dev/docs/installation
export THEOS=~/theos
bash build_on_linux.sh
# 产物: packages/*.deb
```

rootless 越狱请在 `Makefile` 中启用 `THEOS_PACKAGE_SCHEME = rootless`。
仓库内置 GitHub Actions（macOS runner + Theos），push 后在 Actions 的 Artifacts 中可下载自动构建的 `.deb`。

若已在别处编译好 dylib，只需打包：

```bash
python pack_deb.py --dylib MomentsTagFilter.dylib --out MomentsTagFilter.deb   # rootless 加 --rootless
```

## 安装

1. 设备需已越狱并安装 MobileSubstrate / Substitute / ElleKit。
2. 用包管理器（Sileo / Zebra / Filza）安装对应布局的 `.deb`，或 `dpkg -i xxx.deb` 后重启目标进程。
3. 进入设置页打开「启用」开关并勾选标签，即可在信息流页使用筛选入口。

## 许可证

本项目基于 [MIT License](LICENSE) 开源。Copyright (c) 2026 MomentsTagFilter contributors.
