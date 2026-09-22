/* ============================================================
   LEVEL 12 - QUERY PERFORMANCE  |  01_Practice_Explain_ESR_Covered.js
   ------------------------------------------------------------
   Topics : explain verbosity levels, reading the plan tree and
            per-stage stats, the ESR rule, covered queries,
            selectivity, $or and index intersection, predicates
            that cannot use indexes, hint, sort memory, COUNT_SCAN
            and DISTINCT_SCAN

   HOW TO PRACTICE: block by block, predict first.
   Uses bench_orders (200k docs, built here if missing).
   Random data -> numbers differ slightly from the comments.
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
   1. THE THREE VERBOSITY LEVELS
   ============================================================ */

db.bench_orders.createIndex({ customerId: 1 });

// queryPlanner: plan only, the query is NOT executed
const qp = db.bench_orders.find({ customerId: 42 }).explain();
qp.queryPlanner.winningPlan.queryPlan || qp.queryPlanner.winningPlan;   // the tree: FETCH <- IXSCAN with indexBounds
qp.queryPlanner.rejectedPlans.length;                                    // 0 (only one candidate)
qp.executionStats;                                                       // undefined

// executionStats: runs the winning plan and reports the numbers
const es = db.bench_orders.find({ customerId: 42 }).explain("executionStats");
({ nReturned: es.executionStats.nReturned, keys: es.executionStats.totalKeysExamined, docs: es.executionStats.totalDocsExamined, ms: es.executionStats.executionTimeMillis });

// Per-stage statistics: works / advanced / nReturned for each stage (read inner -> outer)
const st = es.executionStats.executionStages;
[ { stage: st.stage, works: st.works, nReturned: st.nReturned },
  { stage: st.inputStage.stage, works: st.inputStage.works, keysExamined: st.inputStage.keysExamined, seeks: st.inputStage.seeks } ];

// allPlansExecution: also runs the rejected candidates for a short trial -> shows WHY the winner won
db.bench_orders.createIndex({ status: 1 });
const ap = db.bench_orders.find({ customerId: 42, status: "Completed" }).explain("allPlansExecution");
ap.queryPlanner.winningPlan.queryPlan ? ap.queryPlanner.winningPlan.queryPlan.inputStage.indexName : ap.queryPlanner.winningPlan.inputStage.indexName;   // customerId_1
ap.executionStats.allPlansExecution.map(p => ({ nReturned: p.nReturned, works: p.executionStages.works, totalKeysExamined: p.totalKeysExamined }));
// The customerId plan produced 100 results within the trial; the status plan (90 % of the collection) did not -> rejected


/* ============================================================
   2. THE ESR RULE  (Equality -> Sort -> Range)
   ============================================================ */

// Query: completed orders above 150000, newest first, first page of 20
const q = { status: "Completed", totalAmount: { $gte: 150000 } };
const s = { orderDate: -1 };
db.bench_orders.dropIndexes();

// (a) no index: COLLSCAN + SORT of ~45000 matches
plan(db.bench_orders.find(q).sort(s).limit(20).explain("executionStats"));

// (b) Equality, Range, Sort  (wrong order): tight bounds on status+amount, but the SORT stage is back
db.bench_orders.createIndex({ status: 1, totalAmount: 1, orderDate: -1 }, { name: "ix_ERS" });
plan(db.bench_orders.find(q).sort(s).limit(20).explain("executionStats"));
// IXSCAN(ix_ERS) -> SORT -> FETCH: keysExamined ~45000 (every match) sorted in memory (the sort key is in the index, so only 20 docs are fetched) ~40 ms

// (c) Equality, Sort, Range  (ESR): index delivers the order; the range is filtered while walking the index
db.bench_orders.createIndex({ status: 1, orderDate: -1, totalAmount: 1 }, { name: "ix_ESR" });
plan(db.bench_orders.find(q).sort(s).limit(20).hint("ix_ESR").explain("executionStats"));
// IXSCAN(ix_ESR) -> FETCH -> LIMIT: no SORT; keysExamined ~80 (walked newest-first until 20 matched), docsExamined 20

// Without the limit the picture changes: ESR must walk ALL Completed keys (~180000) and filter; ERS reads ~45000 keys but sorts them.
plan(db.bench_orders.find(q).sort(s).hint("ix_ESR").explain("executionStats"));
plan(db.bench_orders.find(q).sort(s).hint("ix_ERS").explain("executionStats"));
// -> ESR is the rule for "first page / top-N" queries; for "return everything" the trade-off is sort cost vs keys examined. Measure!

