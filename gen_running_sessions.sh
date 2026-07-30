#!/bin/bash
# 生成运行中的 opencode session 列表（支持同一 session 多个 PID）
# 用法: bash gen_running_sessions.sh
# 输出: <脚本目录>/running_sess_id.txt

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_FILE="${HOME}/.local/share/opencode/opencode.db"
OUTPUT_FILE="${SCRIPT_DIR}/running_sess_id.txt"

if [ ! -f "$DB_FILE" ]; then
  echo "Error: opencode database not found at $DB_FILE" >&2
  exit 1
fi

export DB_FILE OUTPUT_FILE
python3 << 'PYEOF'
import sqlite3
import os
import subprocess
import re
from collections import defaultdict

DB_FILE = os.environ["DB_FILE"]
OUTPUT_FILE = os.environ["OUTPUT_FILE"]


def get_cwd(pid):
    """Cross-platform CWD lookup. /proc on Linux, lsof on macOS/BSD."""
    if os.uname().sysname == "Linux":
        try:
            return os.readlink(f"/proc/{pid}/cwd")
        except (OSError, PermissionError):
            return None
    try:
        result = subprocess.run(
            ["lsof", "-a", "-p", str(pid), "-d", "cwd", "-F", "n"],
            capture_output=True, text=True, timeout=2,
        )
        for line in result.stdout.splitlines():
            if line.startswith("n"):
                return line[1:] or None
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        pass
    return None


conn = sqlite3.connect(DB_FILE)
cursor = conn.cursor()

# 1. Get all non-archived sessions
cursor.execute("""
    SELECT id, title, directory, time_created, time_updated
    FROM session
    WHERE time_archived IS NULL
    ORDER BY time_updated DESC
""")
sessions = {row[0]: {"id": row[0], "title": row[1], "directory": row[2],
                       "time_created": row[3], "time_updated": row[4]}
            for row in cursor.fetchall()}

# 2. Get running opencode processes (exclude mermaid-tools, grep, serve)
result = subprocess.run(
    ["ps", "aux"], capture_output=True, text=True
)
processes = []
for line in result.stdout.splitlines():
    if "opencode" not in line:
        continue
    if "grep" in line or "mermaid" in line or "serve" in line:
        continue
    parts = line.split(None, 10)
    if len(parts) < 11:
        continue
    pid = parts[1]
    cmd = parts[10]

    session_id = None
    if " -s " in cmd or " --session " in cmd:
        m = re.search(r'(?:--session|-s)\s+(ses_\w+)', cmd)
        if m:
            session_id = m.group(1)

    cwd = get_cwd(pid)

    processes.append({
        "pid": pid,
        "cmd": cmd,
        "session_id": session_id,
        "cwd": cwd,
    })

# 3. Match and group by session_id
session_pids = defaultdict(list)
for proc in processes:
    sid = proc["session_id"]
    if sid and sid in sessions:
        session_pids[sid].append(proc["pid"])
    elif proc["cwd"]:
        for sid, s in sessions.items():
            if s["directory"] == proc["cwd"]:
                session_pids[sid].append(proc["pid"])
                break

# 4. Build output
lines = []
lines.append(f"全部运行中的 opencode session（共 {len(session_pids)} 个）")
lines.append("=" * 60)
lines.append("")
lines.append(f"{'Session ID':<40} {'标题':<30} {'所在目录':<50} {'启动方式'}")
lines.append("-" * 150)
for sid, pids in session_pids.items():
    s = sessions[sid]
    pids_str = ", ".join(f"PID {p}" for p in pids)
    lines.append(f"{sid:<40} {s['title']:<30} {s['directory']:<50} {pids_str}")

# 5. Append machine-readable section
lines.append("")
lines.append("---DATA---")
for sid, pids in session_pids.items():
    s = sessions[sid]
    pids_str = ",".join(pids)
    lines.append(f"{sid}|{s['title']}|{s['directory']}|{pids_str}")

output = "\n".join(lines) + "\n"

with open(OUTPUT_FILE, "w") as f:
    f.write(output)

print(output)
print(f"已写入 {OUTPUT_FILE}")

conn.close()
PYEOF
