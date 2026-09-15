#!/bin/sh
# 从 .env 读取 Gemini Key，写入不提交的 Config/Secrets.xcconfig，编译时注入 Info.plist。
# 用法：scripts/sync-secrets.sh [.env 路径，默认 ~/.env] [变量名，默认 GEMINI_FREE_API]
set -eu

ENV_FILE="${1:-$HOME/.env}"
VAR="${2:-GEMINI_FREE_API}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/Config/Secrets.xcconfig"

key=$(grep -E "^(export )?$VAR=" "$ENV_FILE" | head -1 | sed -E "s/^(export )?$VAR=//; s/^[\"']//; s/[\"']\$//")
if [ -z "$key" ]; then
  echo "$VAR not found in $ENV_FILE" >&2
  exit 1
fi
case "$key" in
  *[!A-Za-z0-9._-]*) echo "$VAR contains characters xcconfig can't hold" >&2; exit 1 ;;
esac

umask 077
printf 'GEMINI_API_KEY = %s\n' "$key" > "$OUT"
echo "wrote $OUT"
