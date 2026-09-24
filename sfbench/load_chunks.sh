#!/usr/bin/env bash
# Builds the sfbench corpus datasource-by-datasource (keeps datasource_identifier correlation ~1.0).
# Usage: ./load_chunks.sh                      # full 2500-datasource corpus into DB=sfbench (~35M rows)
#        START_CHUNK=4 ./load_chunks.sh        # resume; each chunk is one transaction, so a failed chunk left nothing
#        DB=sfbench_small NUM_DATASOURCES=50 BASE_ROWS=2000 ./load_chunks.sh
set -euo pipefail
cd "$(dirname "$0")"

DB=${DB:-sfbench}
PGURL=${PGURL:-postgresql://postgres@localhost:5432}
NUM_DATASOURCES=${NUM_DATASOURCES:-2500}
CHUNK_SIZE=${CHUNK_SIZE:-357}
BASE_ROWS=${BASE_ROWS:-9310}
SEED=${SEED:-42}
START_CHUNK=${START_CHUNK:-0}

psql_db() { psql -X -q -v ON_ERROR_STOP=1 "$PGURL/$DB" "$@"; }

if [ "$START_CHUNK" -eq 0 ]; then
  # CREATE DATABASE fails if the DB exists: never clobber an existing corpus.
  psql -X -v ON_ERROR_STOP=1 "$PGURL/postgres" -c "CREATE DATABASE \"$DB\""
  psql_db -1 -f schema.sql
fi

go build -o gen_sfbench .
GEN="./gen_sfbench -n $NUM_DATASOURCES -base $BASE_ROWS -seed $SEED"
COLS="id, datasource_identifier, scan_id, status, risk, sensitivity, confidence, semantic_types, field_name, table_name, database_name, row_count, first_found, created_at, updated_at, deleted_at, dirty, is_archived"

chunks=$(( (NUM_DATASOURCES + CHUNK_SIZE - 1) / CHUNK_SIZE ))
for (( c = START_CHUNK; c < chunks; c++ )); do
  from=$(( c * CHUNK_SIZE ))
  to=$(( from + CHUNK_SIZE < NUM_DATASOURCES ? from + CHUNK_SIZE : NUM_DATASOURCES ))
  echo "$(date +%T) chunk $c/$((chunks - 1)): datasources [$from, $to)"
  psql_db -1 \
    -c "\\copy sensitive_fields ($COLS) FROM PROGRAM '$GEN -from $from -to $to'" \
    -c "\\copy sensitivefield_tags FROM PROGRAM '$GEN -from $from -to $to -tags'"
done

echo "$(date +%T) datasources + indexes"
psql_db -1 -v n="$NUM_DATASOURCES" -f - <<'SQL'
INSERT INTO datasources (id, name, host, port, type, deleted_at, scan_id, created_at, updated_at)
SELECT lpad(to_hex(i), 8, '0') || '-0000-4000-8000-' || lpad(to_hex(i), 12, '0'),
       'ds-' || lpad(i::text, 4, '0'), 'host-' || lpad(i::text, 4, '0') || '.internal',
       (5432 + i)::text, 1 + i % 40, 0, 1, now(), now()
FROM generate_series(0, :n - 1) i;
\i indexes.sql
SQL

echo "$(date +%T) sensitive_state backfill + ANALYZE"
psql_db <<'SQL'
UPDATE datasources d
SET sensitive_state = CASE
        WHEN sf.has_confirmed THEN 'SENSITIVE'
        WHEN sf.has_pending   THEN 'POTENTIALLY_SENSITIVE'
        WHEN sf.has_skipped   THEN 'ALL_SKIPPED'
        WHEN sf.has_rejected  THEN 'ALL_REJECTED'
        ELSE 'NONE' END,
    sensitive_state_updated_at = now()
FROM datasources d0
LEFT JOIN (
    SELECT datasource_identifier,
           bool_or(status = 'confirmed' AND cardinality(semantic_types) > 0) AS has_confirmed,
           bool_or(status = 'pending')  AS has_pending,
           bool_or(status = 'skipped')  AS has_skipped,
           bool_or(status = 'rejected') AS has_rejected
    FROM sensitive_fields
    WHERE deleted_at IS NULL AND is_archived = false
    GROUP BY datasource_identifier
) sf ON sf.datasource_identifier = d0.id
WHERE d.id = d0.id;
VACUUM ANALYZE;
SQL
echo "$(date +%T) done: $DB"
