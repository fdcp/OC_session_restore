# OC Session Restore

批量恢复 opencode session 的工具集，支持通过进程匹配自动发现运行中的 session。

## 功能

- 自动扫描系统中所有运行中的 opencode TUI 进程
- 从 opencode 数据库关联 session 元信息（标题、工作目录）
- 一键 kill 旧进程并输出恢复命令，避免逐个手动操作

## 文件说明

```
OC_session_restore/
├── gen_running_sessions.sh   # 扫描运行中的 session，生成 running_sess_id.txt
├── restore_sessions.sh       # Kill 旧进程 + 输出恢复命令
├── running_sess_id.txt       # 扫描结果（人类可读表格 + 机器可解析 DATA 段）
└── README.md
```

## 工作原理

### gen_running_sessions.sh

1. 从 SQLite 数据库 (`~/.local/share/opencode/opencode.db`) 读取所有未归档的 session
2. 通过 `ps` 扫描所有 opencode TUI 进程（排除 `serve`、`grep`、`mermaid-tools`）
3. 匹配进程与 session：
   - 有 `-s` / `--session` 参数的进程 → 直接提取 session ID
   - 无 `-s` 参数的进程 → 通过进程的 CWD 与 session 的 `directory` 字段匹配
4. 输出 `running_sess_id.txt`

**用法：**

```bash
bash gen_running_sessions.sh
```

### restore_sessions.sh

1. 从 `running_sess_id.txt` 的 `---DATA---` 段读取 session 列表
2. Kill 每个 session 对应的所有进程
3. 输出 `cd <目录> && opencode -s <session_id>` 命令，供在 VS Code 终端中逐个执行

**用法：**

```bash
bash restore_sessions.sh
```

## 典型工作流

```bash
# 1. 扫描当前运行中的 session
bash gen_running_sessions.sh

# 2. Kill 旧进程并获取恢复命令
bash restore_sessions.sh

# 3. 在 VS Code 中打开多个终端，逐个执行输出的命令
```

## 依赖

- Python 3（脚本内嵌 Python 代码，通过 `python3 -c` 执行）
- opencode 已安装并运行过（需要 `~/.local/share/opencode/opencode.db` 数据库）
- SQLite3（Python 的 `sqlite3` 模块，通常内置）

## 已知限制

- **CWD 匹配精度**：当多个 session 共享同一目录时，无 `-s` 参数的进程可能无法精确匹配到正确的 session（当前取第一个匹配项）
- **`opencode run`**：非交互式命令执行后立即退出，不在扫描范围内（实际影响可忽略）
- **`opencode serve`**：服务器模式进程被排除（不计入 session 数量）
