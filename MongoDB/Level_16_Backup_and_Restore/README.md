# Level 16 — Backup & Restore

**Goal:** back up and restore MongoDB with the Database Tools (`mongodump` / `mongorestore` for BSON backups, `mongoexport` / `mongoimport` for JSON/CSV data exchange), understand what each preserves and loses, do point-in-time backups with the oplog, and know the strategies used in production (snapshots, Atlas, Ops Manager, RPO/RTO, restore drills).

**Time:** ~1.5 hr · **Files:** `01_Practice_Backup_Restore.ps1` (PowerShell, runs the tools inside the Docker container) → `Exercises.ps1` · sample files in `data/`

---

## 1. Concepts in plain words

| Tool | Format | Preserves | Use for |
|------|--------|-----------|---------|
| **`mongodump`** | BSON (`.bson`) + `.metadata.json` per collection (indexes, options, collation) | **all BSON types**, indexes (rebuilt on restore), collection options, users/roles when dumping `admin` | backups of small–medium deployments, copying a database, moving between servers/versions |
| **`mongorestore`** | reads a dump directory or `--archive` | — | restore whole instance / one db / one collection; rename with `--nsFrom/--nsTo`; `--drop` first |
| **`mongoexport`** | JSON (Extended JSON v2) or CSV | JSON: types via `$date`, `$oid`, `$numberLong`… (canonical) or relaxed; CSV: **everything becomes text**, nested fields need dot paths | data exchange with other systems, spreadsheets, quick looks |
| **`mongoimport`** | JSON / CSV / TSV | JSON keeps types; CSV → strings unless `--columnsHaveTypes` | loading files, migrations from other databases; `--mode insert | upsert | merge | delete` |
| **Filesystem / volume snapshots** | disk image | everything, instantly | large deployments; needs journaling on, and a consistent snapshot of `dbPath` (LVM / EBS / Docker volume); replica set: snapshot a secondary or use `fsyncLock` on a hidden member |
| **Atlas / Ops Manager backups** | continuous (oplog-based) | point-in-time restore, scheduled snapshots, retention | production, sharded clusters (coordinated across shards) |

### Key options

