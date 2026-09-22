# Level 18 — Sharding

**Goal:** understand how MongoDB scales writes and data volume horizontally with a **sharded cluster** (shards, config servers, `mongos`), choose a good **shard key** (the decision that matters most), read `sh.status()`, tell targeted from scatter-gather queries, and know chunks, balancing, zones, resharding and the operational rules.

**Time:** ~3 hr · **Files:** `docker-compose.sharded.yml` (2 shards + config server + mongos) → `01_Practice_Sharding.js` (run against `mongos`) → `Exercises.js`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Sharding** | Splitting one collection's documents across several **shards** (each a replica set) by the value of the **shard key**. Reads/writes for a key go to one shard → capacity and throughput scale out. Replica sets give HA; sharding gives scale. |
| **Shard** | A replica set holding a subset of the data. Production: ≥ 3 members each. |
| **Config servers** | A replica set (CSRS) storing the cluster metadata: shards, databases, collections, **chunks** and their ranges → which shard owns which key range. |
| **`mongos`** | The stateless query router the application connects to. Caches metadata, routes each operation to the right shard(s), merges results (`SHARD_MERGE`), runs `$group`/`$sort` merges. Run several (usually one per app server). |
| **Shard key** | One or more indexed fields of every document. **Ranged** key: contiguous ranges of values form chunks (good for range queries, bad for monotonic values like timestamps/ObjectId → all writes hit the last chunk = "hot shard"). **Hashed** key: `{ field: "hashed" }` spreads even monotonic values evenly (writes scale, but range queries broadcast). Compound keys `{ region: 1, customerId: 1 }` combine locality and cardinality. |
| **Good shard key** | High **cardinality** (many distinct values), low **frequency** (no value dominates), non-**monotonic** (or hashed), and — most important — **present in most queries** so they can be **targeted**. |
| **Chunk** | A contiguous key range assigned to a shard (default max 128 MB). Split when it grows; **balancer** (runs on the config server primary) moves chunks/ranges to keep shards even by data size. **Jumbo** chunk: cannot be split (single key value too frequent). |
| **Targeted vs broadcast** | Query includes the shard key (equality, or range for ranged keys) → routed to one/few shards (`SINGLE_SHARD`). Otherwise → **scatter-gather** to all shards (`SHARD_MERGE`) — works, but does not scale. Updates/deletes of one document (`updateOne`) must include the shard key or `_id`. |
| **Primary shard** | Each database has one: unsharded collections of that database live there (`movePrimary` to change). |
| **Zones (tag-aware sharding)** | Assign key ranges to shard groups (`region: "eu"` → EU shards): data locality, tiering, compliance. |
| **Resharding** (5.0+) | `reshardCollection` changes the shard key online (copies data in the background); 7.x+ `unshardCollection`, `moveCollection`. Before 5.0 the key was permanent. |
| **Unique constraints** | A unique index on a sharded collection must be **prefixed by the shard key** (uniqueness can only be enforced per shard). `_id` is unique per shard only unless it is the shard key. |
| **Transactions** | Cross-shard transactions (4.2+) use a two-phase commit; keep related data on one shard via the key to avoid them. |
| **When to shard** | Working set > RAM of one machine, write throughput beyond one primary, data volume beyond one server's disk, geographic locality. Before that: better indexes, bigger machine, archiving. Sharding adds operational complexity and cannot be undone cheaply (before 7.x). |

### SQL Server ↔ MongoDB

| SQL Server | MongoDB |
|-----------|---------|
| Table partitioning (single server) | chunks (but spread across servers) |
| Federated / distributed partitioned views | sharded collection + `mongos` routing |
| Partition key | shard key |
| Linked servers / Azure SQL elastic pools | *(no equivalent; sharding is native)* |
| Availability group per shard | each shard is a replica set |

## 2. Syntax cheat-sheet

```js
// on mongos
sh.status()                                       // shards, databases, collections, chunk distribution, balancer
sh.enableSharding("shopDB")
sh.shardCollection("shopDB.orders", { customerId: "hashed" })            // hashed key
sh.shardCollection("shopDB.events", { region: 1, ts: 1 })                // ranged compound key
db.orders.getShardDistribution()                  // docs / size per shard
db.orders.find({ customerId: 42 }).explain().queryPlanner.winningPlan.stage    // SINGLE_SHARD vs SHARD_MERGE
db.getSiblingDB("config").chunks.find({ uuid: <coll uuid> })   // or config.chunks by ns on old versions
db.getSiblingDB("config").shards.find()           db.getSiblingDB("config").databases.find()
sh.getBalancerState()   sh.isBalancerRunning()   sh.stopBalancer()   sh.startBalancer()
sh.splitAt("shopDB.events", { region: "eu", ts: MinKey })       sh.splitFind("shopDB.events", { region: "us", ts: ISODate("2025-01-01") })
sh.moveChunk("shopDB.events", { region: "eu", ts: MinKey }, "shard2rs")   // moveRange in 6.0+
sh.addShardToZone("shard1rs", "EU")   sh.updateZoneKeyRange("shopDB.events", { region: "eu", ts: MinKey }, { region: "eu", ts: MaxKey }, "EU")
db.adminCommand({ reshardCollection: "shopDB.orders", key: { region: 1, customerId: 1 } })
db.adminCommand({ balancerCollectionStatus: "shopDB.orders" })
db.adminCommand({ listShards: 1 })   db.adminCommand({ movePrimary: "shopDB", to: "shard2rs" })
```

