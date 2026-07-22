#!/bin/bash
# 批量恢复 opencode sessions（方案 B：kill + -s 接管）
# 从 running_sess_id.txt 的 ---DATA--- 段读取 session 信息
# 用法: bash restore_sessions.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_FILE="${SCRIPT_DIR}/running_sess_id.txt"

if [ ! -f "$DATA_FILE" ]; then
  echo "Error: $DATA_FILE not found" >&2
  echo "Run gen_running_sessions.sh first" >&2
  exit 1
fi

# Extract ---DATA--- section and parse
awk '/^---DATA---$/{found=1; next} found' "$DATA_FILE" | while IFS='|' read -r sid title directory pids; do
  [ -z "$sid" ] && continue

  echo "=== Kill: $sid ==="
  IFS=',' read -ra PID_ARRAY <<< "$pids"
  for pid in "${PID_ARRAY[@]}"; do
    kill "$pid" 2>/dev/null && echo "  Killed PID $pid" || echo "  PID $pid already dead"
  done
done

sleep 2

echo ""
echo "=== 在 VS Code 中逐个执行以下命令 ==="
awk '/^---DATA---$/{found=1; next} found' "$DATA_FILE" | while IFS='|' read -r sid title directory pids; do
  [ -z "$sid" ] && continue
  echo ""
  echo "# $title → $directory"
  echo "cd $directory && opencode -s $sid"
done
