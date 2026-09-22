/* ============================================================
   LEVEL 12  |  02_Practice_Profiler_PlanCache_Aggregation.js
   ------------------------------------------------------------
   Topics : plan cache (query shapes, $planCacheStats, clear),
            database profiler (system.profile), currentOp / killOp,
            maxTimeMS, aggregation explain and optimiser rewrites,
            $lookup with / without an index, cache & working set,
            the "slow query" checklist

   HOW TO PRACTICE: block by block, predict first.
   Uses bench_orders (built if missing). Profiling is switched
   off again at the end.
   ============================================================ */

use("companyDB");

function ensureBench(n = 200000) {
    if (db.bench_orders.estimatedDocumentCount() >= n) return;
    db.bench_orders.drop();
    const cities = ["Delhi", "Mumbai", "Pune", "Bangalore", "Chennai", "Noida", "Kolkata", "Hyderabad"];
    const tagPool = ["gift", "bulk", "priority", "fragile", "return", "b2b"];
    const start = ISODate("2024-01-01").getTime(), span = 730 * 86400000;
    for (let b = 0; b < n / 20000; b++) {
        db.bench_orders.insertMany(Array.from({ length: 20000 }, (_, i) => {
            const k = b * 20000 + i, r = Math.random();
            return { orderNo: k + 1, customerId: Math.floor(Math.random() * 2000) + 1, employeeId: 101 + (k % 12),
                     status: r < 0.90 ? "Completed" : r < 0.97 ? "Pending" : "Cancelled",
                     orderDate: new Date(start + Math.floor(Math.random() * span)), totalAmount: Math.floor(Math.random() * 199500) + 500,
                     city: cities[k % cities.length], tags: tagPool.filter(() => Math.random() < 0.25),
                     items: Array.from({ length: 1 + (k % 3) }, (_, j) => ({ productId: 1 + ((k + j) % 11), qty: 1 + (j % 4) })) };
        }), { ordered: false });
    }
}
function plan(explainOut) {
    const es = explainOut.executionStats;
    let s = explainOut.queryPlanner.winningPlan;
    if (s.queryPlan) s = s.queryPlan;
    const stages = [];
    while (s) { stages.push(s.stage + (s.indexName ? "(" + s.indexName + ")" : "")); s = s.inputStage || (s.inputStages && s.inputStages[0]); }
    return { plan: stages.reverse().join(" -> "), nReturned: es.nReturned, keysExamined: es.totalKeysExamined, docsExamined: es.totalDocsExamined, ms: es.executionTimeMillis };
}
ensureBench();
db.bench_orders.dropIndexes();


/* ============================================================
   1. THE PLAN CACHE  (per query SHAPE, not per value)
   ============================================================ */

db.bench_orders.createIndex({ customerId: 1 });
db.bench_orders.createIndex({ status: 1 });
db.bench_orders.getPlanCache().clear();

// Two candidate indexes -> the planner races them and CACHES the winner for this shape
db.bench_orders.find({ customerId: 42, status: "Completed" }).toArray().length;
db.bench_orders.find({ customerId: 43, status: "Pending" }).toArray().length;      // same SHAPE (fields + operators), different values -> cached plan reused

db.bench_orders.getPlanCache().list().map(p => ({ shape: p.createdFromQuery ? p.createdFromQuery.query : p.planCacheKey, works: p.works, isActive: p.isActive }));
db.bench_orders.aggregate([ { $planCacheStats: {} }, { $project: { _id: 0, planCacheKey: 1, isActive: 1, works: 1, indexName: { $ifNull: ["$cachedPlan.queryPlan.inputStage.indexName", "$cachedPlan.inputStage.indexName"] } } } ]);

// explain tells you whether the plan came from the cache (8.x: isCached in winningPlan)
db.bench_orders.find({ customerId: 44, status: "Cancelled" }).explain().queryPlanner.winningPlan.isCached;   // true

// The "parameter sniffing" of MongoDB: a plan cached for a selective value used for a non-selective one.
// Here the customerId plan is right for every value. The replanning mechanism re-evaluates a cached plan
// when it does far more work than at caching time (works * 10) - so most cases self-heal.

// Clear the cache (all shapes of the collection) - e.g. after loading very different data
db.bench_orders.getPlanCache().clear();
db.bench_orders.getPlanCache().list().length;             // 0
// Index changes clear it automatically. Different projection / sort / collation = a different shape.


/* ============================================================
   2. THE DATABASE PROFILER
   ============================================================ */

db.setProfilingLevel(0); db.system.profile.drop();         // clean slate (a previous run may have left entries / a sampleRate)
db.getProfilingStatus();                                   // { was: 0, slowms: ..., sampleRate: ... }  (level 0 = off, only slow-op logging)
db.setProfilingLevel(1, { slowms: 20, sampleRate: 1 });    // level 1: record operations slower than 20 ms into system.profile
db.getProfilingStatus();

// Run a slow query (COLLSCAN on city - no index) and a fast one (indexed)
db.bench_orders.find({ city: "Pune", status: "Cancelled" }).toArray().length;
db.bench_orders.find({ customerId: 42 }).toArray().length;

