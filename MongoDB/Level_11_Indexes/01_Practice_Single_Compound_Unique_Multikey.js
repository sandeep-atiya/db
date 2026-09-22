/* ============================================================
   LEVEL 11 - INDEXES  |  01_Practice_Single_Compound_Unique_Multikey.js
   ------------------------------------------------------------
   Topics : building a 200k-document benchmark collection, reading
            explain() numbers, single-field, compound (prefix rule,
            sort direction), unique (+ missing values, partial
            unique), multikey (arrays, compound limitation)

   HOW TO PRACTICE: block by block, predict first.
   Builds companyDB.bench_orders once (about 10-20 s) and keeps it
   for Level 12. Random data -> your numbers differ slightly.
   ============================================================ */

use("companyDB");


/* ============================================================
   0. HELPERS: build the benchmark collection, summarise a plan
   ============================================================ */

function ensureBench(n = 200000) {
    if (db.bench_orders.estimatedDocumentCount() >= n) { print("bench_orders ready:", db.bench_orders.estimatedDocumentCount()); return; }
    db.bench_orders.drop();
    const cities = ["Delhi", "Mumbai", "Pune", "Bangalore", "Chennai", "Noida", "Kolkata", "Hyderabad"];
    const tagPool = ["gift", "bulk", "priority", "fragile", "return", "b2b"];
    const start = ISODate("2024-01-01").getTime(), span = 730 * 86400000;
    const t0 = Date.now();
    for (let b = 0; b < n / 20000; b++) {
        db.bench_orders.insertMany(Array.from({ length: 20000 }, (_, i) => {
            const k = b * 20000 + i, r = Math.random();
            return {
                orderNo: k + 1,
                customerId: Math.floor(Math.random() * 2000) + 1,
                employeeId: 101 + (k % 12),
                status: r < 0.90 ? "Completed" : r < 0.97 ? "Pending" : "Cancelled",
                orderDate: new Date(start + Math.floor(Math.random() * span)),
                totalAmount: Math.floor(Math.random() * 199500) + 500,
                city: cities[k % cities.length],
                tags: tagPool.filter(() => Math.random() < 0.25),
                items: Array.from({ length: 1 + (k % 3) }, (_, j) => ({ productId: 1 + ((k + j) % 11), qty: 1 + (j % 4) }))
            };
        }), { ordered: false });
    }
    print("built bench_orders:", db.bench_orders.countDocuments(), "docs in", Date.now() - t0, "ms");
}

// Reads the stages inner->outer and the key counters of an explain("executionStats") output
function plan(explainOut) {
    const es = explainOut.executionStats;
    let s = explainOut.queryPlanner.winningPlan;
    if (s.queryPlan) s = s.queryPlan;                     // SBE plans nest the classic plan under queryPlan
    const stages = [];
    while (s) { stages.push(s.stage + (s.indexName ? "(" + s.indexName + ")" : "")); s = s.inputStage || (s.inputStages && s.inputStages[0]); }
    return { plan: stages.reverse().join(" -> "), nReturned: es.nReturned, keysExamined: es.totalKeysExamined, docsExamined: es.totalDocsExamined, ms: es.executionTimeMillis };
}

ensureBench();
db.bench_orders.dropIndexes();                            // start with only _id
db.bench_orders.getIndexes().map(i => i.name);           // [ '_id_' ]


/* ============================================================
   1. BASELINE: COLLECTION SCAN
   ============================================================ */

plan(db.bench_orders.find({ customerId: 42 }).explain("executionStats"));
// plan: COLLSCAN, nReturned ~100, keysExamined 0, docsExamined 200000  <- every document was read

plan(db.bench_orders.find({ orderNo: 12345 }).explain("executionStats"));      // same story: 200000 docs for 1 result
plan(db.bench_orders.find({ _id: db.bench_orders.findOne()._id }).explain("executionStats"));   // _id: EXPRESS_IXSCAN / IXSCAN, 1 key, 1 doc


/* ============================================================
   2. SINGLE-FIELD INDEX
   ============================================================ */

