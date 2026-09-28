#!/usr/bin/env bash
# add_firefox_bookmarks.sh
# Adds OpenShift/ACM bookmarks to the default Firefox profile on Linux.
# Requires: python3 (for the SQLite JSON update)

set -euo pipefail

# ---------------------------------------------------------------------------
# Bookmarks to add
# ---------------------------------------------------------------------------
declare -A BOOKMARKS
BOOKMARKS=(
  ["ACM Hub – Clusters"]="https://console-openshift-console.apps.sts-pok-hci00bm-ocp-3acm1.pbm.ihost.com/"
  ["ACM Hub – Managed Clusters"]="https://console-openshift-console.apps.sts-pok-hci00bm-ocp-3acm2.pbm.ihost.com/multicloud/infrastructure/clusters/managed"
  ["OCP ocp1hcp1 – Dashboard"]="https://console-openshift-console.apps.ocp1hcp1.pbm.ihost.com/dashboards"
  ["OCP ocp1hcp2 – Dashboard"]="https://console-openshift-console.apps.ocp1hcp2.pbm.ihost.com/dashboards"
  ["OCP ocp-3ocp2 – Dashboard"]="https://console-openshift-console.apps.sts-pok-hci00bm-ocp-3ocp2.pbm.ihost.com/dashboards"
  ["OCP ocp-3ocp1 – Dashboard"]="https://console-openshift-console.apps.sts-pok-hci00bm-ocp-3ocp1.pbm.ihost.com/dashboards"
)

# ---------------------------------------------------------------------------
# Locate the default Firefox profile directory
# ---------------------------------------------------------------------------
FIREFOX_DIR="$HOME/.mozilla/firefox"

if [[ ! -d "$FIREFOX_DIR" ]]; then
  echo "ERROR: Firefox profile directory not found at $FIREFOX_DIR"
  exit 1
fi

# Pick the first profile marked default-release, then fall back to any .default*
PROFILE_DIR=$(
  awk -F= '/^Default=/ && /default-release/ { print $2; exit }
           /^Default=/ { def=$2 }
           END { if (def) print def }' \
    "$FIREFOX_DIR/profiles.ini" 2>/dev/null || true
)

if [[ -z "$PROFILE_DIR" ]]; then
  # Last resort: first directory whose name ends in .default*
  PROFILE_DIR=$(find "$FIREFOX_DIR" -maxdepth 1 -name '*.default*' -type d \
                  | head -n1 | xargs basename 2>/dev/null || true)
fi

if [[ -z "$PROFILE_DIR" ]]; then
  echo "ERROR: Could not locate a Firefox profile under $FIREFOX_DIR"
  exit 1
fi

# Handle both relative and absolute paths stored in profiles.ini
if [[ "$PROFILE_DIR" != /* ]]; then
  PROFILE_DIR="$FIREFOX_DIR/$PROFILE_DIR"
fi

PLACES_DB="$PROFILE_DIR/places.sqlite"

if [[ ! -f "$PLACES_DB" ]]; then
  echo "ERROR: places.sqlite not found at $PLACES_DB"
  echo "Make sure Firefox has been launched at least once to create the profile."
  exit 1
fi

echo "Using profile: $PROFILE_DIR"

# ---------------------------------------------------------------------------
# Warn if Firefox is running (writes may be lost or corrupt)
# ---------------------------------------------------------------------------
if pgrep -x firefox &>/dev/null; then
  echo "WARNING: Firefox is currently running."
  echo "         Close Firefox before continuing to avoid data loss."
  read -r -p "Continue anyway? [y/N] " answer
  [[ "${answer,,}" == "y" ]] || { echo "Aborted."; exit 0; }
fi

# ---------------------------------------------------------------------------
# Insert bookmarks via Python + sqlite3 module
# ---------------------------------------------------------------------------
python3 - "$PLACES_DB" <<'PYEOF'
import sqlite3, sys, time

db_path = sys.argv[1]
con = sqlite3.connect(db_path)
cur = con.cursor()

# Resolve the id of the "Bookmarks Toolbar" root (guid = 'toolbar_____')
cur.execute("SELECT id FROM moz_bookmarks WHERE guid = 'toolbar_____'")
row = cur.fetchone()
if not row:
    # Fall back to the generic bookmarks root
    cur.execute("SELECT id FROM moz_bookmarks WHERE parent = 1 AND title = 'Bookmarks Menu' LIMIT 1")
    row = cur.fetchone()
if not row:
    cur.execute("SELECT id FROM moz_bookmarks WHERE parent = 1 LIMIT 1")
    row = cur.fetchone()

toolbar_id = row[0]

# Create an "OpenShift" folder inside the toolbar
now_micro = int(time.time() * 1_000_000)
cur.execute("""
    INSERT INTO moz_bookmarks (type, parent, position, title, dateAdded, lastModified, guid)
    VALUES (2, ?, (SELECT COALESCE(MAX(position)+1,0) FROM moz_bookmarks WHERE parent=?),
            'OpenShift', ?, ?, lower(hex(randomblob(9))))
""", (toolbar_id, toolbar_id, now_micro, now_micro))
folder_id = cur.lastrowid

BOOKMARKS = [
    ("ACM Hub – Clusters",          "https://console-openshift-console.apps.sts-pok-hci00bm-ocp-3acm1.pbm.ihost.com/"),
    ("ACM Hub – Managed Clusters",  "https://console-openshift-console.apps.sts-pok-hci00bm-ocp-3acm2.pbm.ihost.com/multicloud/infrastructure/clusters/managed"),
    ("OCP ocp1hcp1 – Dashboard",    "https://console-openshift-console.apps.ocp1hcp1.pbm.ihost.com/dashboards"),
    ("OCP ocp1hcp2 – Dashboard",    "https://console-openshift-console.apps.ocp1hcp2.pbm.ihost.com/dashboards"),
    ("OCP ocp-3ocp2 – Dashboard",   "https://console-openshift-console.apps.sts-pok-hci00bm-ocp-3ocp2.pbm.ihost.com/dashboards"),
    ("OCP ocp-3ocp1 – Dashboard",   "https://console-openshift-console.apps.sts-pok-hci00bm-ocp-3ocp1.pbm.ihost.com/dashboards"),
]

for pos, (title, url) in enumerate(BOOKMARKS):
    # Upsert the URL into moz_places
    cur.execute("SELECT id FROM moz_places WHERE url = ?", (url,))
    place = cur.fetchone()
    if place:
        place_id = place[0]
    else:
        cur.execute("""
            INSERT INTO moz_places (url, title, rev_host, visit_count, hidden, typed, guid)
            VALUES (?, ?, ?, 0, 0, 0, lower(hex(randomblob(9))))
        """, (url, title, url[::-1].split('/')[0] + '.'))
        place_id = cur.lastrowid

    # Insert the bookmark
    cur.execute("""
        INSERT INTO moz_bookmarks (type, fk, parent, position, title, dateAdded, lastModified, guid)
        VALUES (1, ?, ?, ?, ?, ?, ?, lower(hex(randomblob(9))))
    """, (place_id, folder_id, pos, title, now_micro, now_micro))

con.commit()
con.close()
print(f"Done — added {len(BOOKMARKS)} bookmarks in an 'OpenShift' toolbar folder.")
PYEOF
