# gl-domains-list

Domain list for [GL.iNet routers](https://docs.gl-inet.com/router/en/4/tutorials/how_to_configure_domain_and_ip_filtering_rules_for_glinet_routers_via_an_online_text_file/) (VPN Policy / Parental Control via online text file).

The published list is `list.lst`. Subscribe in the GL.iNet UI:

```
https://raw.githubusercontent.com/lvLokkie/gl-domains-list/main/list.lst
```

## Files

| File | Purpose |
|---|---|
| `list.lst` | **Auto-generated.** Union of `list.manual.lst` and domains extracted from runetfreedom geosite.dat for the categories in `scripts/categories.txt`. Subdomain-redundant entries are collapsed (`foo.com` already wildcards `*.foo.com`). Sorted, lower-cased, deduped. |
| `list.manual.lst` | Hand-curated entries. Edit this file to add/remove domains permanently. |
| `scripts/categories.txt` | One v2ray geosite category per line (e.g. `youtube`, `meta`, `openai`). Comments with `#`. Unknown categories are skipped silently. |
| `scripts/build.sh` | The pipeline. Downloads `geosite.dat` from the latest [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) release, extracts domains via [`geoview`](https://github.com/snowie2000/geoview), normalizes for GL.iNet format (drops `regexp:` / `keyword:` / `@attribute` entries, strips `domain:` / `full:` prefixes), merges with the manual list. |
| `.github/workflows/update-list.yml` | Daily cron (04:30 UTC) + `workflow_dispatch`. Commits `list.lst` directly to `main` when it changes. |

## Format

Plain text, one entry per line, per [GL.iNet docs](https://docs.gl-inet.com/router/en/4/tutorials/how_to_configure_domain_and_ip_filtering_rules_for_glinet_routers_via_an_online_text_file/):

- `netflix.com` — root domain, matches all subdomains
- `www.netflix.com` — exact subdomain only

No protocols, no paths, no comments inside `list.lst`. (`list.manual.lst` and `categories.txt` allow `#` comments — they're stripped by `build.sh`.)

## Local run

```bash
bash scripts/build.sh
```

Requires: `bash`, `curl`, `jq`, `sha256sum`, `awk`, `sort`. `geoview` and `geosite.dat` are downloaded into `bin/` and `cache/` (both gitignored, see `.gitignore`).

## Adding categories

Edit `scripts/categories.txt`, commit, push. The next scheduled run picks them up. To preview locally:

```bash
bash scripts/build.sh
diff <(git show HEAD:list.lst) list.lst | head -50
```

To find available categories, browse [v2fly/domain-list-community/data](https://github.com/v2fly/domain-list-community/tree/master/data) (every file there is a category) or look up a known domain:

```bash
./bin/geoview -type geosite -input cache/geosite.dat -action lookup -value chatgpt.com
```

## Why runetfreedom

`runetfreedom/russia-v2ray-rules-dat` re-publishes the v2fly community geosite **every 6 hours** with extra Russia-focused categories (`ru-blocked`, `win-spy`, etc.). Distributed format is binary `geosite.dat` — `build.sh` parses it with `geoview` and emits the GL.iNet-compatible plain-text format.
