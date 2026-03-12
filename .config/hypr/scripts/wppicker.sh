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

# === RUN MATUGEN (auto choose first color) ===
printf "1\n" | matugen image "$SELECTED_PATH"

# === SET WALLPAPER ===
swww img "$SELECTED_PATH" --transition-type any --transition-fps 60

# === CREATE SYMLINK ===
mkdir -p "$(dirname "$SYMLINK_PATH")"
ln -sf "$SELECTED_PATH" "$SYMLINK_PATH"
