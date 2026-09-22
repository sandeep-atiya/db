# Level 20 — Docker & Production

**Goal:** run MongoDB in Docker with confidence (images, volumes, environment variables, init scripts, compose, health checks, resource limits), monitor a running server (`serverStatus`, `mongostat`, `mongotop`, logs, FCV), and know the production checklist an interviewer expects: architecture, security, performance, operations, capacity planning, upgrades, Atlas vs self-managed.

**Time:** ~2.5 hr · **Files:** `01_Practice_Docker.ps1` (+ `init/01_seed.js`) → `02_Practice_Monitoring.js` → `Exercises.ps1`

---

## 1. Concepts in plain words

### Docker essentials for MongoDB

| Command / option | Meaning |
|------------------|---------|
| `docker pull mongo:8` | official image (`mongo:8`, `mongo:8.0`, `mongo:7.0-jammy`, `mongodb/mongodb-community-server`) |
| `docker run -d --name x -p 27017:27017 -v vol:/data/db mongo:8` | detached, name, port mapping host:container, **named volume** for `/data/db` (data survives container removal) |
| `-e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD=…` | creates the root user **and enables `--auth`** (only on first start with an empty volume) |
| `-e MONGO_INITDB_DATABASE=appdb` + `-v ./init:/docker-entrypoint-initdb.d` | `*.js` / `*.sh` files in that folder run **once** on an empty volume, against `MONGO_INITDB_DATABASE` (seed data, app users) |
| `command: ["mongod", "--replSet", "rs0", "--wiredTigerCacheSizeGB", "1"]` | extra `mongod` flags (or mount a `mongod.conf` and `--config`) |
| `docker exec -it x mongosh` / `docker exec x mongodump …` | run tools inside; `docker cp` to move files |
| `docker logs -f x`, `docker stats`, `docker inspect x` | logs (mongod logs JSON lines to stdout), CPU/RAM, config/health |
| `docker stop / start / restart / rm x`, `docker volume ls / inspect / rm` | lifecycle; removing the volume deletes the data |
| `docker compose up -d / ps / logs -f / stop / down [-v]` | multi-container setups (Level 00, 15, 17, 18) |
| `healthcheck`, `deploy.resources.limits` / `--memory 2g --cpus 2` | readiness for dependants; **set the WiredTiger cache below the container memory limit** (`--wiredTigerCacheSizeGB`) or the OOM killer strikes |
| `network` | containers on one compose network reach each other by service name; replica-set host names must be resolvable by *clients* too (Level 17 uses `host.docker.internal`) |

Docker is great for dev, CI, labs; in production use Kubernetes (MongoDB Community/Enterprise Operator), VMs with configuration management, or **Atlas**.

### Monitoring: what to look at

| Source | Key metrics |
|--------|-------------|
| `db.serverStatus()` | `uptime`, `connections` (current/available), `opcounters`, `mem.resident`, `wiredTiger.cache` (bytes in cache vs max, dirty), `globalLock.currentQueue`, `metrics.document`, `network`, `asserts`, `repl` |
| `db.stats()`, `db.coll.stats()` | data / storage / index sizes, document count, avg object size |
| `mongostat` | per-second insert/query/update/delete, dirty/used cache %, queued readers/writers (qrw), connections |
| `mongotop` | time spent reading/writing per collection |
| profiler / slow query log (Level 12) | slow operations, `planSummary` |
| `rs.status()`, `rs.printSecondaryReplicationInfo()` | member health, lag (Level 17) |
| `sh.status()`, balancer | chunk distribution (Level 18) |
| `db.currentOp()` / `$currentOp` | long-running / blocked operations |
| `db.adminCommand({ getLog: "global" })` | recent log lines; production: file logs with rotation, `slowms` |
| External | Atlas metrics & alerts, Ops/Cloud Manager, Prometheus `mongodb_exporter` + Grafana, Datadog…; alert on: replication lag, connections near limit, queued operations, cache eviction / page faults, disk % and IOPS, election events, slow queries |

### Production checklist (say this in the interview)