```
mongodb://mongos1:27017,mongos2:27017/shopDB                 # apps connect to mongos, never to a shard directly
```

## 3. Gotchas

- **The shard key decides everything**: queries without it broadcast; a monotonic ranged key hot-spots one shard; a low-cardinality key (country with 3 values) cannot be split → jumbo chunks. Design it with the query patterns in hand.
- **Hashed keys kill range queries** on that field (they broadcast) and cannot be used for zones by value.
- **`_id` is not globally unique** on a sharded collection unless it is (part of) the shard key; unique indexes must start with the shard key.
- **Single-document `updateOne` / `replaceOne` / `deleteOne` must be targetable** (include the shard key or `_id`… with `_id` alone the router broadcasts and errors for `updateOne` without shard key in older versions). Multi-updates broadcast fine.
- **Shard key values are (almost) immutable**: changing them (5.0+ allowed) is a delete + insert across shards inside a transaction — slow.
- **Balancing costs I/O**: schedule the balancer window off-peak; pre-split empty collections before bulk loads (hashed keys pre-split automatically).
- **`$lookup`/`$graphLookup` on sharded "from" collections** are supported (5.1+) but expensive; `$out` to sharded target is not allowed (use `$merge`).
- **Aggregations merge on a shard or on mongos**: `$group`/`$sort` happen per shard and merge on the "merging shard" or router — memory on mongos is limited (`allowDiskUse` applies on shards).
- **Config servers down = cluster frozen for metadata changes** (reads/writes keep working with cached routing). Back them up.
- **Backups of a sharded cluster** need coordination (Level 16).
- **Sharding too early** is the classic mistake; sharding too late (when the single primary is at 100 %) is the painful one — balancing an already huge collection takes days.

## 4. Interview questions

**Q: What is sharding and when do you need it?**
Horizontal partitioning of collections across replica sets by a shard key, routed by `mongos`, with metadata on config servers. Needed when data volume, working set or write throughput exceed a single replica set (or for geographic locality); replica sets alone give HA and read scaling, not write scaling.

**Q: What makes a good shard key?**
High cardinality, even frequency, non-monotonic (or hashed), and used by most queries so they are targeted; ideally it also keeps related documents (one customer's orders) on the same shard for locality and transactions. Compound keys often satisfy all of this.

**Q: Hashed vs ranged sharding?**
Hashed: even write distribution for monotonic keys (timestamps, ObjectId), equality queries targeted, range queries broadcast. Ranged: range queries targeted, zones possible, but monotonic keys hot-spot one shard and skewed values create jumbo chunks.

**Q: What are chunks and the balancer?**
Chunks are key ranges (≤ 128 MB) assigned to shards. The balancer, running on the config server primary, migrates ranges so data (size) is even across shards; it can be windowed or stopped.

**Q: What is a targeted query vs scatter-gather?**
Targeted: `mongos` uses the shard key in the filter to send the query to one (or few) shards. Scatter-gather: no shard key → sent to all shards, results merged on `mongos` — latency = slowest shard, no scaling benefit.

**Q: Can you change the shard key?**
Since 5.0: `reshardCollection` rebuilds the collection online with a new key (needs free space and time); `refineCollectionShardKey` (4.4) can add suffix fields. Before that: dump/restore into a new collection.

**Q: What are the components of a sharded cluster?**
Shards (replica sets with the data), config server replica set (metadata), `mongos` routers (stateless, app-facing). Minimum production: 2 shards × 3 members + 3 config servers + 2 mongos.

**Q: What happens to `_id` and unique indexes?**
Uniqueness is enforced per shard: `_id` can repeat across shards unless it is the shard key; any unique index must be prefixed with the shard key; otherwise use an application-level check or make the key unique.

**Q: How do zones help?**
They pin key ranges to sets of shards: data residency (EU data on EU shards), hot/cold tiers (recent data on SSD shards), or per-tenant isolation.

**Q: How do transactions work across shards?**
Supported since 4.2 with a two-phase commit coordinated by a shard; slower than single-shard transactions, so choose keys that keep transactional documents together.

## 5. Checklist

- [ ] I can name the components and explain the shard key, chunks, balancer, targeted vs scatter-gather
- [ ] I can enable sharding, shard a collection (hashed and ranged), and read `sh.status()` / `getShardDistribution()`
- [ ] I can prove with `explain` which queries are targeted and which broadcast
- [ ] I can split and move chunks, configure zones, and check / stop the balancer
- [ ] I can explain unique-index, `_id`, transaction and resharding rules and when *not* to shard
