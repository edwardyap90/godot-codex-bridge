# Godot Codex Bridge

一个实验性的 Godot 4 编辑器本地桥接插件，让 Codex 这类编程 agent 可以通过明确、可审查的命令读取和操作 Godot 编辑器。

插件本身不调用 AI 模型 API，不保存模型密钥。推理和代码决策在 Godot 外部完成，Godot 插件只负责执行本地命令。

> 状态：Alpha。已在 Godot 4.6 测试，建议使用前保留备份。

## 能力

- 默认使用项目内文件队列，不占端口。
- 可选开启 `127.0.0.1` TCP 桥。
- 通过 `project_root` 做项目隔离，避免多项目串用。
- 右侧 Dock 显示项目、队列路径、最近命令、可视反馈、快照和运行报告。
- 命令历史写入 `.godot/godot_codex_bridge/history.jsonl`。
- 支持先预览、再加入待确认队列、最后应用。
- 修改文件或当前场景前自动创建快照。
- 支持恢复快照。
- 应用场景动作后会尽量自动选中最后一个成功修改的节点。
- 支持触发 Godot headless 检查并记录错误/警告。
- 可操作场景树、选中节点、Inspector、Project Settings、Input Map、资源和 `AnimationPlayer`。

## 安装

1. 把 `addons/godot_codex_bridge/` 复制到你的 Godot 项目。
2. 如果需要命令行 helper，把 `tools/godot_bridge_send.sh` 也复制过去。
3. 在 `Project > Project Settings > Plugins` 启用 **Godot Codex Bridge**。
4. 右侧会出现 **Codex Bridge** Dock。

默认文件队列在：

```text
res://.godot/godot_codex_bridge/inbox
res://.godot/godot_codex_bridge/outbox
```

## 新游戏工作流

如果要让 Codex 从零创建 Godot 游戏，先 bootstrap 项目：

```bash
tools/godot_bridge_bootstrap_project.sh ~/GodotGames/my-game "My Game"
cd ~/GodotGames/my-game
tools/godot_bridge_guard.sh
```

`guard` 通过后，Codex 应该通过 `tools/godot_bridge_send.sh` 写入游戏脚本、场景、资源、项目设置和编辑器动作。直接写文件只适用于 bridge 尚不存在之前的最小 bootstrap。

完整流程见 [docs/CODEX_WORKFLOW.md](docs/CODEX_WORKFLOW.md)。

## Demo 项目

`examples/flappy-sky-runner` 是一个完整的小型 Flappy 风格 Godot 游戏示例。运行方式：

```bash
tools/godot_bridge_bootstrap_project.sh examples/flappy-sky-runner "Flappy Sky Runner"
cd examples/flappy-sky-runner
tools/godot_bridge_guard.sh
tools/godot_bridge_send.sh play_main_scene
```

## 安全模型

- 请求会校验目标 `project_root`。
- 拒绝写入 `res://addons/godot_codex_bridge`。
- 支持 dry-run 预览。
- 支持待确认队列。
- 改动前创建快照。
- 运行状态只放在项目本地 `.godot/godot_codex_bridge/`，不要提交到 Git。

这仍然是编辑器自动化插件。不要执行来自不可信 agent 的命令。

## 常用命令

```bash
tools/godot_bridge_send.sh ping
tools/godot_bridge_send.sh status
tools/godot_bridge_send.sh doctor
tools/godot_bridge_send.sh get_project_identity
tools/godot_bridge_send.sh get_editor_context
tools/godot_bridge_send.sh --json '{"command":"select_node","node_path":"Player"}'
```

`status` 会显示当前项目、队列路径、待处理请求数量和桥接状态响应。`doctor` 会检查插件文件、插件启用状态、Python、Godot 可执行文件、队列目录和 bridge ping。

## 开发验证

GitHub Actions 会在推送到 `main`、Pull Request 和手动触发时自动运行这些检查。

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --check-only --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/action_executor_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/scene_action_executor_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/control_bridge_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/file_bridge_smoke.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tests/status_dock_smoke.gd
```
