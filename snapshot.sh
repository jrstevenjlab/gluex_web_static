#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   COOKIE_JAR=./cookies.txt ENABLE_PAGEFIND=1 OBEY_ROBOTS=1 ./snapshot.sh urls.txt site
#
# Defaults:
URLS_FILE="${1:-urls.txt}"
OUT_DIR="${2:-site}"

mkdir -p "$OUT_DIR"

# ---- Tunables (env vars) ----
# Provide cookies for private pages (Netscape format; see earlier steps)
COOKIE_JAR="${COOKIE_JAR:-}"
# Respect robots by default; set to 0 ONLY if you have permission to crawl anyway
OBEY_ROBOTS="${OBEY_ROBOTS:-1}"
# Throttle so we don't look like a botnet
RATE_WAIT="${RATE_WAIT:-1}"
RANDOM_WAIT="${RANDOM_WAIT:-1}"
# Retries & timeouts
RETRIES="${RETRIES:-3}"
TIMEOUT="${TIMEOUT:-30}"
# Optional: build a JS offline search index after mirroring
ENABLE_PAGEFIND="${ENABLE_PAGEFIND:-0}"

# Use a modern desktop browser UA to avoid basic WAF blocks
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36'

# Robots handling
ROBOTS_OPT=$([ "$OBEY_ROBOTS" = "1" ] && echo "--execute robots=on" || echo "--execute robots=off")

if [ ! -f "$URLS_FILE" ]; then
  echo "URL list not found: $URLS_FILE" >&2
  exit 1
fi

echo "==> Snapshotting URLs from: $URLS_FILE"
echo "==> Output directory:       $OUT_DIR"
echo "==> Robots:                 $ROBOTS_OPT"
[ -n "$COOKIE_JAR" ] && echo "==> Using cookies from:     $COOKIE_JAR"

mirror_one () {
  local url="$1"
  echo ""
  echo "---- Mirroring: $url"

  # Important wget flags for a full, offline-browsable copy:
  #  --mirror              = -r -N -l inf -nr (recursive with timestamping)
  #  --convert-links       rewrite links to local files
  #  --adjust-extension    add .html where needed
  #  --page-requisites     grab images/CSS/JS used by pages
  #  --no-parent           don't climb above the given path
  #  --domains             stay on halldweb.jlab.org
  #  --trust-server-names  honor server's suggested filenames (helpful for cgi/params)
  #  --content-on-error    save error pages (for debugging)
  #  --recursive           (redundant with --mirror but explicit)
  #  --reject-regex        optionally skip logout/edit/search endpoints (safer snapshot)
  #
  # NOTE: We do NOT use --accept=... so we don't accidentally miss filetypes.
  # If you want to restrict types, add: --accept=html,htm,css,js,pdf,jpg,jpeg,png,gif,svg,ico,txt

  WGET_ARGS=(
    --mirror
    --recursive
    --convert-links
    --adjust-extension
    --page-requisites
    --no-parent
    --domains=halldweb.jlab.org
    --trust-server-names
    --content-on-error
    --timestamping
    --directory-prefix="$OUT_DIR"
    --user-agent="$UA"
    --referer="https://halldweb.jlab.org/"
    --server-response
    --tries="$RETRIES"
    --timeout="$TIMEOUT"
    --user=jrsteven
    --password=~Z3sjz3sj6
    $ROBOTS_OPT
    # Skip obviously dynamic endpoints that won't work offline anyway (optional but recommended)
    --reject-regex 'logout|action=edit|action=submit|Special:|search\.cgi|/cgi-bin/|ShowCalendar|ListEvents|RetrieveArchive'
  )

  # Cookies for private areas (wiki-private/doc-private)
  if [ -n "$COOKIE_JAR" ] && [ -f "$COOKIE_JAR" ]; then
    WGET_ARGS+=( --load-cookies="$COOKIE_JAR" --keep-session-cookies )
  fi

  # Politeness
  if [ "$RANDOM_WAIT" = "1" ]; then
    WGET_ARGS+=( --wait="$RATE_WAIT" --random-wait )
  else
    WGET_ARGS+=( --wait="$RATE_WAIT" )
  fi

  # Run wget; save a log alongside the site for inspection
  local safe_name
  safe_name="$(echo "$url" | sed 's#[^A-Za-z0-9._-]#_#g')"
  wget "${WGET_ARGS[@]}" "$url" 2>&1 | tee -a "$OUT_DIR/wget_${safe_name}.log"
}

# Iterate URLs
while IFS= read -r url; do
  [[ -z "$url" || "$url" =~ ^# ]] && continue
  mirror_one "$url"
done < "$URLS_FILE"

# Generate a simple landing page
INDEX="$OUT_DIR/index.html"
cat > "$INDEX" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>HALld Offline Snapshot</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>body{font-family:system-ui;margin:2rem;line-height:1.5}li{margin:.35rem 0}</style>
<h1>HALld Offline Snapshot</h1>
<p>Choose a section (or browse the folder tree):</p>
<ul>
  <li><a href="/wiki/index.php">Public Wiki</a></li>
  <li><a href="/wiki-private/index.php">Private Wiki</a></li>
  <li><a href="/doc-public/DocDB/DocumentDatabase">DocDB (Public)</a></li>
  <li><a href="/doc-private/DocDB/DocumentDatabase">DocDB (Private)</a></li>
</ul>
<p><em>Note:</em> This is a static mirror. Live search/forms may not work offline.</p>
HTML

# Optional: offline search index (client-side)
if [ "$ENABLE_PAGEFIND" = "1" ]; then
  echo "==> Building offline search index with Pagefind..."
  if command -v npx >/dev/null 2>&1; then
    npx --yes pagefind --site "$OUT_DIR" || echo "Pagefind failed (continuing)."
  else
    echo "npx not found; skipping Pagefind. Install Node.js to enable it."
  fi
fi

echo ""
echo "✅ Snapshot complete → $OUT_DIR"
echo "   You can serve it locally with:  python3 -m http.server -d $OUT_DIR 8080"