- `mongodump --db X --collection Y --query '{...}' / --queryFile`, `--out dir`, `--gzip`, `--archive=file` (single stream, pipeable), `--oplog` (replica set only, whole instance: captures oplog entries during the dump → consistent point-in-time dump), `--numParallelCollections`, `--readPreference secondary`.
- `mongorestore dir`, `--db`/`--nsInclude "db.coll"`, `--nsFrom "a.*" --nsTo "b.*"`, `--drop` (drop target collections first), `--gzip --archive=file`, `--oplogReplay` (apply the captured oplog → point in time of the dump end), `--noIndexRestore`, `--maintainInsertionOrder`, `--numInsertionWorkersPerCollection`.
- `mongoexport --jsonArray --pretty`, `--type csv --fields a,b,c.d` (or `--fieldFile`), `--query`, `--sort`, `--limit`, `--jsonFormat canonical|relaxed`.
- `mongoimport --type csv --headerline` (first line = field names), `--fields`, `--columnsHaveTypes` (header like `age.int32(),joined.date(2006-01-02)`), `--jsonArray`, `--mode upsert --upsertFields _id`, `--drop`, `--ignoreBlanks`.
- All tools: `--uri "mongodb://user:pw@host:27017/?authSource=admin"` or `--host/--port/-u/-p/--authenticationDatabase`; run inside Docker with `docker exec <container> mongodump …` and move files with `docker cp`, or install the [Database Tools](https://www.mongodb.com/try/download/database-tools) on Windows.

### Strategy questions (know these)

- **RPO** (how much data may be lost) drives frequency / oplog continuity; **RTO** (how fast must we be back) drives restore method and rehearsal.
- **A backup you never restored is not a backup** — schedule restore drills, verify counts / checksums, document the runbook.
- **Consistency**: `mongodump` without `--oplog` is not point-in-time on a busy replica set (collections dumped at different moments). Use `--oplog` + `--oplogReplay`, snapshots, or Atlas.
- **What to back up besides data**: users/roles (`admin` db), indexes (in `.metadata.json`), config files, keyFiles/TLS certs, and for sharded clusters the config server database.
- **Sharded clusters**: `mongodump` is not supported for consistent backups of a sharded cluster (balancer must be stopped, all shards + config at the same time) → use Atlas/Ops Manager or coordinated snapshots.
- **Retention & storage**: off-site copies, encryption of backup files, versioned buckets; test that the restore tool version supports the dump version (restore into same or newer server).
- **Dump size vs storage size**: dumps are uncompressed BSON (`--gzip` helps); restores rebuild indexes (CPU-heavy) — for big data prefer snapshots.

## 2. Syntax cheat-sheet

```powershell
# Dump / restore (inside the container)
docker exec mongo-practice mongodump --db companyDB --out /dump/full
docker exec mongo-practice mongodump --db companyDB --gzip --archive=/dump/companyDB.gz
docker exec mongo-practice mongodump --oplog --out /dump/pit                       # whole instance, point-in-time (replica set)
docker exec mongo-practice mongorestore --db companyDB --drop /dump/full/companyDB
docker exec mongo-practice mongorestore --nsFrom "companyDB.*" --nsTo "companyDB_copy.*" /dump/full
docker exec mongo-practice mongorestore --db companyDB --collection customers --drop /dump/full/companyDB/customers.bson
docker exec mongo-practice mongorestore --gzip --archive=/dump/companyDB.gz
docker exec mongo-practice mongorestore --oplogReplay /dump/pit
docker cp mongo-practice:/dump/full ./backups/full                                  # container -> host
docker cp ./data/customers_extra.csv mongo-practice:/dump/                          # host -> container

# Export / import
docker exec mongo-practice mongoexport --db companyDB --collection orders --jsonArray --pretty --out /dump/orders.json
docker exec mongo-practice mongoexport --db companyDB --collection customers --type csv --fields "_id,name,email,city" --out /dump/customers.csv
docker exec mongo-practice mongoimport --db companyDB --collection customers_csv --type csv --headerline --file /dump/customers_extra.csv
docker exec mongo-practice mongoimport --db companyDB --collection customers_csv --type csv --headerline --columnsHaveTypes --file /dump/customers_typed.csv
docker exec mongo-practice mongoimport --db companyDB --collection products --jsonArray --mode upsert --upsertFields _id --file /dump/products_extra.json

# With authentication
docker exec mongo-auth-practice mongodump --uri "mongodb://admin:Admin%23123@localhost:27017/?authSource=admin" --db companyDB --out /dump/x
```

## 3. Gotchas

- **`mongoexport`/`mongoimport` are not backup tools**: CSV loses types (numbers, dates, ObjectIds become strings), JSON relaxed mode may lose precision (Long/Decimal128), and neither exports indexes or collection options. Use `mongodump`.
- **`mongorestore` inserts; it does not overwrite existing documents** unless you `--drop` the collection first (duplicate `_id` = error/skip). Use `--drop` for a clean restore.
- **`--oplog` only works when dumping the entire instance** (no `--db`/`--collection`) on a replica set member; `--oplogReplay` needs the `oplog.bson` from that dump.
- **Restoring `admin` overwrites users/roles** — usually what you want on a rebuilt server, dangerous on a live one; `--nsExclude "admin.*"` to skip.
- **Index rebuild time**: restore recreates every index from `.metadata.json`; big collections take long → `--noIndexRestore` then build later, or restore on a secondary.
- **Version compatibility**: restore into the same or a newer server version; tools ≥ 100.x support servers 4.4–8.x; dumps from very old versions may need intermediate upgrades.
- **Docker volumes**: backing up `/data/db` by copying files while `mongod` runs gives an inconsistent copy — stop the container or use `db.fsyncLock()` (standalone) / snapshot a locked secondary.
- **PowerShell quoting**: JSON for `--query` is painful on Windows → put it in a file and use `--queryFile`.
- **`mongoimport` CSV `_id` column becomes a string** ("9"), which no longer matches numeric queries — use `--columnsHaveTypes` or import into a staging collection and convert.
- **Restores are not atomic**: a failed restore halfway leaves a partial collection; restore into a staging database, verify, then rename/swap.

## 4. Interview questions

**Q: How do you back up MongoDB?**
Small/medium: `mongodump` (BSON + indexes) with `--oplog` on a replica set, `--gzip`, scheduled, stored off-site, restored regularly in drills. Large: filesystem / cloud volume snapshots of a consistent `dbPath` (secondary or `fsyncLock`). Managed: Atlas continuous backups / Ops Manager with point-in-time restore.

**Q: `mongodump` vs `mongoexport`?**
`mongodump` writes BSON with full type fidelity plus index metadata — for backup/restore/migration. `mongoexport` writes JSON/CSV for humans and other systems — loses indexes and (CSV) types; not a backup.

**Q: How do you get a point-in-time consistent backup with `mongodump`?**
Run it against a replica set member with `--oplog` (captures the oplog while dumping the whole instance) and restore with `--oplogReplay`, which applies those entries so the data is consistent as of the end of the dump.

**Q: How do you restore a single collection / to a different database?**
`mongorestore --db X --collection Y --drop path/X/Y.bson`; rename with `--nsFrom "old.*" --nsTo "new.*"`; single collection from an archive with `--nsInclude`.

**Q: What is RPO/RTO and how do they influence the strategy?**
RPO = maximum acceptable data loss (backup frequency, oplog-based continuous backup for near-zero). RTO = maximum acceptable downtime (snapshot restores are fast, dump restores with index rebuilds are slow; rehearsed runbooks).

**Q: How do you back up a sharded cluster?**
Not with plain `mongodump` in production: you need the balancer stopped and consistent snapshots of every shard *and* the config servers at the same point; use Atlas/Ops Manager or coordinated volume snapshots.

**Q: How do you migrate data from SQL Server / CSV into MongoDB?**
Export CSV/JSON, reshape (embed related rows) with a script or `mongoimport` into staging collections followed by aggregation (`$lookup`/`$group` → `$out`), typed imports (`--columnsHaveTypes`), then validate counts, build indexes, and switch the application.

## 5. Checklist

- [ ] I can dump and restore a database, a collection, to a different name, gzipped / archived
- [ ] I can export to JSON and CSV and import CSV / JSON with the right types and modes
- [ ] I can do an oplog-based point-in-time dump and replay it
- [ ] I can explain snapshots vs dumps vs Atlas backups, RPO/RTO and restore drills
- [ ] I know what dumps do not contain and the common restore mistakes
