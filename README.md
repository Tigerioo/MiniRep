# MiniRep

《魔兽世界：熊猫人之谜》怀旧服声望追踪插件。当前版本 **1.1.0**，目标客户端 **5.5.4 / Interface 50504**，无第三方插件依赖。

```text
皇帝少昊 · 崇敬 · 8,400 / 21,000（40%） · 今日 +2,000
贫民窟 · 友善 · 2,400 / 6,000（40%） · 今日 +500
```

## 功能

- 同时关注多个声望，显示名称、等级、阶段进度和百分比。
- Ctrl + 左键拖动整个面板，支持字号调整、锁定和按角色保存。
- 搜索声望，按资料片/原生分类筛选，按名称、累计声望值或今日新增排序。
- 逐行显示今日新增，并在设置中提供今日汇总。
- 兼容普通声望与友谊声望，保留折叠分类和非活动声望。

## 安装与使用

将仓库内的 **`MiniRep` 文件夹**复制到对应怀旧服客户端的 `Interface\AddOns\`，最终路径应为 `Interface\AddOns\MiniRep\MiniRep.toc`。重启游戏并启用插件。

输入 `/rmini` 或右键屏幕文字打开设置。点击声望行添加/取消关注；分类和排序按钮支持左键下一项、右键上一项。

升级时退出游戏后覆盖插件文件，保留客户端 `WTF` 目录。1.0 的单个声望与位置设置会自动迁移。

今日新增按电脑本地日期统计，只累计在线且关注期间记录到的正向增量，同日重登保留，午夜后重新开始。当前只保留当天，不追溯安装前、离线或未关注期间的收益。

完整说明见 [插件使用说明](MiniRep/README.md)。

## 项目结构

```text
MiniRep/       可直接安装的插件代码、使用说明与验证记录
docs/          当前功能设计
scripts/       本地开发检查入口
tests/         声望计算、每日记录及模拟 API 检查
```

## 开发检查

安装 Node.js 与 npm 后，在仓库根目录执行：

```powershell
npm ci --ignore-scripts --no-audit --no-fund
npm run check:syntax
npm run check:smoke
```

开发工具仅在本地检查时使用，安装插件不需要 Node.js，也不需要把 `node_modules` 放进游戏目录。

检查包含 Lua 5.1 语法、51 项声望/今日数据断言，以及模拟 API 的多关注、筛选、排序、Ctrl 拖动和配置迁移流程。尚未在真实游戏客户端验证渲染和事件时序，详见 [验证记录](MiniRep/VALIDATION.md)。

## 打包

在 Windows PowerShell 中执行，安装包只包含可安装目录：

```powershell
New-Item -ItemType Directory -Path dist -Force | Out-Null
Compress-Archive -LiteralPath MiniRep -DestinationPath dist/MiniRep-1.1.0.zip
```

生成的安装包和开发依赖已加入 Git 忽略列表。当前设计见 [设计稿](docs/design.md)。
