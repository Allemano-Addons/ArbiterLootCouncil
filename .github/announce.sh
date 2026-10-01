#!/usr/bin/env bash
# Posts a short release note to the Discord #releases channel. Runs from the release workflow after the
# packager has uploaded the files. The webhook URL is the repository (or organisation) secret
# DISCORD_RELEASES_WEBHOOK; without it nothing is posted. DRY_RUN=1 prints the message instead of sending it.
set -euo pipefail

SITE_URL="https://allemano-site.pages.dev"   # change here when the site gets its own domain
MAX_CHARS=3400                               # Discord allows 4096 in an embed description

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
# Drop empty lines at the ends, then keep whole lines up to the limit.
NOTES=$(printf '%s\n' "$NOTES" | sed -e '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
CUT=0
NOTES=$(printf '%s\n' "$NOTES" | awk -v max="$MAX_CHARS" '
  { if (total + length($0) + 1 > max) { cut = 1; exit } print; total += length($0) + 1 }
  END { if (cut) print "…" }')
case "$NOTES" in *"…") CUT=1 ;; esac
[ -n "$NOTES" ] || NOTES="See the changelog."

case "$TAG" in
  *-alpha) KIND="alpha" ;;
  *-beta) KIND="beta" ;;
  *) KIND="release" ;;
esac

# The addon's colour from the Allemano brand library, and its page on the website.
case "$CFID" in
  1719062|1719071|1719074|1719076) HEX=35C6D6; SLUG=hush ;;  # Hush and its modules
  1719158) HEX=4F7FFF; SLUG=altboard ;;
  1719141) HEX=E5484D; SLUG=art ;;
  1719167) HEX=E8A93A; SLUG=session-tracker ;;
  1719025) HEX=F0763A; SLUG=craftboard ;;
  1719135) HEX=45C97E; SLUG=alc ;;
  1719519) HEX=ECEDEF; SLUG=hub ;;
  *) HEX=ECEDEF; SLUG="" ;;
esac
COLOR=$((16#$HEX))
CF_URL="https://www.curseforge.com/projects/$CFID"
if [ -n "$SLUG" ]; then PAGE_URL="$SITE_URL/addons/$SLUG#changelog"; else PAGE_URL="$CF_URL"; fi

# The links at the foot of the message.
LINKS="[Download on CurseForge]($CF_URL)"
[ -n "$SLUG" ] && LINKS="$LINKS · [All changes]($PAGE_URL)"
DESCRIPTION="$NOTES"$'\n\n'"$LINKS"

if [ -n "${DRY_RUN:-}" ]; then
  echo "title:  $TITLE $FULL"
  echo "url:    $PAGE_URL"
  echo "color:  $COLOR ($HEX)"
  echo "kind:   $KIND  cut: $CUT"
  echo "description (${#DESCRIPTION} characters):"
  echo "$DESCRIPTION"
  exit 0
fi

jq -n \
  --arg title "$TITLE $FULL" \
  --arg description "$DESCRIPTION" \
  --arg url "$PAGE_URL" \
  --arg footer "Allemano Addons · WoW: Forever · $KIND" \
  --argjson color "$COLOR" \
  '{username: "Allemano Addons", embeds: [{title: $title, url: $url, description: $description, color: $color, footer: {text: $footer}}]}' |
  curl -fsS -H "Content-Type: application/json" -d @- "$DISCORD_WEBHOOK"
echo "Announced $TITLE $FULL on Discord."
