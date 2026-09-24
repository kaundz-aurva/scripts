#!/usr/bin/env bash
# Runs the sensitive_state queries with EXPLAIN (ANALYZE, BUFFERS). Read-only; safe against any sfbench-shaped DB.
# Usage: DB=sfbench ./bench.sh
set -euo pipefail

DB=${DB:-sfbench}
PGURL=${PGURL:-postgresql://postgres@localhost:5432}
FATTEST=${FATTEST:-00000000-0000-4000-8000-000000000000}  # index 0 is always in the 40x tier

q() { echo; echo "== $1"; psql -X -v ON_ERROR_STOP=1 "$PGURL/$DB" -c "EXPLAIN (ANALYZE, BUFFERS) $2"; }

psql -X "$PGURL/$DB" -c "SELECT attname, n_distinct, round(correlation::numeric, 4) AS correlation
  FROM pg_stats WHERE tablename = 'sensitive_fields' AND attname IN ('datasource_identifier', 'status', 'scan_id')"

q "rollup for fattest datasource ($FATTEST)" "
SELECT datasource_identifier,
       bool_or(status = 'confirmed' AND cardinality(semantic_types) > 0),
       bool_or(status = 'pending'), bool_or(status = 'skipped'), bool_or(status = 'rejected')
FROM sensitive_fields
WHERE datasource_identifier IN ('$FATTEST') AND deleted_at IS NULL AND is_archived = false
GROUP BY datasource_identifier"

q "old predicate: id IN (SELECT datasource_identifier FROM sensitive_fields ...)" "
SELECT count(*) FROM datasources
WHERE deleted_at = 0 AND id IN (SELECT datasource_identifier FROM sensitive_fields sf WHERE is_archived = false)"

has_col=$(psql -X -At "$PGURL/$DB" -c "SELECT count(*) FROM information_schema.columns
  WHERE table_name = 'datasources' AND column_name = 'sensitive_state'")
if [ "$has_col" = 1 ]; then
  q "new: sensitive_state column read" "
SELECT count(*) FROM datasources WHERE deleted_at = 0 AND sensitive_state = 'SENSITIVE'"
else
  echo; echo "== datasources.sensitive_state missing in $DB, skipping column-read query"
fi
