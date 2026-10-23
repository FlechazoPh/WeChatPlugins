#!/usr/bin/env bash
# 把本工程推到你的 GitHub 仓库，触发 Actions 自动编译出 .deb。
# 用法：
#   1) 在 GitHub 新建一个空仓库（private 也行），复制它的地址
#   2) 运行： bash push_to_github.sh git@github.com:你的名/MomentsTagFilter.git
#   3) 打开仓库 Actions 页，等 macOS runner 跑完，在 Artifacts 下载 MomentsTagFilter-deb
set -e
REMOTE="$1"
if [ -z "$REMOTE" ]; then echo "用法: bash push_to_github.sh <git远程地址>"; exit 1; fi
cd "$(dirname "$0")"
git init -q
git add -A
git -c user.email=you@example.com -c user.name=you commit -q -m "MomentsTagFilter: WeChat moments tag filter tweak"
git branch -M main
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE"
git push -u origin main
echo "已推送。去 GitHub 仓库的 Actions 页查看编译进度与下载 .deb。"
