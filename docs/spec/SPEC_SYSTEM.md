# Spec 系统

> 规则的完整版在 solo-spec skill 里（`~/.claude/skills/solo-spec/`）；这里是本项目的一页摘要。

GeoGhost 由一个人决定产品、AI agent 写大部分文档和代码。这里的文件是两者共用的记忆：新开一个会话，只读这些文件就能接着做。

## 目录

| 位置 | 内容 |
|---|---|
| [BOARD.md](BOARD.md) | 所有进行中的变更：状态、下一步、谁来做。**从这里开始** |
| `capabilities/<能力>/spec.md` | 现在的 App 对用户表现出的行为（主 spec）。只在变更归档时更新 |
| `changes/<变更>/proposal.md` | 为什么做、做什么、不做什么，以及讨论中按日期累积的决定 |
| `changes/<变更>/specs/<能力>/spec.md` | 这个变更让行为怎么变（delta） |
| `changes/<变更>/design.md` | 怎么实现：接口、数据、安全规则、取舍 |
| `changes/<变更>/tasks.md` | 任务清单：负责人、依赖、怎么验证 |
| `changes/archive/` | 完成或放弃的变更，不再修改 |

路线图、定价等长期想法仍在 [06 路线图](../06-product-roadmap.md)；决定要做时才变成这里的一个变更。工程决策仍记在 [01 技术架构](../01-technical-architecture.md) 的 ADR 里。

## 提案状态

`idea`（记下来，未决定）→ `accepted`（决定做）→ `in-progress`（开始做）→ `done`（上线并归档）；或 `dropped`（决定不做，写明原因后归档）。只有用户能把提案改成 `accepted` 或 `dropped`。

## 任务负责人

- `agent`：代码、文档、测试，agent 自己能完成并验证的。
- `me`：账号、密钥、付费服务、各种后台（Supabase、Cloudflare、App Store Connect）、真机检查、任何对外发布的东西。

任务只有在「verify」写的验证通过后才打勾，并在下一行写证据。

## spec 的写法

- 写用户能观察到的行为，不写实现（表名、框架、服务名不出现；`spec.json` 列出了本项目的禁用词）。
- 每条 Requirement 一条规则，用「必须」或 SHALL / MUST，至少一个 Scenario（**GIVEN** / **WHEN** / **THEN**）。
- 检查：`python3 ~/.claude/skills/solo-spec/scripts/spec_tool.py check-delta <delta> --main <主 spec>`
- 归档：`python3 ~/.claude/skills/solo-spec/scripts/spec_tool.py archive changes/<变更> --baseline '<commit>'`（先 dry run，再加 `--apply`）
