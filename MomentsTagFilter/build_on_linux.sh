#!/usr/bin/env bash
# 在 Linux 或 macOS 上一键编译 + 打包 MomentsTagFilter.deb
# 前置：已安装 Theos (https://theos.dev) 与 iOS SDK，且 $THEOS 指向 theos 目录。
set -e

if [ -z "$THEOS" ]; then
  echo "请先设置 THEOS 环境变量，例如：export THEOS=~/theos"
  echo "安装 Theos: bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)\""
  exit 1
fi

cd "$(dirname "$0")"

# 清理 + 编译 + 打包（arm64 + arm64e）
make clean || true
make package FINALPACKAGE=1

echo
echo "完成。生成的 deb 在 ./packages/ 目录下："
ls -la packages/*.deb 2>/dev/null || echo "（未找到 packages/*.deb，请检查上面的编译日志）"
