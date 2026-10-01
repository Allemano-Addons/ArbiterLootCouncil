#!/usr/bin/env bash
# Posts a short release note to the Discord #releases channel. Runs from the release workflow after the
# packager has uploaded the files. The webhook URL is the repository (or organisation) secret
# DISCORD_RELEASES_WEBHOOK; without it nothing is posted. DRY_RUN=1 prints the message instead of sending it.
set -euo pipefail

if [ -z "${DISCORD_WEBHOOK:-}" ] && [ -z "${DRY_RUN:-}" ]; then
  echo "No Discord webhook set: nothing to announce."
  exit 0
fi

TAG="${GITHUB_REF_NAME:?}"
FULL="${TAG#v}"      # 0.3.3-beta
BASE="${FULL%%-*}"   # 0.3.3
TOC=$(ls ./*.toc | head -1)
TITLE=$(grep -m1 '^## Title:' "$TOC" | sed 's/^## Title: *//' | tr -d '\r')
CFID=$(grep -m1 '^## X-Curse-Project-ID:' "$TOC" | sed 's/.*: *//' | tr -d '\r')

# The lines under the changelog heading that starts with the version (the heading may end in a date).
notes() {
  awk -v v="$1" '
    /^## / {
      if (found) exit
      h = "## " v
      a = substr($0, length(h) + 1, 1)
      if (index($0, h) == 1 && (a == "" || a == " " || a == "\r")) found = 1
      next
    }
    found { print }' CHANGELOG.md | tr -d '\r'
}
NOTES=$(notes "$FULL")
[ -n "$NOTES" ] || NOTES=$(notes "$BASE")
NOTES=$(printf '%s' "$NOTES" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' | head -c 1700)
[ -n "$NOTES" ] || NOTES="See the changelog on CurseForge."

case "$TAG" in
  *-alpha) KIND="alpha" ;;
  *-beta) KIND="beta" ;;
  *) KIND="release" ;;
esac

# The addon's colour from the Allemano brand library.
case "$CFID" in
  1719062|1719071|1719074|1719076) HEX=35C6D6 ;; # Hush and its modules
  1719158) HEX=4F7FFF ;;                         # AltBoard
  1719141) HEX=E5484D ;;                         # Allemano Raid Tools
  1719167) HEX=E8A93A ;;                         # Session Tracker
  1719025) HEX=F0763A ;;                         # CraftBoard
  1719135) HEX=45C97E ;;                         # Arbiter Loot Council
  *) HEX=ECEDEF ;;                               # Hub and anything else
esac
COLOR=$((16#$HEX))
URL="https://www.curseforge.com/projects/$CFID"

if [ -n "${DRY_RUN:-}" ]; then
  echo "title:  $TITLE $FULL"
  echo "url:    $URL"
  echo "color:  $COLOR ($HEX)"
  echo "kind:   $KIND"
  echo "notes:"
  echo "$NOTES"
  exit 0
fi

jq -n \
  --arg title "$TITLE $FULL" \
  --arg description "$NOTES" \
  --arg url "$URL" \
  --arg footer "Allemano Addons · WoW: Forever · $KIND" \
  --argjson color "$COLOR" \
  '{username: "Allemano Addons", embeds: [{title: $title, url: $url, description: $description, color: $color, footer: {text: $footer}}]}' |
  curl -fsS -H "Content-Type: application/json" -d @- "$DISCORD_WEBHOOK"
echo "Announced $TITLE $FULL on Discord."
