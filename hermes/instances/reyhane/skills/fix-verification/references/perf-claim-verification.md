# Verifying performance claims (SQL / PostgreSQL)

When an issue says "this query cannot use the index" or "this job runs twice",
settle it against a real database — plans and `EXPLAIN` output are cheap to get
and they are the only evidence that survives review.

## Connect without printing a credential

```bash
cd <repo> && set -a && . ./.env && set +a
export PGPASSWORD="$DB_PASSWORD"
psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USERNAME" -d "$DB_DATABASE" -X -q -c "..."
```

The value never reaches the transcript because only `$VAR` is written. Never
paste a credential value into a comment or report.

## Index claims

- **List indexes by table, not by name prefix.** `\di persons*` matches only
  names that start with `persons` and silently hides `idx_persons_*`:

  ```sql
  SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'persons';
  ```

- **Prove whether a predicate is index-eligible** with `EXPLAIN` under
  `SET enable_seqscan=off;`. A plan line `Seq Scan on t (cost=10000000000.00…)`
  means the planner found **no** index path for that predicate — that is the
  negative result you are looking for.
- **Test the arm, then the whole WHERE clause.** An expression can be perfectly
  index-backed in isolation (`Bitmap Index Scan on …_trgm_idx`) while the real
  query is a seq scan: a `BitmapOr` is only available when **every** OR arm has
  an index. One arm like `n_code LIKE '%x%'` with only a btree unique keeps the
  entire chain on a seq scan, and swapping `CONCAT()` for `||` in another arm
  changes nothing.
- **Expression indexes match on the expression tree.** `CONCAT(a,' ',b)` is a
  `STABLE` function call and can never match an index built on `(a || ' ' || b)`.
- **Prove the missing index is the blocker without mutating the schema** —
  create it inside a transaction and roll back:

  ```sql
  BEGIN;
  CREATE INDEX tmp_probe_idx ON persons USING GIN (n_code gin_trgm_ops);
  SET enable_seqscan=off;
  EXPLAIN SELECT id FROM persons WHERE n_code LIKE '%12%' OR (f_name || ' ' || l_name) LIKE '%12%';
  ROLLBACK;
  ```
  Running it from a `.sql` file (`psql -v ON_ERROR_STOP=1 -f probe.sql`) is what
  makes the output reliable — chained `-c` statements can come back empty.
  Showing `BitmapOr` here proves the fix, and showing the same query stays on a
  seq scan with the other arms present proves the plan's scope is too small.

## Before you trust any EXPLAIN

Confirm the schema you measured matches the repo. A working database can carry
indexes that **no migration creates** (hand-made during earlier experiments), so
"the index is already used in dev" is not evidence that a fresh deploy uses it —
and a recorded plan from such a database is not representative. Cross-check every
index named in a plan against `database/migrations/`.

## Reading a plan-in-issue's dev commands

Plans often tell the executor to run `docker compose up` + `psql` against the dev
DB. Run the read-only parts yourself and report the plan you actually got; a
plan whose Step-3 acceptance criterion cannot be met is a finding, not a
blocker to work around by adding an index the plan forbade.