db.bench_orders.createIndex({ customerId: 1 });          // 'customerId_1'
plan(db.bench_orders.find({ customerId: 42 }).explain("executionStats"));
// plan: IXSCAN(customerId_1) -> FETCH, keysExamined ~100 = docsExamined ~100 = nReturned  <- ideal ratio

// Range and $in also use it
plan(db.bench_orders.find({ customerId: { $gte: 1990 } }).explain("executionStats"));          // ~1100 keys
plan(db.bench_orders.find({ customerId: { $in: [1, 2, 3] } }).explain("executionStats"));      // 3 ranges in one scan

// The index also serves a SORT on that field (no SORT stage) ...
plan(db.bench_orders.find({}).sort({ customerId: 1 }).limit(5).explain("executionStats"));   // IXSCAN -> FETCH -> LIMIT, 5 keys
// ... but sorting on a non-indexed field needs an in-memory SORT (limit keeps it a small top-k sort)
plan(db.bench_orders.find({ customerId: 42 }).sort({ totalAmount: -1 }).explain("executionStats"));   // ... -> SORT

// A filter on ANOTHER field still scans
plan(db.bench_orders.find({ orderNo: 12345 }).explain("executionStats"));      // COLLSCAN


/* ============================================================
   3. COMPOUND INDEX and the PREFIX RULE
   ============================================================ */

db.bench_orders.createIndex({ status: 1, orderDate: -1 }, { name: "ix_status_date" });

// status alone (prefix) -> uses it
plan(db.bench_orders.find({ status: "Cancelled" }).explain("executionStats"));                 // IXSCAN(ix_status_date), ~6000 keys
// status + date range -> uses both fields (tight bounds)
plan(db.bench_orders.find({ status: "Cancelled", orderDate: { $gte: ISODate("2025-06-01") } }).explain("executionStats"));   // ~1800 keys
// date ALONE -> NOT a prefix -> COLLSCAN
plan(db.bench_orders.find({ orderDate: { $gte: ISODate("2025-12-01") } }).explain("executionStats"));

// Sort direction: the index is (status asc, orderDate desc)
plan(db.bench_orders.find({ status: "Pending" }).sort({ orderDate: -1 }).limit(3).explain("executionStats"));   // no SORT stage
plan(db.bench_orders.find({ status: "Pending" }).sort({ orderDate: 1 }).limit(3).explain("executionStats"));    // still no SORT (index walked backwards)
plan(db.bench_orders.find({ status: "Pending" }).sort({ totalAmount: 1 }).limit(3).explain("executionStats"));  // SORT stage (totalAmount not in index)

// Equality on the 2nd field WITHOUT the 1st: not a prefix -> COLLSCAN (0 results: no order at exactly midnight)
plan(db.bench_orders.find({ orderDate: ISODate("2025-01-01") }).explain("executionStats"));

// Redundant index: { status: 1 } is a prefix of ix_status_date -> unnecessary
db.bench_orders.createIndex({ status: 1 });
db.bench_orders.getIndexes().map(i => i.name);           // customerId_1, ix_status_date, status_1  <- drop status_1
db.bench_orders.dropIndex("status_1");


/* ============================================================
   4. UNIQUE INDEX  (+ what "missing" means)
   ============================================================ */

db.bench_orders.createIndex({ orderNo: 1 }, { unique: true, name: "uq_orderNo" });
try {
    db.bench_orders.insertOne({ orderNo: 1, customerId: 1, status: "Pending" });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                  // E11000 duplicate key error ... uq_orderNo dup key: { orderNo: 1 }
}
plan(db.bench_orders.find({ orderNo: 12345 }).explain("executionStats"));      // IXSCAN(uq_orderNo), 1 key, 1 doc

// Missing field = null for a unique index -> only ONE document may lack the field
db.l11_users.drop();
db.l11_users.createIndex({ email: 1 }, { unique: true });
db.l11_users.insertOne({ name: "a", email: "a@x.com" });
db.l11_users.insertOne({ name: "b" });                    // ok: first "null"
try {
    db.l11_users.insertOne({ name: "c" });                // second missing -> duplicate null!
} catch (e) {
    print("EXPECTED ERROR:", e.message);
}
try {
    db.l11_users.insertOne({ name: "d", email: null });   // explicit null = same thing
} catch (e) {
    print("EXPECTED ERROR:", e.message);
}

