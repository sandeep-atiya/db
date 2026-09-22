# Level 17 — Replication & Change Streams

**Goal:** understand how a replica set gives high availability (oplog, elections, failover, rollback), control durability and freshness with write concern / read concern / read preference, operate a set with the `rs.*` commands, run a real 3-node set with a failover drill, and react to data changes in real time with change streams.

**Time:** ~3 hr · **Files:** `01_Practice_ReplicaSet_Commands.js` (1-node set) → `02_Practice_Change_Streams.js` → `docker-compose.replset.yml` + `03_Failover_Lab.js` (3-node lab) → `Exercises.js`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Replica set** | A group of `mongod`s holding the same data: one **primary** (accepts writes) and **secondaries** that copy the primary's **oplog**. Max 50 members, 7 voting. Gives HA (automatic failover), redundancy, read scaling (secondary reads), maintenance without downtime. |
| **Oplog** | `local.oplog.rs`: a capped collection of every write as an **idempotent** operation (`i`nsert / `u`pdate / `d`elete / `c`ommand). Secondaries tail it and apply it. Its size (default 5 % of disk, 1–50 GB) defines the **oplog window** — how long a member can be down and still catch up (else: initial sync). |
| **Election** | Members heartbeat every 2 s. If the primary is unreachable for `electionTimeoutMillis` (10 s), the eligible members vote; a **majority of voting members** is required. Highest **priority** (0–1000, 0 = never primary) and most recent oplog win. Terms number each election. |
| **Failover & rollback** | The application's driver retries (`retryWrites`, `retryReads`) during the ~10–12 s election. Writes acknowledged only by the old primary (w:1) that were not replicated before it fell may be **rolled back** when it rejoins (written to rollback files) — `w: "majority"` prevents that. |
| **Member types** | data-bearing voting member (normal), **priority 0** (never primary — DR region), **hidden** (invisible to clients — reporting/backups), **delayed** (`secondaryDelaySecs` — human-error recovery), **arbiter** (votes only, no data — avoid; a PSA set cannot acknowledge `majority` writes when the secondary is down). |
| **Write concern** | How many members must acknowledge a write: `w: 1` (primary), `w: "majority"` (default since 5.0 for most topologies), `w: <n>`, `w: "<tag>"`; `j: true` (journaled); `wtimeout`. Majority = durable through failover. |
| **Read concern** | What a read may see: `local` (latest on that node, may be rolled back), `available` (same on sharded), `majority` (committed to a majority — never rolled back), `linearizable` (primary, all prior majority writes, single document), `snapshot` (transactions / consistent point). |
| **Read preference** | Which member serves reads: `primary` (default), `primaryPreferred`, `secondary`, `secondaryPreferred`, `nearest`; with `maxStalenessSeconds` and **tag sets** (`{ region: "eu" }`). Secondary reads may be **stale**. |
| **Causal consistency** | A session guarantees read-your-writes / monotonic reads across members (uses cluster time + `afterClusterTime`). |
| **Replication lag** | Time between a write on the primary and its application on a secondary (`rs.printSecondaryReplicationInfo()`, `optimeDate` diff). Causes: slow disk/network, big transactions, index builds. **Flow control** throttles the primary to keep majority lag < `flowControlTargetLagSeconds` (10 s). |
| **Change streams** | `coll.watch()` / `db.watch()` / `client.watch()`: a cursor of change events built on the oplog (needs a replica set, `majority` read concern). Events: `insert update replace delete drop rename dropDatabase invalidate` (+ DDL events 6.0 with `showExpandedEvents`). Resumable with a **resume token** (`resumeAfter`, `startAfter`, `startAtOperationTime`). `fullDocument: "updateLookup"` returns the current document on updates; `fullDocumentBeforeChange` needs pre-images (`changeStreamPreAndPostImages`). Use for: cache invalidation, search index sync, notifications, event sourcing, cross-collection denormalisation (Level 13). |

### SQL Server ↔ MongoDB

| SQL Server | MongoDB |
|-----------|---------|
| Always On Availability Group (sync/async replicas, automatic failover with a listener) | replica set (primary + secondaries, automatic election, driver discovers the primary) |
| Transaction log shipped to replicas | oplog tailed by secondaries |
| Synchronous commit | `w: "majority"` |
| Readable secondary | `readPreference: secondary…` (stale reads possible) |
| Witness / quorum | voting members, arbiter (avoid) |
| Failover Cluster Instance (shared storage) | *(no equivalent — replica sets are shared-nothing)* |
| CDC / Change Tracking / Service Broker triggers | change streams |
| Log shipping with restore delay | delayed member |

## 2. Syntax cheat-sheet

