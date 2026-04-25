#!/usr/bin/env bash
# Build list.lst by merging list.manual.lst with domains extracted from
# runetfreedom/russia-v2ray-rules-dat geosite.dat.
#
# Usage: bash scripts/build.sh
#
# Requires: bash, curl, jq, sha256sum, awk, sort. gh CLI is optional (used as
# fallback if curl rate-limits on api.github.com).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CACHE_DIR="cache"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

GEOVIEW_VERSION="${GEOVIEW_VERSION:-0.2.5}"
GEOVIEW_BIN="bin/geoview"
GEOSITE_REPO="runetfreedom/russia-v2ray-rules-dat"

mkdir -p "$CACHE_DIR" "bin" "$TMP_DIR/extracted"

# ---------- 1. Download geoview if absent ----------
if [[ ! -x "$GEOVIEW_BIN" ]]; then
    echo "==> Fetching geoview ${GEOVIEW_VERSION}..."
    arch="$(uname -m)"
    case "$arch" in
        x86_64) gv_arch="amd64" ;;
        aarch64|arm64) gv_arch="arm64" ;;
        *) echo "Unsupported arch: $arch" >&2; exit 1 ;;
    esac
    curl -fsSL -o "$GEOVIEW_BIN" \
        "https://github.com/snowie2000/geoview/releases/download/${GEOVIEW_VERSION}/geoview-linux-${gv_arch}"
    chmod +x "$GEOVIEW_BIN"
fi

# ---------- 2. Download latest geosite.dat from runetfreedom ----------
echo "==> Resolving latest runetfreedom release..."
release_json="$(curl -fsSL "https://api.github.com/repos/${GEOSITE_REPO}/releases/latest")"
geosite_url="$(echo "$release_json" | jq -r '.assets[] | select(.name=="geosite.dat") | .browser_download_url')"
sha_url="$(echo "$release_json" | jq -r '.assets[] | select(.name=="geosite.dat.sha256sum") | .browser_download_url')"
tag="$(echo "$release_json" | jq -r '.tag_name')"
echo "    tag: $tag"

curl -fsSL -o "$CACHE_DIR/geosite.dat" "$geosite_url"
curl -fsSL -o "$CACHE_DIR/geosite.dat.sha256sum" "$sha_url"

echo "==> Verifying sha256..."
( cd "$CACHE_DIR" && sha256sum -c geosite.dat.sha256sum )

# ---------- 3. Extract each category ----------
echo "==> Extracting categories..."
matched=0
missed=0
while IFS= read -r line; do
    cat="${line%%#*}"               # strip inline comments
    cat="$(echo "$cat" | xargs)"    # trim whitespace
    [[ -z "$cat" ]] && continue
    out="$TMP_DIR/extracted/$cat.txt"
    if "$GEOVIEW_BIN" -type geosite -input "$CACHE_DIR/geosite.dat" \
        -list "$cat" -strict=false -output "$out" >/dev/null 2>&1 \
        && [[ -s "$out" ]]; then
        n=$(wc -l < "$out")
        printf '    [+] %-25s %6d\n' "$cat" "$n"
        matched=$((matched + 1))
    else
        printf '    [-] %-25s (skipped — not in geosite)\n' "$cat"
        missed=$((missed + 1))
    fi
done < scripts/categories.txt

echo "    matched: $matched, skipped: $missed"

# ---------- 4. Normalize extracted output ----------
# Drop regex/keyword/attribute lines, strip domain:/full: prefixes,
# lowercase, trim, dedup.
echo "==> Normalizing extracted domains..."
normalized="$TMP_DIR/extracted-normalized.txt"
# `awk 1` instead of `cat` — geoview omits the trailing newline on the last
# line of each file, so cat would merge "last-of-A" with "first-of-B".
shopt -s nullglob
extracted_files=("$TMP_DIR/extracted/"*.txt)
shopt -u nullglob
awk 1 "${extracted_files[@]}" \
    | awk '
        /^[[:space:]]*$/ { next }
        /^#/ { next }
        /@/ { next }                              # drop @cn / @ads / etc.
        /^keyword:/ { next }
        /^regexp:/ { next }
        /xn--/ { next }                           # GL.iNet rejects punycode IDNs
        {
            sub(/^domain:/, "")
            sub(/^full:/, "")
            sub(/[[:space:]].*$/, "")             # drop trailing tokens
            $0 = tolower($0)
            if ($0 ~ /^[a-z0-9._-]+\.[a-z0-9._-]+$/) print
            else if ($0 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?$/) print
        }
    ' \
    | LC_ALL=C sort -u > "$normalized"
echo "    extracted unique: $(wc -l < "$normalized")"

# ---------- 5. Normalize manual list and merge ----------
manual_norm="$TMP_DIR/manual-normalized.txt"
awk '
    /^[[:space:]]*$/ { next }
    /^#/ { next }
    {
        sub(/[[:space:]].*$/, "")
        $0 = tolower($0)
        if ($0 ~ /^[a-z0-9._-]+\.[a-z0-9._-]+$/) print
            else if ($0 ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}(\/[0-9]{1,2})?$/) print
    }
' list.manual.lst | LC_ALL=C sort -u > "$manual_norm"

merged="$TMP_DIR/merged.txt"
LC_ALL=C sort -u "$manual_norm" "$normalized" > "$merged"

# ---------- 6. Collapse subdomain redundancy ----------
# If foo.com is in the set, drop *.foo.com (GL.iNet root match wildcards
# subdomains, so the longer entry is redundant). Two-pass: lexicographic
# sort puts children before parents (fonts.googleapis.com < googleapis.com),
# so we must materialize the full set before filtering.
echo "==> Collapsing redundant subdomains..."
collapsed="$TMP_DIR/collapsed.txt"
awk '
    NR == FNR { all[$0] = 1; next }
    {
        n = split($0, parts, ".")
        for (i = 2; i <= n - 1; i++) {
            suffix = parts[i]
            for (j = i + 1; j <= n; j++) suffix = suffix "." parts[j]
            if (suffix in all) next
        }
        print
    }
' "$merged" "$merged" > "$collapsed"

echo "    before collapse: $(wc -l < "$merged")"
echo "    after collapse:  $(wc -l < "$collapsed")"

# ---------- 7. Write list.lst ----------
mv "$collapsed" list.lst
echo "==> list.lst: $(wc -l < list.lst) entries"
