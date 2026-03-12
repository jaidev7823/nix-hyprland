#!/usr/bin/env bash

# === CONFIG ===
WALLPAPER_DIR="$HOME/work/hypr-rice/wallpapers/"
SYMLINK_PATH="$HOME/.config/hypr/current_wallpaper"
TMP_DIR="/tmp/rofi-colors"

mkdir -p "$TMP_DIR"

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

# === EXTRACT COLORS ===
COLORS=$(magick "$SELECTED_PATH" \
  -resize 80x80 \
  -colors 4 \
  -unique-colors txt:- | awk -F'[# ]' '/#/ {print "#" $2}')

# === GENERATE COLOR ICONS ===
MENU=""
for c in $COLORS; do
  ICON="$TMP_DIR/${c#\#}.png"
  magick -size 64x64 xc:"$c" "$ICON"
  MENU+="$c\0icon\x1f$ICON\n"
done

# === ROFI COLOR PICKER ===
COLOR=$(printf "$MENU" | rofi -dmenu -p "Color")

[ -z "$COLOR" ] && exit 1

# === RUN MATUGEN ===
printf "%s\n" "$COLOR" | matugen image "$SELECTED_PATH"

# === SET WALLPAPER ===
swww img "$SELECTED_PATH" --transition-type any --transition-fps 60

# === CREATE SYMLINK ===
mkdir -p "$(dirname "$SYMLINK_PATH")"
ln -sf "$SELECTED_PATH" "$SYMLINK_PATH"