// The profile entry: what ran, how long, and the plan summary
db.system.profile.find({ ns: "companyDB.bench_orders", op: "query" }).sort({ ts: -1 }).limit(1).map(
    p => ({ op: p.op, ns: p.ns, millis: p.millis, planSummary: p.planSummary, keysExamined: p.keysExamined, docsExamined: p.docsExamined, nreturned: p.nreturned, filter: p.command.filter })
).toArray();
// planSummary: 'COLLSCAN', docsExamined 200000, millis > 20 - the fast indexed query was NOT recorded

// Top slow operations for the database (a classic DBA query)
db.system.profile.aggregate([
    { $match: { millis: { $gte: 20 } } },
    { $group: { _id: { ns: "$ns", plan: "$planSummary" }, n: { $sum: 1 }, avgMs: { $avg: "$millis" }, maxMs: { $max: "$millis" } } },
    { $sort: { avgMs: -1 } }, { $limit: 5 }
]);

// Level 2 = EVERY operation (development only - heavy). Level 0 = off. sampleRate to profile a fraction.
db.setProfilingLevel(2, { slowms: 20, sampleRate: 0.5 });
db.bench_orders.findOne({ customerId: 1 });
db.setProfilingLevel(0, { slowms: 100, sampleRate: 1 });   // OFF - always do this (and restore the defaults you changed)
db.getProfilingStatus().was;                               // 0
// system.profile is a capped collection (1 MB by default) in EACH database; drop it to resize: db.system.profile.drop()
// Slow operations are ALSO written to the mongod log ("Slow query" lines) whenever they exceed slowms, even at level 0.


/* ============================================================
   3. currentOp, killOp, maxTimeMS
   ============================================================ */

// What is running right now? (active, longer than 1 s, not the internal ops)
db.currentOp({ active: true, secs_running: { $gt: 1 }, ns: /^companyDB\./ }).inprog.map(
    o => ({ opid: o.opid, secs: o.secs_running, ns: o.ns, plan: o.planSummary, waitingForLock: o.waitingForLock })
);                                                          // [] on an idle server (internal / monitoring connections are filtered out by ns)
// The same via the admin command (works with filters like currentOp aggregation stage):
db.getSiblingDB("admin").aggregate([ { $currentOp: { allUsers: true, idleConnections: false } }, { $match: { active: true } }, { $count: "activeOps" } ]);
// To stop a runaway operation:  db.killOp(<opid>)   (the client receives an "Interrupted" error)

// maxTimeMS: let the SERVER abort a query that takes too long (protects the database from a slow client request)
try {
    db.bench_orders.find({ city: "Pune", status: "Cancelled" }).maxTimeMS(1).toArray();
} catch (e) {
    print("EXPECTED ERROR:", e.codeName, "-", e.message.substring(0, 60));   // MaxTimeMSExpired
}
db.bench_orders.find({ customerId: 42 }).maxTimeMS(1000).toArray().length;   // fast query: fine
// Aggregations: db.coll.aggregate(pipeline, { maxTimeMS: 5000 })


/* ============================================================
   4. AGGREGATION EXPLAIN AND OPTIMISER REWRITES
   ============================================================ */

db.bench_orders.dropIndexes();
db.bench_orders.createIndex({ status: 1, orderDate: -1 });

// $match after $project: the optimiser moves the $match BEFORE the $project and into the query -> index used
const agg1 = db.bench_orders.aggregate([
    { $project: { status: 1, orderDate: 1, totalAmount: 1 } },
    { $match: { status: "Cancelled" } },
    { $sort: { orderDate: -1 } },
    { $limit: 5 }
]).explain("executionStats");
agg1.stages ? agg1.stages.map(s => Object.keys(s)[0]) : "whole pipeline pushed down";   // [ '$cursor', '$sort' ]
plan(agg1.stages ? agg1.stages[0].$cursor : agg1);          // IXSCAN(status_1_orderDate_-1) ~5800 keys: the $match moved into the cursor (index used),
                                                            // but the $sort stayed BEHIND the $project -> all Cancelled orders read, then a top-5 sort.
// Write it in the natural order and the index delivers the sort too (keys ~= 5):
const agg1b = db.bench_orders.aggregate([
    { $match: { status: "Cancelled" } }, { $sort: { orderDate: -1 } }, { $limit: 5 },
    { $project: { status: 1, orderDate: 1, totalAmount: 1 } }
]).explain("executionStats");
plan(agg1b.stages ? agg1b.stages[0].$cursor : agg1b);       // IXSCAN -> FETCH -> LIMIT, keysExamined 5. Lesson: $match and $sort first, $project after.

// Compare: a $match that the optimiser CANNOT move (it depends on a computed field)
const agg2 = db.bench_orders.aggregate([
    { $set: { big: { $gt: ["$totalAmount", 150000] } } },
    { $match: { big: true, status: "Cancelled" } },
    { $count: "n" }
]).explain("executionStats");
plan(agg2.stages ? agg2.stages[0].$cursor : agg2);          // status part pushed down (IXSCAN on status), "big" filtered after $set
// Rewrite it so everything is indexable: { $match: { status: "Cancelled", totalAmount: { $gt: 150000 } } } first.

