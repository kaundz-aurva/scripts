# sfbench

Builds a local Postgres copy of the Aurva `sensitive_fields` table at production shape, for benchmarking
queries like the `datasources.sensitive_state` rollup. The default run gives ~35M rows across 2,500
datasources, ~28.6M `sensitivefield_tags` links and ~24GB with indexes. The original build took about 2h.

## Correlation warning

Rows have to be physically clustered by datasource: `pg_stats.correlation` for `datasource_identifier`
should be about 1.0. An earlier corpus loaded datasources round-robin, got a correlation of 0.02, and gave
badly wrong benchmark numbers (every per-datasource query touched pages all over the heap). The generator
writes one datasource at a time and `load_chunks.sh` loads them in order. Keep it that way.
`bench.sh` prints the correlation first. Check it before you trust any timing.

## Run

```sh
./load_chunks.sh                          # full corpus into DB=sfbench (refuses if the DB exists)
START_CHUNK=4 ./load_chunks.sh            # resume from chunk 4 (each chunk is one transaction)
DB=sfbench ./bench.sh                     # EXPLAIN (ANALYZE, BUFFERS) of the key queries, read-only
```

Small corpus in a few seconds:

```sh
DB=sfbench_small NUM_DATASOURCES=50 BASE_ROWS=2000 CHUNK_SIZE=10 ./load_chunks.sh
```

| env | default | meaning |
|---|---|---|
| `DB` | `sfbench` | database to create/load |
| `PGURL` | `postgresql://postgres@localhost:5432` | server, without the db name |
| `NUM_DATASOURCES` | 2500 | datasources; ids are `lpad(to_hex(i),8,'0')\|\|'-0000-4000-8000-'\|\|lpad(to_hex(i),12,'0')` |
| `BASE_ROWS` | 9310 | rows in a small datasource. The first ~0.48% get 40x (372,400) and the rest of the first 5% get 8x |
| `CHUNK_SIZE` | 357 | datasources per transaction |
| `START_CHUNK` | 0 | resume point. 0 creates the DB and schema |
| `SEED` | 42 | corpus seed |

Output is deterministic. Each datasource uses its own RNG, seeded with `(SEED, index)`, so any chunking
produces byte-identical rows. Check with `./gen_sfbench -n 50 -base 2000 | shasum` against concatenated
`-from/-to` ranges.

## Shape (matches the original sfbench pg_stats)

- status is 40/35/23/2 skipped/confirmed/pending/rejected. Skipped and rejected rows have
  `semantic_types = {}` and risk/confidence 0. Confirmed rows carry 1-3 types with confidence 80-100;
  pending rows carry the same with confidence 40-79.
- `risk` is the max of the fixed per-type risk. `sensitivity` comes from risk: >=7 → 0, 5-6 → 1,
  otherwise 2. Tags are the distinct categories of the types (Identity/Financial/Health/Contact/Technical).
- `scan_id` is one value per datasource, 1-12. About 3% of rows are soft-deleted (`deleted_at` 1-720h
  before `created_at`). About 4% are `dirty`. About 2% of datasources are archived as a whole, never a
  fat one.
- Each table has 20-30 columns (`col_NN`), there are 40 tables per `db_NNN`, and `row_count` is uniform
  from 100 to 5M.
- `datasources` gets one row per generated id, with `sensitive_state` backfilled using the same rollup as
  the migration.

The original sfbench DB's `datasources` table has 2,000 random v4 ids that don't match any
`datasource_identifier` and has no `sensitive_state` column. This rebuild fixes that, so the
`id IN (SELECT ...)` benchmark actually joins.
