# PathPop

**Agent 给出路径，你一键找到文件。**

和 AI Agent 协作写作时，Agent 常常会在完成任务后告诉你：“文件已保存到这个目录。”但拿到路径后，你还得手动切换到 Finder，再复制、粘贴路径，才能找到成果。

PathPop 把这几步缩短为一个动作：**直接在 Agent 对话中选中它给出的本机文件或目录路径，按下快捷键，Finder 就会定位到对应位置。** 不用先离开对话去找 Finder，也不用来回复制粘贴路径。

无论是刚写好的文章、整理好的文档，还是生成的项目文件，都能更快地从 Agent 的回复找到实际成果。PathPop 是一个轻量的 macOS 菜单栏工具，也适用于聊天消息、文档等其他包含本机路径的场景。

它只定位并高亮，不会打开文件。

**[下载安装包](https://github.com/shanks-w/PathPop/releases/latest)** · macOS 14.0+ · Apple 芯片 / Intel · 免费开源

## 看看效果

![PathPop 操作演示：选中 Agent 给出的本机路径，按快捷键，Finder 定位并高亮文件](docs/assets/pathpop-demo.gif)

动图由示例对话与 Finder 截图制作，按操作步骤播放。图中的 `Option + D` 是自定义快捷键；默认快捷键为 `Control + Option + Command + R`。

## 能做什么

- **选中即定位**：默认快捷键为 `⌃⌥⌘R`，也可以自定义。
- **识别常见路径格式**：支持绝对路径、`~/`、本地 `file://`，以及中文、空格和明确的外层引号。
- **歧义先确认**：从整段文字中推测路径，或识别到多个候选时，由你确认要定位哪一个。
- **保留剪贴板**：直接读取选中文字，不模拟复制，也不改写剪贴板。
- **手动复制也能用**：遇到不支持直接读取的应用，可以复制路径，再从菜单栏定位。

## 使用方式

1. 启动 PathPop，它会出现在 macOS 菜单栏中，不显示 Dock 图标或主窗口。
2. 按提示开启辅助功能权限。
3. 在 Agent 对话或其他应用中，选中它给出的完整本机文件或目录路径。
4. 按下 `Control + Option + Command + R`，Finder 就会定位目标。

例如，选中类似下面的路径（请替换为你电脑上真实存在的路径）：

```text
/Users/yourname/Documents/项目说明.txt
~/Downloads/设计稿.png
file:///Users/yourname/Documents/project%20notes.txt
```

如果选中的文字里有多个路径，或者需要去掉行列号等内容才能识别，PathPop 会先显示确认窗口。取消后不会定位。

> PathPop 定位的是你这台 Mac 上真实存在的文件。它不会下载远程文件，也不能把其他电脑或云端环境中的路径变成本机文件。

## 下载与安装

无需 Xcode，也不用自己构建。

1. 打开 [GitHub Releases](https://github.com/shanks-w/PathPop/releases/latest)，下载 `PathPop-版本号-universal.dmg`（Apple 芯片和 Intel Mac 通用，要求 macOS 14.0 或更新版本）。
2. 打开 DMG，把 `PathPop.app` 拖到 `Applications`（应用程序）文件夹。
3. 从“应用程序”启动 PathPop。它只显示菜单栏图标，没有主窗口或 Dock 图标。
4. 按提示开启辅助功能权限，然后选中路径、按快捷键即可定位。

安装包使用 ad-hoc 签名，**尚未使用 Apple Developer ID 签名或经过 Apple 公证**。首次打开时，如果 macOS 提示无法验证开发者，请先确认下载来源是本仓库的 Releases，再按 [Apple 官方指引](https://support.apple.com/zh-cn/102445)，在“系统设置 → 隐私与安全”中选择“仍要打开”并确认。无需关闭系统安全功能。

请先安装到“应用程序”再授权，不要从 DMG 内长期运行。更新时先从菜单栏退出旧版本，再替换应用；若旧权限失效，按下文重新添加。可以为“应用程序”中的 PathPop 创建桌面替身，方便以后双击启动。

每次发布附带 `SHA256SUMS`，可用 `shasum -a 256 -c SHA256SUMS` 核对下载文件。

## 从源码构建

要求：

- macOS 14.0 或更高版本。
- 完整安装的 Xcode，并选中相应的命令行工具。

在终端执行：

```bash
git clone https://github.com/shanks-w/PathPop.git
cd PathPop
xcodebuild -project PathPop.xcodeproj -scheme PathPop -configuration Debug -derivedDataPath ./build build
open ./build/Build/Products/Debug/PathPop.app
```

也可以用 Xcode 打开 `PathPop.xcodeproj`，选择 `PathPop` Scheme 和本机运行。

项目使用本地 ad-hoc 签名，无需配置开发者账号。Swift + AppKit 实现，无第三方依赖。请只运行一个实例，避免快捷键冲突。

日常使用时，可以为构建出的 `PathPop.app` 创建桌面替身，双击启动。授权后尽量保持应用位置不变。

## 权限与隐私

选中文字定位需要辅助功能权限：在“系统设置 → 隐私与安全”中找到“辅助功能”；部分系统版本将它显示为“设备控制和数据访问”。添加并开启当前版本的 PathPop。

这个权限用于读取前台应用中选中的文字。PathPop 不上传选中文字，不联网、不收集使用统计，也不保存路径历史。

“从剪贴板定位路径”只读取你已复制的文本，无需辅助功能权限。

### 已开启权限，仍反复提示怎么办？

更新安装包或自行重新构建后，临时签名可能改变，系统中的旧授权可能不再匹配。可以这样处理：

1. 退出 PathPop。
2. 在上述权限列表中移除旧的 PathPop 条目。
3. 重新添加当前的 `PathPop.app` 并开启权限。
4. 再次启动 PathPop。

## 自定义快捷键

点击菜单栏图标 →“设置快捷键…”→“录制”。注册成功后立即保存，点击“恢复默认”可恢复为 `⌃⌥⌘R`。

为避免影响正常使用，不接受仅由 Shift 搭配其他按键的组合，也不接受 `⌘C`、`⌘V`、`⌘Q` 等常用操作组合。注册失败时会尝试保留原快捷键，并提示原因。

## 目前的限制

- 自动读取取决于目标应用是否提供辅助功能选区。部分网页、自绘控件或远程桌面需要手动复制后从菜单定位。
- 不支持相对路径、`$HOME`、`~其他用户` 或远程文件地址。
- 文件不存在时，不会自动改为定位较短的相似文件名。
- 超长日志的解析性能，以及不同 macOS 版本、键盘布局和第三方应用的兼容性，仍需继续验证。
- 当前没有内置“登录时启动”或自动更新功能。

## 开发与测试

制作包含 Apple 芯片和 Intel 两种架构的 Release 安装包：

```bash
bash scripts/package.sh
```

产物位于 `build/releases/v版本号/`，包含 DMG 和 `SHA256SUMS`。脚本使用独立构建目录，不会替换 Debug 应用；当前生成的是 ad-hoc 签名、未公证的安装包。

运行基础回归测试：

```bash
bash scripts/test.sh
```

这些测试覆盖路径解析、歧义确认、选区读取流程、快捷键校验及注册失败回退，不读写用户的真实剪贴板或快捷键设置。

可选的桌面与界面检查：

```bash
# 请先退出 PathPop，避免占用同一快捷键。
bash scripts/test.sh --desktop

# 需要能够取得键盘焦点的 macOS 桌面会话。
bash scripts/test.sh --ui
```

界面检查依赖本机桌面环境；命令行测试通过不等于所有应用的跨应用兼容性都已验证。当前版本已在作者本机完成使用测试，欢迎反馈其他环境的问题。

## 反馈与贡献

欢迎通过 [Issues](https://github.com/shanks-w/PathPop/issues) 报告问题或提出建议，也欢迎提交 Pull Request。

报告问题时，请附上 macOS 版本、目标应用名称、复现步骤和预期结果。路径示例请使用虚构名称，不要上传私人文件或敏感内容。

## 许可证

本项目采用 [MIT License](LICENSE)，可免费使用、修改和分发，也允许商业使用；分发时需保留版权及许可声明。