// Let the planner choose (it races both)
plan(db.bench_orders.find(q).sort(s).limit(20).explain("executionStats"));


/* ============================================================
   3. COVERED QUERIES  (no FETCH, docsExamined 0)
   ============================================================ */

db.bench_orders.dropIndexes();
db.bench_orders.createIndex({ customerId: 1, totalAmount: 1 });

// Projection includes _id (not in the index) -> FETCH needed
plan(db.bench_orders.find({ customerId: 42 }, { customerId: 1, totalAmount: 1 }).explain("executionStats"));   // IXSCAN -> FETCH -> PROJECTION_SIMPLE
// Exclude _id -> covered
plan(db.bench_orders.find({ customerId: 42 }, { _id: 0, customerId: 1, totalAmount: 1 }).explain("executionStats"));   // IXSCAN -> PROJECTION_COVERED, docsExamined 0
// Covered + sorted by the index + aggregate in the app: "total spent by customer 42" without touching a document
db.bench_orders.find({ customerId: 42 }, { _id: 0, totalAmount: 1 }).toArray().reduce((a, d) => a + d.totalAmount, 0);

// A field outside the index breaks coverage
plan(db.bench_orders.find({ customerId: 42 }, { _id: 0, totalAmount: 1, status: 1 }).explain("executionStats"));   // FETCH again

// Multikey indexes cannot cover
db.bench_orders.createIndex({ tags: 1 });
plan(db.bench_orders.find({ tags: "b2b" }, { _id: 0, tags: 1 }).explain("executionStats"));   // FETCH (array must come from the document)


/* ============================================================
   4. SELECTIVITY  (an index on a low-cardinality field)
   ============================================================ */

db.bench_orders.dropIndexes();
db.bench_orders.createIndex({ status: 1 });
// Rare value: 3 % -> index is a win
plan(db.bench_orders.find({ status: "Cancelled" }).explain("executionStats"));    // IXSCAN, ~6000 keys, ~5 ms
// Common value: 90 % -> index scan + 180000 FETCHes is SLOWER than a plain COLLSCAN
plan(db.bench_orders.find({ status: "Completed" }).explain("executionStats"));    // IXSCAN, ~180000 keys+docs, maybe 100+ ms
plan(db.bench_orders.find({ status: "Completed" }).hint({ $natural: 1 }).explain("executionStats"));   // COLLSCAN, 200000 docs, often faster
// Lesson: index for the selective values; for the common value the planner may (rightly) choose a scan.


/* ============================================================
   5. $or, $in AND INDEX INTERSECTION
   ============================================================ */

db.bench_orders.dropIndexes();
db.bench_orders.createIndex({ customerId: 1 });
db.bench_orders.createIndex({ orderNo: 1 });

// $or: each branch can use its own index (OR stage merging two IXSCANs)
plan(db.bench_orders.find({ $or: [ { customerId: 42 }, { orderNo: 5 } ] }).explain("executionStats"));   // ... OR ... two IXSCAN
// $or with ONE unindexed branch -> the whole query scans
plan(db.bench_orders.find({ $or: [ { customerId: 42 }, { city: "Pune" } ] }).explain("executionStats"));  // COLLSCAN

// $in on one indexed field = several point ranges in one scan
plan(db.bench_orders.find({ customerId: { $in: [1, 2, 3, 4, 5] } }).explain("executionStats"));

// AND on two indexed fields: the planner usually picks ONE index and filters the rest (index intersection is rare)
db.bench_orders.createIndex({ city: 1 });
const two = db.bench_orders.find({ customerId: 42, city: "Pune" }).explain("executionStats");
plan(two);                                                                        // IXSCAN(customerId_1) -> FETCH (filter city)
// A compound index beats intersection every time:
db.bench_orders.createIndex({ customerId: 1, city: 1 });
plan(db.bench_orders.find({ customerId: 42, city: "Pune" }).explain("executionStats"));   // keys == docs == nReturned


/* ============================================================
   6. PREDICATES THAT CANNOT USE INDEX BOUNDS
   ============================================================ */

