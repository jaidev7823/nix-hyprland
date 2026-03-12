#!/usr/bin/env bash

# === CONFIG ===
WALLPAPER_DIR="$HOME/work/hypr-rice/wallpapers/"
SYMLINK_PATH="$HOME/.config/hypr/current_wallpaper"

cd "$WALLPAPER_DIR" || exit 1
IFS=$'\n'

# === WALLPAPER PICKER ===
SELECTED_WALL=$(
  for a in $(ls -t *.jpg *.png *.gif *.jpeg 2>/dev/null); do
    echo -en "$a\0icon\x1f$a\n"
  done | rofi -dmenu -p "Wallpaper"
)

[ -z "$SELECTED_WALL" ] && exit 1
SELECTED_PATH="$WALLPAPER_DIR/$SELECTED_WALL"

# === COLOR PICKER WITH VISUAL PREVIEW ===
COLORS=(
  "#d6ab5d"
  "#ff5555"
  "#50fa7b"
  "#8be9fd"
  "#f1fa8c"
  "#bd93f9"
  "#ff79c6"
  "#ffffff"
  "#000000"
)

COLOR=$(
  for c in "${COLORS[@]}"; do
    printf "<span foreground='%s'>████</span> %s\n" "$c" "$c"
  done | rofi -dmenu -markup-rows -p "Color" | awk '{print $2}'
)

[ -z "$COLOR" ] && exit 1

# === RUN MATUGEN ===
printf "%s\n" "$COLOR" | matugen image "$SELECTED_PATH"

# === SET WALLPAPER ===
swww img "$SELECTED_PATH" --transition-type any --transition-fps 60

# === CREATE SYMLINK ===
mkdir -p "$(dirname "$SYMLINK_PATH")"
ln -sf "$SELECTED_PATH" "$SYMLINK_PATH"
