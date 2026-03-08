# WidgetDesk

> Prompt your AI to put widgets on your Mac desktop.  
> 用自然语言让 AI 把组件放到你的 Mac 桌面上。

WidgetDesk turns Claude Code into a desktop widget maker for macOS. Describe an idea, and your agent can create, update, hide, show, or remove a widget for you.  
WidgetDesk 让 Claude Code 变成一个 macOS 桌面组件生成器。你描述一个想法，agent 就能帮你创建、修改、隐藏、显示或删除桌面组件。

It is built for fast desktop experiments: pomodoro timers, weather cards, system monitors, music widgets, volume controls, quick notes, or small playful ideas.  
它适合快速实现各种桌面创意：番茄钟、天气卡片、系统监控、音乐组件、音量调节、速记胶囊，或者一些轻量有趣的小玩意。

![WidgetDesk demo](docs/images/widgetdesk-hero.png)

```text
/widget add a pomodoro timer on the bottom left
/widget create a floating volume knob on the right
/widget show me a live CPU monitor on the top right
```

## What You Can Build | 你可以做什么

- Utility widgets: clocks, timers, weather, battery, CPU, memory
- Control widgets: volume knobs, music cards, quick launchers
- Interactive widgets: memo pads, sticky notes, tiny tools
- Experimental widgets: playful UI, mini toys, one-off desktop ideas

- 实用组件：时钟、计时器、天气、电池、CPU、内存
- 控制组件：音量旋钮、音乐卡片、快捷启动器
- 交互组件：速记板、便签、小工具
- 实验组件：有趣 UI、小玩具、一次性的桌面创意


## Quick Start | 快速开始

Prerequisites:

- macOS 12+
- [Claude Code](https://claude.ai/code)
- [Homebrew](https://brew.sh)

前提：

- macOS 12+
- [Claude Code](https://claude.ai/code)
- [Homebrew](https://brew.sh)

If you have not cloned the repo yet:

```bash
git clone <your-repo-url> widgetdesk
cd widgetdesk
bash ./.claude/skills/widget/scripts/setup.sh
bash ./.claude/skills/widget/scripts/setup.sh --check
```

If you already cloned it:

```bash
cd widgetdesk
bash ./.claude/skills/widget/scripts/setup.sh
bash ./.claude/skills/widget/scripts/setup.sh --check
```

If you are using Codex instead of Claude Code:

```bash
cd widgetdesk
bash ./.agents/skills/widget/scripts/setup.sh
bash ./.agents/skills/widget/scripts/setup.sh --check
```

Then try this in Claude Code:

```text
/widget add a clock showing the current time
```

然后在 Claude Code 里试：

```text
/widget add a clock showing the current time
```

## Built-In Templates | 内置模板

The repo currently ships ten templates:  
当前仓库内置 10 个模板：

| Widget | Description | Default Position |
|--------|-------------|------------------|
| `clock.jsx` | Time + date display | Bottom right |
| `pomodoro.jsx` | 25/5 pomodoro timer | Bottom left |
| `system-stats.jsx` | CPU, memory, battery bars | Top right |
| `now-playing.jsx` | Apple Music now playing card | Bottom center |
| `weather-canvas.jsx` | Animated weather card via `wttr.in` | Top left |
| `git-pulse.jsx` | Git activity heatmap from local repos | Top right |
| `horizon-clock.jsx` | Alternate clock style | Bottom right |
| `memo-capsule.jsx` | Local quick note capsule | Top center |
| `volume-knob.jsx` | System volume control knob | Right side |
| `tap-counter.jsx` | Interactive counter with persisted local state | Bottom right |

## Example Prompts | 示例指令

```text
/widget add a clock on the top right
/widget add a system volume knob on the right
/widget add a sticky note that says "drink water"
/widget show today's weather from wttr.in
/widget hide the pomodoro timer
/widget delete the system stats widget
/widget list all my widgets
```

The agent writes the widget file into the correct desktop widget directory and the host reloads it automatically.  
Agent 会把 widget 写进正确的桌面组件目录，宿主会自动热更新。

## What This Repo Ships | 仓库内容

- A Claude Code skill under `.claude/skills/widget/`
- Reusable implementation patterns
- Ten ready-to-use widget templates
- A skill-local `scripts/setup.sh` installer that prepares the local environment and installs the skill into `~/.claude/skills/widget/`

- 一个放在 `.claude/skills/widget/` 下的 Claude Code skill
- 一组可复用实现模式
- 10 个现成模板
- 一个 skill 内部的 `scripts/setup.sh` 安装脚本，用来准备本地环境并把 skill 安装到 `~/.claude/skills/widget/`

## Troubleshooting | 排查

- Run the skill-local `scripts/setup.sh` first; use `--check` only for dry-run diagnostics
- If the widget directory is missing, open the desktop host once manually and rerun the skill-local `scripts/setup.sh`
- If `/widget` is not available in Claude Code, confirm `~/.claude/skills/widget/SKILL.md` exists

- 先运行 skill 内部的 `scripts/setup.sh`；`--check` 只用于只读诊断
- 如果 widget 目录不存在，先手动打开一次桌面宿主，再重新执行 skill 内部的 `scripts/setup.sh`
- 如果 Claude Code 里没有 `/widget`，确认 `~/.claude/skills/widget/SKILL.md` 已存在

## Widget Format | Widget 格式

Widgets are `.jsx` files. Minimal example:  
Widget 本质上就是 `.jsx` 文件，最小示例如下：

```jsx
export const command = "date '+%H:%M'"
export const refreshFrequency = 1000
export const className = `
  position: fixed;
  bottom: 90px;
  right: 40px;
  color: white;
  font-size: 48px;
`
export const render = ({ output }) => <div>{output?.trim()}</div>
```

For the full contract, rules, setup flow, and host workflow, see [SKILL.md](.claude/skills/widget/SKILL.md).  
完整规则、约束、初始化流程和宿主流程见 [SKILL.md](.claude/skills/widget/SKILL.md)。


## Project Structure | 项目结构

```text
.claude/
  skills/
    widget/
      SKILL.md
      patterns.md
      scripts/
        setup.sh
        doctor.sh
        install-widget.sh
        list-widgets.sh
        start-uebersicht.sh
      templates/
        clock.jsx
        git-pulse.jsx
        horizon-clock.jsx
        memo-capsule.jsx
        now-playing.jsx
        pomodoro.jsx
        system-stats.jsx
        tap-counter.jsx
        volume-knob.jsx
        weather-canvas.jsx
```

## For Other AI Agents | 给其他 Agent

[SKILL.md](.claude/skills/widget/SKILL.md) defines the Claude-facing workflow, and the mirrored `.agents` copy carries the Codex-facing workflow. Other agents can reuse either as long as they can write widget files into the local desktop widget directory.  
[SKILL.md](.claude/skills/widget/SKILL.md) 定义了面向 Claude 的流程，对应的 `.agents` 副本定义了面向 Codex 的流程。只要其他 agent 能往本地桌面组件目录写文件，就可以复用这套规则。

## License | 许可

MIT
