/* ============================================================
   LEVEL 18 - SHARDING  |  01_Practice_Sharding.js
   ------------------------------------------------------------
   Topics : the cluster (sh.status, config db), enableSharding,
            hashed vs ranged shard keys, getShardDistribution,
            targeted vs scatter-gather (explain on mongos),
            chunks, split / move, balancer, zones, unique index
            rule, _id per shard, primary shard, resharding

   HOW TO RUN
     docker compose -f docker-compose.sharded.yml up -d   (wait ~40 s)
     mongosh --port 27030          <- mongos!  then run block by block
   or:  Get-Content 01_Practice_Sharding.js -Raw | mongosh --quiet --port 27030
   ============================================================ */

use("shopDB");


/* ============================================================
   1. THE CLUSTER
   ============================================================ */

db.hello().msg;                                            // "isdbgrid" = you are talking to a mongos router
db.adminCommand({ listShards: 1 }).shards.map(s => s._id + " -> " + s.host);   // shard1rs, shard2rs
const cfg = db.getSiblingDB("config");
cfg.shards.find({}, { _id: 1, host: 1, state: 1 });
cfg.settings.find();                                       // e.g. chunksize (default 128 MB), balancer settings
sh.getBalancerState();                                     // true
db.getSiblingDB("shopDB").dropDatabase();                  // clean start


/* ============================================================
   2. ENABLE SHARDING, HASHED SHARD KEY
   ============================================================ */

sh.enableSharding("shopDB");                               // the database gets a PRIMARY shard (for unsharded collections)
cfg.databases.findOne({ _id: "shopDB" }).primary;          // shard1rs or shard2rs

// orders by customerId, HASHED: even spread even for a monotonic key, equality queries targeted, ranges broadcast
sh.shardCollection("shopDB.orders_hashed", { customerId: "hashed" });
db.orders_hashed.getIndexes().map(i => i.key);             // the shard key index { customerId: 'hashed' } was created automatically
// Hashed sharding on an EMPTY collection pre-creates chunks on every shard (here 1 per shard), so data spreads from the first insert
cfg.collections.findOne({ _id: "shopDB.orders_hashed" }).key;

// Load 100 000 orders through mongos (~10 s)
const statuses = ["Completed", "Completed", "Completed", "Pending", "Cancelled"];
for (let b = 0; b < 5; b++) {
    db.orders_hashed.insertMany(Array.from({ length: 20000 }, (_, i) => {
        const k = b * 20000 + i;
        return { orderNo: k + 1, customerId: k % 5000, region: k % 3 === 0 ? "eu" : k % 3 === 1 ? "us" : "in",
                 status: statuses[k % 5], orderDate: new Date(Date.UTC(2025, 0, 1) + k * 60000), totalAmount: 100 + (k % 900) };
    }), { ordered: false });
}
db.orders_hashed.countDocuments();                         // 100000 - counted across both shards by mongos
db.orders_hashed.getShardDistribution();                   // ~50 % / ~50 % of docs on each shard, chunks per shard


/* ============================================================
   3. TARGETED vs SCATTER-GATHER  (explain on mongos)
   ============================================================ */

function route(explainOut) {
    const wp = explainOut.queryPlanner.winningPlan;
    return { stage: wp.stage, shards: wp.shards ? wp.shards.map(s => s.shardName) : (wp.inputStage && wp.inputStage.shards ? wp.inputStage.shards.map(s => s.shardName) : "?") };
}
route(db.orders_hashed.find({ customerId: 42 }).explain());                          // SINGLE_SHARD  - the key hashes to exactly one shard
route(db.orders_hashed.find({ customerId: { $in: [42, 43, 44] } }).explain());       // SINGLE_SHARD or SHARD_MERGE with only the shards that own those hashes
route(db.orders_hashed.find({ status: "Pending" }).explain());                       // SHARD_MERGE   - no shard key -> every shard is asked (scatter-gather)
route(db.orders_hashed.find({ customerId: { $gte: 40, $lte: 45 } }).explain());      // SHARD_MERGE   - a RANGE on a hashed key cannot be targeted