db.bench_orders.dropIndexes();
db.bench_orders.createIndex({ city: 1 });
db.bench_orders.createIndex({ status: 1 });

plan(db.bench_orders.find({ city: /^Pu/ }).explain("executionStats"));            // anchored, case-sensitive: IXSCAN with tight bounds ["Pu", "Pv")
plan(db.bench_orders.find({ city: /une/ }).explain("executionStats"));            // unanchored: IXSCAN over ALL keys (200000) - an index scan is not a seek
plan(db.bench_orders.find({ city: /^pu/i }).explain("executionStats"));           // case-insensitive: same full index scan
plan(db.bench_orders.find({ status: { $ne: "Completed" } }).explain("executionStats"));   // $ne: bounds are [MinKey,"Completed") U ("Completed",MaxKey] - works here (rare value), but generally scans a lot
plan(db.bench_orders.find({ status: { $nin: ["Completed", "Pending"] } }).explain("executionStats"));
plan(db.bench_orders.find({ city: { $exists: false } }).explain("executionStats"));       // IXSCAN on the [null, null] bounds + FETCH filter: 0 keys here (every doc has a city); with many nulls it is a big scan
plan(db.bench_orders.find({ $expr: { $eq: ["$city", "Pune"] } }).explain("executionStats"));   // $expr equality CAN use the index (5.0+), but functions on the field cannot:
plan(db.bench_orders.find({ $expr: { $eq: [ { $toLower: "$city" }, "pune" ] } }).explain("executionStats"));   // COLLSCAN ~100 ms
// $where = JavaScript evaluated for EVERY document: the full scan takes ~30 s here. Capped with maxTimeMS so you do not have to wait:
try {
    plan(db.bench_orders.find({ $where: "this.city == 'Pune'" }).maxTimeMS(3000).explain("executionStats"));
} catch (e) {
    print("EXPECTED ERROR:", e.codeName, "- $where could not finish 200000 documents in 3 s (a plain $eq takes 25 ms). Never use $where in production.");
}


/* ============================================================
   7. SORT MEMORY, allowDiskUse, LIMIT
   ============================================================ */

db.bench_orders.dropIndexes();
// An in-memory SORT reports its memory limit and how much it sorted
const srt = db.bench_orders.find({ status: "Pending" }).sort({ totalAmount: -1 }).explain("executionStats");
const sortStage = (function find(s) { if (!s) return null; if (s.stage === "SORT") return s; return find(s.inputStage); })(srt.executionStats.executionStages);
({ stage: sortStage && sortStage.stage, memLimitBytes: sortStage && sortStage.memLimit, sortedBytes: sortStage && sortStage.totalDataSizeSorted, usedDisk: sortStage && sortStage.usedDisk });
// 100 MB limit: bigger sorts fail unless allowDiskUse() (find, 6.0+) / { allowDiskUse: true } (aggregate) - or an index that provides the order.
db.bench_orders.find({ status: "Pending" }).sort({ totalAmount: -1 }).allowDiskUse().limit(1).explain("executionStats").executionStats.nReturned;   // 1

// LIMIT turns a full sort into a cheap top-k sort (only k documents kept in memory)
plan(db.bench_orders.find({ status: "Pending" }).sort({ totalAmount: -1 }).limit(5).explain("executionStats"));


/* ============================================================
   8. COUNT_SCAN and DISTINCT_SCAN  (answered from the index)
   ============================================================ */

db.bench_orders.createIndex({ status: 1 });
const cnt = db.bench_orders.explain("executionStats").count({ status: "Pending" });
plan(cnt);                                                                        // COUNT_SCAN(status_1): keys ~14000, docs 0
db.bench_orders.explain("executionStats").distinct("status").queryPlanner.winningPlan.stage;   // PROJECTION_COVERED over DISTINCT_SCAN
plan(db.bench_orders.explain("executionStats").distinct("status"));               // DISTINCT_SCAN: 3 keys examined for 3 values
// countDocuments({}) walks an index; estimatedDocumentCount() reads metadata:
db.bench_orders.explain("executionStats").count({}).queryPlanner.winningPlan.stage;   // RECORD_STORE_FAST_COUNT (metadata, no scan)


/* ============================================================
   CLEANUP
   ============================================================ */
db.bench_orders.dropIndexes();

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Profiler_PlanCache_Aggregation.js
   ------------------------------------------------------------ */
