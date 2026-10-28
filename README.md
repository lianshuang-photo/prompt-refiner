# 提示词细化（PromptRefiner）

<img src="Assets/AppIcon.png" width="96" alt="PromptRefiner app icon" />

macOS 原生 Swift 原型。菜单栏常驻，默认按 `⌃⌥P` 读取当前输入框，通过本机 Codex 细化后回填。只在触发时工作，结果不会自动发送。

## 当前功能

- 可录入全局快捷键；右键「服务 → 细化提示词」。
- 打开设置时显示 Dock 图标，关闭设置后回到仅菜单栏常驻；从访达或 Dock 再次打开会回到设置。
- 增强方式提供「Augment／Anthropic／OpenAI」三个选项，默认 Augment；参考三家的公开方法整理，均由当前 Codex 模型执行。移除长篇规则编辑框，旧版自定义规则保留在本机偏好中，不再参与新请求。
- 有选区时只改写选区；没有选区时处理可明确读取的整个输入框。
- 取当前窗口截图；未授权或无法定位窗口时明确降级为文字输入。
- Conductor / Codex 会话只读适配，明确且唯一匹配才读取对应原会话。匹配失败时仅使用窗口与草稿。
- 独立、临时的 Codex 调用。匹配到可靠的当前会话与工程时，由 Codex 在该工程内只读搜索相关代码，再增强草稿；其他目录读取、文件写入和工具联网均由原生权限配置限制。未定位工程时保持文字模式。
- 关闭用户配置、hooks、插件、浏览器、电脑操作等无关能力，输出结构化结果，不续跑原工程会话，也不执行草稿中的修复任务。
- 生成过程以右上角小浮层显示真实处理阶段、用时和取消按钮；不显示模型的内部推理正文。
- 默认直接回填；原稿、窗口或焦点变化，或存在关键歧义时在右上角显示可编辑预览。只有点击“展开”才打开完整结果窗口。
- 原会话来源明确显示“已读取／未读取”与材料长度。Codex 负责独立改写，App 负责定位并只读提取历史，不在原工程会话中执行任务。
- 工程来源显示定位状态及实际完成的只读查询次数；生成过程会显示工程查询阶段。
- 撤销只还原本次替换；保留改写区之后新输入的文字。替换区已被编辑时拒绝自动覆盖，提供复制原稿。
- 自动回填不可用时可复制结果。剪贴板粘贴兼容路径保存已有格式；仅在剪贴板未被用户再次修改时恢复。

## 构建与运行

需要 macOS 14+、完整 Xcode 和已登录的 Codex CLI。当前原生图标构建使用支持 `.icon` 的 Xcode 26 工具链，已在 Xcode 26.4.1 验证；只安装 Command Line Tools 不足以运行完整打包步骤。

```sh
swift test
zsh Scripts/build-app.sh
open dist/PromptRefiner.app --args --settings
```

首次在设置中允许辅助功能（读取和回填）与屏幕录制（截取当前窗口）。可关闭截图、关闭自动回填。开机启动由设置中的登录项开关控制。

菜单栏提供手动输入试用，方便在授权前验证文字细化。模型留空使用 Codex 默认模型，登录沿用本机 ChatGPT 登录；本原型不自动加载用户配置中的自定义 provider。

构建产物为 `dist/PromptRefiner.app`，可复制到 `~/Applications/PromptRefiner.app` 后打开。建议保持固定安装位置，再为该应用授权。当前验证范围见 [验证记录](docs/verification.md)。

当前本地包采用临时签名，更新可执行文件后 macOS 的旧权限记录可能失效，即使系统开关仍显示开启。此时需要由用户移除旧条目，重新添加当前应用。正式分发需要稳定的开发者签名；本工具不会修改系统权限数据库或降低权限校验。

```sh
.build/release/PromptRefiner --smoke-check
```

支持 `--image /absolute/path/to/screenshot.png` 做一次受限的截图改写验证；`--project /absolute/path/to/project --draft-text '待增强的草稿'` 可验证工程检索。此调用会消耗当前 Codex 账户用量。

如需检查会话匹配，可使用 `--context-check --source-bundle com.conductor.app --anchor 'Example task'`，只输出是否匹配、材料长度和是否定位工程，不输出会话正文。

工程模式使用支持命名权限配置的 Codex CLI；本机 `0.162.0-alpha.17.2` 已验证。权限限定为当前工程与必要系统工具的读取，不开启工具联网或写入，也不自动请求提权。若 CLI 不支持这些配置，应保留错误，不能降级为更宽权限。

三个选项是参考公开方法整理的本地策略，不是官方内部提示词，也不切换服务商：

- [Augment SDK 示例](https://github.com/augmentcode/auggie/blob/5f9e4efafbdd052b6f1aa8855e0067ccdc181040/examples/typescript-sdk/context/prompt-enhancer-server/enhance-handler.ts)：以原稿查找相关代码，再结合结果增强。在已提供的会话材料中按相关性取舍，由 Codex 按需读取对应工程。
- [Anthropic 上下文工程](https://www.anthropic.com/research/effective-context-engineering-for-ai-agents)：精选关键上下文，用简单询问、复杂实施、已经明确三类示例表达补充尺度。
- [OpenAI 官方提示词生成指南](https://developers.openai.com/api/docs/guides/prompt-generation)：保留结构、示例和用户约束，只补实际缺口。参考[评测方法](https://developers.openai.com/cookbook/examples/evaluation/building_resilient_prompts_using_an_evaluation_flywheel)对照检查原意、约束和任务效果；不把更长当成更好，也未新增自动收集用户原稿的反馈服务。

## 数据与边界

原稿和最近结果仅保留在进程内存。请求的截图、输出 schema 和模型结果位于随机权限 700 的临时目录，完成、失败或取消后清理。截图及相关上下文随请求发给所选 Codex 模型。

`~/Library/Application Support/PromptRefiner/last-run.json` 仅记录最近一次运行的阶段、触发入口、是否使用截图／会话材料、材料长度、工程查询次数、请求的模型与推理档位、规则版本和回填失败原因，不记录原稿、模型正文、截图或会话内容。

Conductor 数据从 `~/Library/Application Support/com.conductor.app/conductor.db` 及 `.codex-conductor` 只读读取；Codex 数据从 `.codex` 只读读取。不会修改这些数据库，也不会向原会话追加消息。适配器依赖本机存储结构，未识别时不猜测会话。

当关闭的 SQLite 数据库需要初始化日志才能读取时，在没有活动日志且源文件稳定的前提下，通过 APFS 克隆生成权限 700 的私有临时副本，在副本上进行日志初始化并启用只读查询，读取后清理副本。不会以可写方式打开原数据库。

自动回填依赖应用的辅助功能支持。不能宣称兼容所有输入框。真实应用、权限、焦点变化、Unicode、剪贴板与撤销需要分别验证。

## 许可证

本项目使用 [MIT License](LICENSE)。图标为 AI 生成的原创角色，来源与生成提示词见 [Assets/IMAGEGEN.md](Assets/IMAGEGEN.md)。