// $sort + $limit coalesce into a top-k sort; $skip + $limit merge; consecutive $match merge. Let the server show you:
const agg3 = db.bench_orders.aggregate([ { $match: { status: "Pending" } }, { $sort: { totalAmount: -1 } }, { $skip: 10 }, { $limit: 5 } ]).explain("executionStats");
agg3.stages ? agg3.stages.map(s => Object.keys(s)[0]) : plan(agg3);
// 8.x: the whole pipeline is handed to the query engine (SORT with limitAmount 15 = skip 10 + limit 5, then SKIP);
// older servers show [ '$cursor', '$sort' ] with the $sort carrying "limit: 15".


/* ============================================================
   5. $lookup - index the foreign field
   ============================================================ */

db.l12_customers.drop();
const seeded = db.l12_customers.insertMany(Array.from({ length: 50 }, (_, i) => ({ customerId: i + 1, name: "Customer " + (i + 1) })));
Object.keys(seeded.insertedIds).length;                   // 50
db.bench_orders.dropIndexes();                             // the join key bench_orders.customerId has NO index now
function timeIt(fn) { const t0 = Date.now(); const r = fn(); return { ms: Date.now() - t0, result: r }; }
const joinPipeline = [
    { $lookup: { from: "bench_orders", localField: "customerId", foreignField: "customerId", as: "orders" } },
    { $project: { _id: 0, customerId: 1, orders: { $size: "$orders" } } }
];

// 50 customers, each joined against 200 000 orders WITHOUT an index = 50 full collection scans (10 million documents)
timeIt(() => db.l12_customers.aggregate(joinPipeline).toArray()).ms;      // ~1000-3000 ms

db.bench_orders.createIndex({ customerId: 1 });
timeIt(() => db.l12_customers.aggregate(joinPipeline).toArray()).ms;      // a few ms - 50 index seeks

// The explain output names the join strategy and the index (search the tree for the "strategy" key)
function findKey(o, key) {
    if (o && typeof o === "object") { if (key in o) return o; for (const k of Object.keys(o)) { const r = findKey(o[k], key); if (r) return r; } }
    return null;
}
const lk = db.l12_customers.aggregate(joinPipeline).explain("executionStats");
const eq = findKey(lk, "strategy");
eq ? { stage: eq.stage, strategy: eq.strategy, indexName: eq.indexName } : "classic engine: see stages[].$lookup.indexesUsed";
// -> { stage: 'EQ_LOOKUP', strategy: 'IndexedLoopJoin', indexName: 'customerId_1' }  (without the index: NestedLoopJoin / HashJoin)
// Also: $match on the OUTER side before $lookup, and project away big fields before joining.


/* ============================================================
   6. MEMORY: cache and working set
   ============================================================ */

const cache = db.serverStatus().wiredTiger.cache;
({ cacheUsedMB: Math.round(cache["bytes currently in the cache"] / 1048576), cacheMaxMB: Math.round(cache["maximum bytes configured"] / 1048576),
   dirtyMB: Math.round(cache["tracked dirty bytes in the cache"] / 1048576), readIntoCacheMB: Math.round(cache["bytes read into cache"] / 1048576) });
const cs = db.bench_orders.stats();
({ dataMB: Math.round(cs.size / 1048576), storageMB: Math.round(cs.storageSize / 1048576), indexMB: Math.round(cs.totalIndexSize / 1048576), avgObjBytes: Math.round(cs.avgObjSize) });
// Rule: hot data + indexes (the working set) must fit in the cache (~50 % of RAM - 1 GB by default). If "bytes read into cache"
// grows constantly and latency climbs, you are paging from disk: add RAM, shrink indexes, archive data, or shard.


/* ============================================================
   7. THE SLOW-QUERY CHECKLIST (say this in the interview)
   ============================================================ */

print(`
 1. explain("executionStats"): COLLSCAN? keys/docs examined vs nReturned? in-memory SORT? FETCH with a filter?
 2. Predicate: selective? indexable? (no $ne/$nin/$exists:false/$where/unanchored or /i regex/$expr on computed values)
 3. Index: design with ESR, make it covering if cheap, check the prefix rule; verify with explain; hint only to test
 4. Profiler / logs: is this query the real problem? how often? which shape? currentOp for lock waits and long runners
 5. Plan cache: bad cached plan? (clear it, or change the shape) ; maxTimeMS to protect the server
 6. Aggregation: $match first, project early, $sort+$limit together, index the $lookup foreign field, allowDiskUse
 7. Server: working set vs cache, disk IOPS, replication lag, connection count, page faults
 8. Schema: embed vs reference, avoid unbounded arrays, bucket pattern, pre-computed fields (Level 13)
`);


/* ============================================================
   CLEANUP
   ============================================================ */
db.setProfilingLevel(0, { slowms: 100, sampleRate: 1 });
db.bench_orders.dropIndexes(); db.l12_customers.drop();

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
