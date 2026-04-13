#!/usr/bin/env bash

# === CONFIG ===
WALLPAPER_DIR="$HOME/work/nix-hyprland/wallpapers"
SYMLINK_PATH="$HOME/.config/hypr/current_wallpaper"

# === WALLPAPER PICKER ===
# Using 'find' is faster and safer for filenames with spaces
SELECTED_WALL=$(
  find "$WALLPAPER_DIR" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.jpeg" \) -exec basename {} \; |
    while read -r file; do
      echo -en "$file\0icon\x1f$WALLPAPER_DIR/$file\n"
    done | rofi -dmenu -p "Wallpaper"
)

[ -z "$SELECTED_WALL" ] && exit 1
SELECTED_PATH="$WALLPAPER_DIR/$SELECTED_WALL"

# === CREATE SYMLINK ===
mkdir -p "$(dirname "$SYMLINK_PATH")"
ln -sf "$SELECTED_PATH" "$SYMLINK_PATH"

# === SET WALLPAPER (Moved UP for instant visual feedback) ===
awww img "$SELECTED_PATH" --transition-type any --transition-fps 60 &

# === RUN MATUGEN (Backgrounded and detached) ===
# 'yes 1' sends an infinite stream of "1"s in case it asks multiple times.
# Redirecting to /dev/null prevents it from hanging when run via a WM keybind.
yes 1 | matugen image "$SELECTED_PATH" >/dev/null 2>&1 &