// The full picture: per-shard plans are inside winningPlan.shards[]
db.orders_hashed.find({ customerId: 42 }).explain("executionStats").executionStats.executionStages.shards.map(s => ({ shard: s.shardName, nReturned: s.executionStages.nReturned }));

// Single-document writes must be targetable
db.orders_hashed.updateOne({ customerId: 42, orderNo: 43 }, { $set: { note: "targeted" } }).matchedCount;   // 1 (shard key included)
try {
    const r = db.orders_hashed.updateOne({ orderNo: 44 }, { $set: { note: "?" } });                            // no shard key, no _id
    print("updateOne without shard key: matched", r.matchedCount, "- 8.x broadcasts it (two-phase, slower); older versions refuse");
} catch (e) {
    print("EXPECTED ERROR:", e.codeName || "", e.message.substring(0, 80));
}
db.orders_hashed.updateMany({ status: "Cancelled" }, { $set: { archived: true } }).matchedCount;               // multi-updates may broadcast: 20000


/* ============================================================
   4. RANGED SHARD KEY, CHUNKS, SPLIT, MOVE
   ============================================================ */

sh.shardCollection("shopDB.events", { region: 1, ts: 1 });   // compound ranged key: locality by region, then time
cfg.chunks.find({ uuid: cfg.collections.findOne({ _id: "shopDB.events" }).uuid }, { _id: 0, min: 1, max: 1, shard: 1 });   // ONE chunk: MinKey..MaxKey on the primary shard

// Pre-split so each region gets its own chunk (do this BEFORE a bulk load in real life)
sh.splitAt("shopDB.events", { region: "in", ts: MinKey });
sh.splitAt("shopDB.events", { region: "us", ts: MinKey });
cfg.chunks.find({ uuid: cfg.collections.findOne({ _id: "shopDB.events" }).uuid }, { _id: 0, min: 1, max: 1, shard: 1 });   // 3 chunks, still all on one shard

// Move the "us" chunk to the other shard by hand
const primaryOfShop = cfg.databases.findOne({ _id: "shopDB" }).primary;
const otherShard = primaryOfShop === "shard1rs" ? "shard2rs" : "shard1rs";
sh.moveChunk("shopDB.events", { region: "us", ts: MinKey }, otherShard);
cfg.chunks.find({ uuid: cfg.collections.findOne({ _id: "shopDB.events" }).uuid }, { _id: 0, "min.region": 1, shard: 1 });

db.events.insertMany(Array.from({ length: 3000 }, (_, i) => ({ region: ["eu", "us", "in"][i % 3], ts: new Date(Date.UTC(2025, 0, 1) + i * 1000), v: i })));
db.events.getShardDistribution();                          // "us" documents on the other shard, "eu" + "in" on the primary shard
route(db.events.find({ region: "us", ts: { $gte: ISODate("2025-01-01") } }).explain());   // SINGLE_SHARD - ranged key + range query = targeted
route(db.events.find({ ts: { $gte: ISODate("2025-01-01") } }).explain());                 // SHARD_MERGE  - prefix (region) missing


/* ============================================================
   5. THE BALANCER
   ============================================================ */

sh.isBalancerRunning();                                    // false most of the time (it wakes up when shards are uneven)
db.adminCommand({ balancerCollectionStatus: "shopDB.orders_hashed" });   // { balancerCompliant: true } - data is even
sh.stopBalancer();  sh.getBalancerState();                 // false - e.g. during a bulk load or a backup
sh.startBalancer(); sh.getBalancerState();                 // true
// A balancing WINDOW (off-peak hours):
// cfg.settings.updateOne({ _id: "balancer" }, { $set: { activeWindow: { start: "01:00", stop: "05:00" } } }, { upsert: true })
// Balancing is by data size per shard (6.0.3+), ranges are moved with moveRange; chunk size: cfg.settings.findOne({ _id: "chunksize" })


