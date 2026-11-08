#!/usr/bin/env bash
# Inserts every row fixture into mox.current_file, each in its own
# rolled-back transaction. valid/* must be accepted and invalid/* rejected,
# which keeps the shared fixtures and the database constraints in agreement.
#
# Usage: shared/fixtures/check-rows.sh [database-url]
# Default URL is the local Supabase stack started by `supabase start`.
set -euo pipefail

DB_URL="${1:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
ROWS="$(cd "$(dirname "$0")/rows" && pwd)"
failures=0

check() {
    local expected="$1" file="$2" result output
    if output=$(psql "$DB_URL" -X -q -v ON_ERROR_STOP=1 -v row="$(cat "$file")" 2>&1 <<'SQL'
begin;
insert into mox.current_file
select * from json_populate_record(null::mox.current_file, :'row');
rollback;
SQL
    ); then result=valid; else result=invalid; fi

    if [[ "$result" == "$expected" ]]; then
        echo "ok    $expected/$(basename "$file")"
    else
        echo "FAIL  $expected/$(basename "$file") was $result"
        [[ -n "$output" ]] && echo "      $output"
        failures=$((failures + 1))
    fi
}

for f in "$ROWS"/valid/*.json; do check valid "$f"; done
for f in "$ROWS"/invalid/*.json; do check invalid "$f"; done

if (( failures > 0 )); then
    echo "$failures fixture(s) disagree with the schema" >&2
    exit 1
fi
echo "All fixtures agree with the schema."
