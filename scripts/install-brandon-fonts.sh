#!/bin/sh
# Copies the licensed Brandon fonts installed on this Mac into the asset catalog. They are
# commercial fonts, so they are git-ignored and never committed; without them the postcard and
# loading screen fall back to the system font.
set -e
cd "$(dirname "$0")/.."
for font in "Brandon Grotesque/BrandonGrotesque-Bold" "Brandon Text/BrandonText-Bold" "Brandon Text/BrandonText-Black"; do
  name=$(basename "$font")
  source="/Library/Fonts/$font.otf"
  [ -f "$source" ] || source="$HOME/Library/Fonts/$name.otf"
  [ -f "$source" ] || { echo "Missing $name.otf; install Brandon fonts first." >&2; exit 1; }
  dir="WikiTour/Assets.xcassets/$name.dataset"
  mkdir -p "$dir"
  cp "$source" "$dir/"
  cat > "$dir/Contents.json" <<JSON
{
  "data" : [
    {
      "filename" : "$name.otf",
      "idiom" : "universal",
      "universal-type-identifier" : "public.opentype-font"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON
  echo "Installed $name"
done
