#!/usr/bin/env bash
# 截图工具：默认整屏截图；--window 只截 DevEco Studio 窗口（按窗口 bounds 裁剪）
#
# 用法：
#   bash scripts/shot.sh <输出文件.png> [--window] [--device] [--app "DevEco-Studio"]
#   --window  只截 DevEco Studio 窗口（按窗口 bounds 裁剪）
#   --device  从已连接的鸿蒙设备/模拟器截图（hdc snapshot_display），也就是 App 画面
# 环境变量：
#   SHOT_APP   目标应用进程名，默认 DevEco-Studio
#   SHOT_QUIET 1 = 不输出多余信息
set -euo pipefail

HDC="${HDC:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc}"

OUT="${1:-screenshot.png}"
MODE="screen"
APP="${SHOT_APP:-DevEco-Studio}"

shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --window) MODE="window" ;;
    --device) MODE="device" ;;
    --app) APP="$2"; shift ;;
    *) echo "未知参数: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$(dirname "$OUT")"

# 0) 设备/模拟器截图（App 真实画面）
if [ "$MODE" = "device" ]; then
  TARGET="$("$HDC" list targets 2>/dev/null | head -1 | tr -d '\r' | sed 's/[[:space:]]*$//')"
  case "$TARGET" in
    ""|*Empty*)
      echo "错误：没有连接中的设备/模拟器（hdc list targets 为空）" >&2
      exit 1 ;;
  esac
  REMOTE="/data/local/tmp/shot_$$.jpeg"
  "$HDC" -t "$TARGET" shell "snapshot_display -f $REMOTE" >/dev/null 2>&1 || {
    echo "错误：设备截图失败（snapshot_display 不可用）" >&2; exit 1; }
  "$HDC" -t "$TARGET" file recv "$REMOTE" "$OUT" >/dev/null 2>&1
  "$HDC" -t "$TARGET" shell "rm -f $REMOTE" >/dev/null 2>&1 || true
  [ "${SHOT_QUIET:-0}" = "1" ] || echo "已截图（设备 ${TARGET}）：${OUT}"
  exit 0
fi

TMP="$(mktemp -t shot).png"

# 1) 窗口模式：优先按 CGWindowID 直接截该窗口内容（可忽略遮挡窗口，如悬浮面板）
if [ "$MODE" = "window" ]; then
  WID="$(osascript -e "tell application \"$APP\" to get id of front window" 2>/dev/null || true)"
  case "$WID" in
    ''|*[!0-9]*) : ;;
    *)
      if screencapture -x -o -l "$WID" "$OUT" 2>/dev/null; then
        [ "${SHOT_QUIET:-0}" = "1" ] || echo "已截图（窗口 ${WID}）：$OUT ($(sips -g pixelWidth -g pixelHeight "$OUT" | awk '/pixel/{printf "%s ", $2}'))"
        exit 0
      fi
      ;;
  esac
fi

# 2) 退路：整屏截 + 按窗口 bounds 裁剪（Retina 下是 2x 物理像素）
screencapture -x -m -t png "$TMP"

if [ "$MODE" = "window" ]; then
  # 2) 取窗口逻辑坐标(x, y, w, h)
  BOUNDS="$(osascript \
    -e "tell application \"System Events\" to tell (first process whose name contains \"$APP\") to get {position, size} of front window" \
    2>/dev/null || true)"
  if [ -n "$BOUNDS" ]; then
    read -r X Y W H <<<"$(echo "$BOUNDS" | tr -d ' ' | tr ',' ' ')"
    # 3) 计算 Retina 缩放比（物理像素 / 逻辑像素）
    SCREEN_W_LOGICAL="$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null | awk -F', ' '{print $3}' || echo 1440)"
    IMG_W="$(sips -g pixelWidth "$TMP" | awk '/pixelWidth/{print $2}')"
    SCALE="$(python3 -c "print(f'{$IMG_W/$SCREEN_W_LOGICAL:.3f}')" 2>/dev/null || echo 2)"
    sips -c "$(python3 -c "print(round($H*$SCALE))")" "$(python3 -c "print(round($W*$SCALE))")" \
         --cropOffset "$(python3 -c "print(round($Y*$SCALE))")" "$(python3 -c "print(round($X*$SCALE))")" \
         "$TMP" --out "$OUT" >/dev/null
  else
    cp "$TMP" "$OUT"
    [ "${SHOT_QUIET:-0}" = "1" ] || echo "提示：未找到应用 \"$APP\" 的窗口，已退化为整屏截图" >&2
  fi
else
  cp "$TMP" "$OUT"
fi

rm -f "$TMP"
[ "${SHOT_QUIET:-0}" = "1" ] || echo "已截图：$OUT ($(sips -g pixelWidth -g pixelHeight "$OUT" | awk '/pixel/{printf "%s ", $2}'))"