// Fix: PARTIAL unique index - uniqueness only for real strings (this is what 00_Setup did for customers.email)
db.l11_users.dropIndex("email_1");
db.l11_users.createIndex({ email: 1 }, { unique: true, partialFilterExpression: { email: { $type: "string" } } });
db.l11_users.insertMany([ { name: "c" }, { name: "d", email: null }, { name: "e" } ]);   // all fine now
db.l11_users.countDocuments();                            // 5
try {
    db.l11_users.insertOne({ name: "f", email: "a@x.com" });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                  // real duplicates are still rejected
}

// (Legacy) sparse: same idea, only for "field exists" - prefer partial
db.l11_users.createIndex({ phone: 1 }, { unique: true, sparse: true });

// A unique index cannot be created while duplicates exist
db.l11_users.insertMany([ { name: "g", city: "Delhi" }, { name: "h", city: "Delhi" } ]);
try {
    db.l11_users.createIndex({ city: 1 }, { unique: true });
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 60));
}


/* ============================================================
   5. MULTIKEY INDEX  (arrays)
   ============================================================ */

db.bench_orders.createIndex({ tags: 1 });                // automatically multikey: one key per element
plan(db.bench_orders.find({ tags: "priority" }).explain("executionStats"));    // IXSCAN(tags_1), ~50000 keys
db.bench_orders.find({ tags: "priority" }).explain().queryPlanner.winningPlan.queryPlan ?
    db.bench_orders.find({ tags: "priority" }).explain().queryPlanner.winningPlan.queryPlan.inputStage.isMultiKey :
    db.bench_orders.find({ tags: "priority" }).explain().queryPlanner.winningPlan.inputStage.isMultiKey;   // true

// Index on a field INSIDE an array of documents
db.bench_orders.createIndex({ "items.productId": 1 });
plan(db.bench_orders.find({ "items.productId": 11 }).explain("executionStats"));

// $all uses the multikey index (intersection of ranges); $size cannot
plan(db.bench_orders.find({ tags: { $all: ["gift", "b2b"] } }).explain("executionStats"));   // IXSCAN
plan(db.bench_orders.find({ tags: { $size: 3 } }).explain("executionStats"));                 // COLLSCAN

// LIMITATION: a compound index may contain only ONE array field per document
db.l11_multi.drop();
db.l11_multi.insertOne({ a: [1, 2], b: [3, 4] });
try {
    db.l11_multi.createIndex({ a: 1, b: 1 });
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 90));   // cannot index parallel arrays [b] [a]
}
db.l11_multi.drop();
db.l11_multi.createIndex({ a: 1, b: 1 });                 // fine on an empty collection ...
db.l11_multi.insertOne({ a: [1, 2], b: 5 });              // ... and fine when only one is an array
try {
    db.l11_multi.insertOne({ a: [1, 2], b: [3, 4] });     // ... but this document is rejected
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 90));
}

// Multikey + sort: sorting on an array field uses the min (asc) / max (desc) element. The index is used,
// but notice keysExamined (~35000 for 2 results): multikey bounds + de-duplication make this far from free.
plan(db.bench_orders.find({ tags: "gift" }).sort({ tags: 1 }).limit(2).explain("executionStats"));


/* ============================================================
   6. WHAT WE HAVE NOW
   ============================================================ */

db.bench_orders.getIndexes().map(i => ({ name: i.name, key: i.key, unique: !!i.unique }));
db.bench_orders.totalIndexSize();                         // bytes (a few MB)
db.bench_orders.stats().indexSizes;

/* ------------------------------------------------------------
   Indexes are kept for 02_Practice_Special_Indexes_Management.js.
   CLEANUP of the small collections:
   ------------------------------------------------------------ */
db.l11_users.drop(); db.l11_multi.drop();

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Special_Indexes_Management.js
   ------------------------------------------------------------ */