```js
rs.status()                              // members: stateStr PRIMARY/SECONDARY, health, optimeDate, lastHeartbeat
rs.conf()                                // _id, version, members[{ host, priority, votes, hidden, arbiterOnly, secondaryDelaySecs }], settings
rs.initiate({ _id: "rs3", members: [ { _id: 0, host: "h1:27017" }, { _id: 1, host: "h2:27017" }, { _id: 2, host: "h3:27017" } ] })
rs.add("h4:27017")   rs.add({ host: "h5:27017", priority: 0, hidden: true })   rs.addArb("h6:27017")   rs.remove("h4:27017")
const c = rs.conf(); c.members[1].priority = 2; c.settings.electionTimeoutMillis = 10000; rs.reconfig(c)
rs.stepDown(60)                          // primary steps down, no re-election for 60 s
rs.freeze(120)                           // this member refuses to become primary for 120 s
rs.printReplicationInfo()                // oplog size, first/last entry, window
rs.printSecondaryReplicationInfo()       // lag per secondary
db.hello()                               // isWritablePrimary, primary, hosts, setName
db.getMongo().setReadPref("secondaryPreferred", [ { region: "eu" } ])
db.orders.find().readPref("secondary").readConcern("majority")
db.orders.insertOne(doc, { writeConcern: { w: "majority", j: true, wtimeout: 5000 } })
db.adminCommand({ setDefaultRWConcern: 1, defaultWriteConcern: { w: "majority" } })
db.getSiblingDB("local").oplog.rs.find().sort({ $natural: -1 }).limit(3)

// change streams
const cs = db.orders.watch([ { $match: { operationType: { $in: ["insert", "update"] } } } ], { fullDocument: "updateLookup" });
while (cs.hasNext()) printjson(cs.next());       // blocking loop (or cs.tryNext() non-blocking)
const token = cs.getResumeToken();  cs.close();
db.orders.watch([], { resumeAfter: token })
db.watch()  /  db.getMongo().watch()             // database / whole deployment
db.runCommand({ collMod: "orders", changeStreamPreAndPostImages: { enabled: true } })   // then fullDocumentBeforeChange: "whenAvailable"
```

```
mongodb://h1:27017,h2:27017,h3:27017/companyDB?replicaSet=rs3&w=majority&readPreference=secondaryPreferred&retryWrites=true
```

## 3. Gotchas

- **Even number of voting members = no gain** (3 and 4 both tolerate 1 failure). Use odd numbers; 3 data nodes is the standard minimum.
- **Arbiters (PSA)**: with the secondary down, `w: "majority"` writes hang and majority reads stall (cache pressure) — prefer PSS.
- **`w: 1` writes can be rolled back** after a failover. Use `majority` for anything you cannot lose; it costs one network round trip.
- **Secondary reads are eventually consistent** — never read-your-own-write from a secondary without a causal session.
- **`rs.reconfig` needs a majority and can trigger an election** (priority change). Change one thing at a time; `{ force: true }` only in disaster recovery.
- **A member down longer than the oplog window needs an initial sync** (full copy) — size the oplog for your maintenance windows.
- **Hostnames in `rs.conf()` must be resolvable by every member AND every client** — the #1 setup problem (localhost vs container names vs public DNS). The lab uses `host.docker.internal:<port>` so both sides resolve it.
- **Change streams need `majority` read concern support and stop with `invalidate` on drop/rename** — handle it and restart with `startAfter`. Resume tokens expire when the oplog rolls over — persist the token and keep the oplog large enough.
- **`fullDocument: "updateLookup"` is not the document at update time** — it is the current version when the event is read (may already differ). Pre/post images give exact versions (6.0+).
- **One change stream = one cursor = one connection** per watcher; scale consumers rather than opening thousands of streams.
- **Elections take ~10–12 s by default**: applications must handle `NotWritablePrimary` errors or rely on retryable writes/reads.

## 4. Interview questions

**Q: How does replication work in MongoDB?**
A replica set has one primary that receives writes and records them in the oplog; secondaries continuously copy and apply the oplog. Members heartbeat; if the primary fails, a majority elects a new one within seconds and drivers reconnect automatically.

**Q: What happens during a failover? Can data be lost?**
The primary becomes unreachable → after the election timeout the remaining voters elect the most up-to-date eligible member. Writes acknowledged with `w: 1` that had not replicated may be rolled back when the old primary returns; `w: "majority"` writes are never lost.

**Q: Why an odd number of members? What does an arbiter do?**
Elections need a majority of votes; with 3 members one may fail, with 4 still only one — the 4th adds cost without resilience. An arbiter votes but holds no data; it avoids the cost of a third data node but weakens majority writes/reads when a data node is down.

**Q: Explain write concern, read concern and read preference.**
Write concern = how many members acknowledge a write (durability). Read concern = which version of data a read may see (isolation/consistency: local, majority, linearizable, snapshot). Read preference = which member answers the read (primary vs secondaries, tags, staleness).

**Q: What is the oplog and why does its size matter?**
The capped `local.oplog.rs` collection with idempotent copies of all writes. Its size sets the oplog window: how long a secondary can lag or be offline and still catch up without a full initial sync; also how far back change streams can resume.

**Q: How do you reduce replication lag?**
Faster disks/network on secondaries, avoid huge transactions and unindexed updates, build indexes in a rolling fashion, keep secondaries equally sized, use flow control, monitor with `rs.printSecondaryReplicationInfo()`.

**Q: What are change streams and how do they differ from tailing the oplog?**
A supported, resumable API over the oplog delivering structured events (with optional full documents and pre-images) filtered by a pipeline, honouring majority commit. Tailing the oplog directly is unsupported, unfiltered and breaks across versions.

**Q: How do you make a change stream consumer reliable?**
Persist the last resume token after processing each event, restart with `startAfter`, handle `invalidate`, make processing idempotent, keep the oplog window larger than your maximum downtime, and monitor lag.

**Q: How do you perform maintenance on a replica set without downtime?**
Rolling: stop a secondary, upgrade/patch it, restart, wait for it to catch up; repeat for every secondary; `rs.stepDown()` the primary and do the same. Same pattern for rolling index builds and version upgrades.

## 5. Checklist

- [ ] I can read `rs.status()` / `rs.conf()` and explain primary, secondary, priority, votes, hidden, delayed, arbiter
- [ ] I can explain oplog, election, failover, rollback and the oplog window
- [ ] I can set write concern, read concern and read preference and say what each protects against
- [ ] I can run the 3-node lab, kill the primary, watch the election and confirm the write path recovers
- [ ] I can open a change stream with a pipeline and `fullDocument`, resume it with a token, and handle `invalidate`