- **Architecture**: 3-member replica set (odd voters) across availability zones; shard only when needed with a well-chosen key; `mongos` next to the app; separate config servers.
- **Security** (Level 15): auth on, least-privilege users, keyFile/x.509 between members, TLS, bind to private network + firewall, encryption at rest, auditing, secrets management, no `$where`.
- **Schema & indexes** (Levels 11–13): model for the queries, ESR indexes, no unbounded arrays, validation where it matters, periodic index review (`$indexStats`).
- **Performance**: working set fits in RAM (WiredTiger cache ≈ 50 % RAM − 1 GB), SSD/NVMe with enough IOPS, connection pooling, `maxTimeMS`, read/write concern chosen consciously, avoid scatter-gather.
- **Durability & recovery** (Level 16): `w: "majority"`, journaling (always on), automated backups + **restore drills**, oplog sized for maintenance windows, documented RPO/RTO.
- **Operations**: monitoring + alerting, capacity planning (data and index growth, connections, CPU, disk), rolling upgrades (`featureCompatibilityVersion` two-step), rolling index builds, log rotation, runbooks (failover, disk full, hot shard, slow query).
- **OS tuning** (self-managed Linux): XFS, disable transparent huge pages, `ulimit -n 64000+`, NUMA interleave, NTP, no swap pressure, separate disks for data/journal/logs, `noatime`.
- **Atlas vs self-managed**: Atlas gives automated HA, backups with PIT, scaling, monitoring, security defaults, Search/Vector/Data Federation; self-managed gives control and can be cheaper at scale but needs the checklist above done by you.

## 2. Syntax cheat-sheet

```powershell
docker pull mongo:8
docker run -d --name mongo-prod-like -p 27019:27017 `
  -e MONGO_INITDB_ROOT_USERNAME=admin -e MONGO_INITDB_ROOT_PASSWORD=S3cret `
  -e MONGO_INITDB_DATABASE=appdb -v mongo-prod-data:/data/db -v ${PWD}\init:/docker-entrypoint-initdb.d:ro `
  --memory 1g --cpus 1 mongo:8 mongod --wiredTigerCacheSizeGB 0.25 --auth