/* ============================================================
   6. ZONES  (pin key ranges to shards: data residency / tiers)
   ============================================================ */

sh.addShardToZone(primaryOfShop, "ASIA_EU");
sh.addShardToZone(otherShard, "AMERICAS");
sh.updateZoneKeyRange("shopDB.events", { region: "us", ts: MinKey }, { region: "us", ts: MaxKey }, "AMERICAS");
sh.updateZoneKeyRange("shopDB.events", { region: "eu", ts: MinKey }, { region: "eu", ts: MaxKey }, "ASIA_EU");
sh.updateZoneKeyRange("shopDB.events", { region: "in", ts: MinKey }, { region: "in", ts: MaxKey }, "ASIA_EU");
cfg.tags.find({}, { _id: 0, tag: 1, "min.region": 1 });    // the balancer will now keep "us" on AMERICAS and eu/in on ASIA_EU
cfg.shards.find({}, { _id: 1, tags: 1 });


/* ============================================================
   7. RULES: unique indexes, _id, unsharded collections, primary shard
   ============================================================ */

// A unique index must be PREFIXED by the shard key
try {
    db.orders_hashed.createIndex({ orderNo: 1 }, { unique: true });
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 90));   // cannot create unique index over { orderNo: 1 } with shard key pattern { customerId: "hashed" }
}
// _id is unique PER SHARD only: the same _id can exist on both shards. A second "dup" whose customerId hashes to the
// SAME shard is rejected (E11000 there); one that hashes to the OTHER shard is accepted.
db.orders_hashed.insertOne({ _id: "dup", customerId: 1, orderNo: -1 });
let placedWith = null;
for (const cid of [2, 3, 4, 5, 6, 7, 8, 9]) {
    try { db.orders_hashed.insertOne({ _id: "dup", customerId: cid, orderNo: -cid }); placedWith = cid; break; }
    catch (e) { print("customerId", cid, "-> same shard as customer 1: EXPECTED ERROR E11000"); }
}
print("second _id 'dup' accepted with customerId", placedWith, "(different shard)");
db.orders_hashed.countDocuments({ _id: "dup" });           // 2 (!)
db.orders_hashed.deleteMany({ _id: "dup" });

// Unsharded collections of shopDB live on the primary shard
db.settings.insertOne({ _id: "theme", value: "dark" });
cfg.collections.findOne({ _id: "shopDB.settings" });       // null - not sharded (8.x may track unsharded collections; then check "unsplittable: true")
db.settings.find().explain().queryPlanner.winningPlan.shards ? db.settings.find().explain().queryPlanner.winningPlan.shards.map(s => s.shardName) : primaryOfShop;   // the primary shard

sh.status();                                               // the whole picture: shards, most recently active mongoses, balancer, databases + chunk distribution


/* ============================================================
   8. RESHARDING  (5.0+): change the shard key online
   ============================================================ */

// Not run here (it copies the whole collection in the background and needs free space) - the command is:
//   db.adminCommand({ reshardCollection: "shopDB.orders_hashed", key: { region: 1, customerId: 1 } })
//   db.getSiblingDB("admin").aggregate([ { $currentOp: { allUsers: true, localOps: false } }, { $match: { type: "op", "originatingCommand.reshardCollection": { $exists: true } } } ])   // progress
// 4.4: refineCollectionShardKey adds suffix fields; 7.x: unshardCollection / moveCollection.


/* ============================================================
   CLEANUP
   ============================================================ */
db.getSiblingDB("shopDB").dropDatabase();
sh.removeShardFromZone(primaryOfShop, "ASIA_EU"); sh.removeShardFromZone(otherShard, "AMERICAS");

/* ------------------------------------------------------------
   DONE. Next: Exercises.js  (then: docker compose -f docker-compose.sharded.yml down -v)
   ------------------------------------------------------------ */