docker logs --tail 20 mongo-prod-like
docker exec mongo-prod-like mongosh -u admin -p S3cret --authenticationDatabase admin --quiet --eval "db.adminCommand('listDatabases')"
docker stats --no-stream mongo-prod-like
docker inspect --format "{{.State.Health.Status}} {{.HostConfig.Memory}}" mongo-prod-like
docker stop mongo-prod-like; docker start mongo-prod-like
docker rm -f mongo-prod-like; docker volume rm mongo-prod-data
```

```js
db.serverStatus().connections                 db.serverStatus().wiredTiger.cache["bytes currently in the cache"]
db.serverStatus().opcounters                  db.serverStatus().globalLock.currentQueue
db.serverStatus().mem                         db.serverStatus().metrics.document
db.stats({ scale: 1024 * 1024 })              db.orders.stats({ scale: 1024 }).wiredTiger["block-manager"]["file size in bytes"]
db.adminCommand({ getLog: "global" }).log.slice(-5)
db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 })
db.adminCommand({ setFeatureCompatibilityVersion: "8.0", confirm: true })
db.adminCommand({ getParameter: 1, wiredTigerEngineRuntimeConfig: 1 })
db.hostInfo().system                          db.serverBuildInfo().version
db.adminCommand({ connPoolStats: 1 })         db.adminCommand({ hostInfo: 1 })
db.adminCommand({ setParameter: 1, slowOpThresholdMs: 200 })
db.adminCommand({ logRotate: 1 })
```

## 3. Gotchas

- **`MONGO_INITDB_*` and init scripts run only on an empty data volume** — changing the password later needs `db.changeUserPassword`, not a new env var.
- **Container memory limit vs WiredTiger cache**: the cache defaults to 50 % of the *host's* RAM as seen inside the container (cgroup-aware in recent versions, but set `--wiredTigerCacheSizeGB` explicitly anyway).
- **Ephemeral containers lose data without a volume**; bind mounts on Windows are slow and have permission quirks — use named volumes.
- **Replica sets in Docker**: host names in `rs.conf()` must be reachable by clients; `localhost` inside a container ≠ your laptop.
- **Do not run `mongod` as root in production, do not expose 27017 publicly**, do not use `latest` tags in production, pin versions.
- **Logs are JSON** (4.4+): filter with `jq` / `docker logs | Select-String`; slow queries appear as `"msg":"Slow query"`.
- **FCV two-step upgrades**: upgrade binaries one major version at a time, run with the old FCV until stable, then `setFeatureCompatibilityVersion`; downgrade is only possible before raising FCV.
- **`serverStatus` counters are since start**; compute rates (mongostat does) — absolute values mean little.
- **Connections ≈ 1 MB RAM each on the server**; thousands of app instances × pool size can exhaust memory — size pools, use `maxIdleTimeMS`, consider a connection proxy.
- **Disk full = crash / no writes**: alert at 70–80 %, and remember that `compact`/index builds need free space.

## 4. Interview questions

**Q: How do you run MongoDB in Docker for development, and what changes for production?**
Dev: official image, named volume for `/data/db`, root user via env vars, init scripts for seed data, compose for replica sets/labs. Production: pinned versions, replica set across hosts/AZs, resource limits with explicit cache size, no public ports, TLS/auth, backups, monitoring — usually via Kubernetes operator, VMs, or Atlas rather than plain Docker.

**Q: How do you monitor a MongoDB cluster? Which metrics matter most?**
`serverStatus`/`mongostat`/`mongotop`, profiler and slow logs, `rs.status` for lag, plus a metrics stack (Atlas, Ops Manager, Prometheus exporter). Watch: opcounters and latency, queued readers/writers, connections, cache usage/eviction and page faults, replication lag, disk space/IOPS, elections, slow query counts.

**Q: How much RAM does MongoDB need?**
Enough for the working set (frequently accessed documents + indexes) to fit in the WiredTiger cache (~50 % RAM − 1 GB) plus filesystem cache and OS. Check with cache hit ratios / "bytes read into cache" growth and index sizes.

**Q: How do you upgrade a replica set without downtime?**
Rolling: upgrade secondaries one by one, `rs.stepDown()` the primary, upgrade it; then raise `featureCompatibilityVersion`. One major version at a time; drivers and tools compatible first; backups before.

**Q: What is `featureCompatibilityVersion`?**
A flag that gates on-disk/feature changes after a binary upgrade so you can still downgrade; set it to the new version once you are confident, which enables the new features and blocks downgrade.

**Q: Your MongoDB server is running out of connections — what do you do?**
Find who: `serverStatus().connections`, `currentOp`, `appName`s; fix the client side (one client per process, `maxPoolSize`, `maxIdleTimeMS`), raise `net.maxIncomingConnections` only with RAM to spare, add a proxy/pooling layer, and scale readers to secondaries.

**Q: Atlas or self-hosted?**
Atlas: managed HA, backups, scaling, security defaults, monitoring, global clusters, Search; pay per usage, less control. Self-hosted: full control, no per-cluster fees, but you own security, backups, upgrades, monitoring and on-call. Most teams without dedicated DBAs choose Atlas.

**Q: What is your runbook when disk usage hits 90 %?**
Alert early; stop non-essential writes/jobs; drop obsolete indexes/collections, archive or TTL old data; check oplog size and `system.profile`; add disk (cloud volumes online), `compact` on secondaries in a rolling fashion; longer term: capacity planning and sharding.

## 5. Checklist

- [ ] I can run a MongoDB container with volume, env vars, init scripts, auth and resource limits, and read its logs
- [ ] I can inspect, stop, start, remove containers and volumes and explain what survives
- [ ] I can read `serverStatus`, `mongostat`, `mongotop`, `db.stats` and the recent log
- [ ] I can recite the production checklist by area and explain FCV and rolling upgrades
- [ ] I can compare Atlas and self-managed and reason about RAM / connections / disk capacity
