/* ============================================================
   LEVEL 11 - INDEXES  |  02_Practice_Special_Indexes_Management.js
   ------------------------------------------------------------
   Topics : partial, TTL, text, hashed, wildcard, collation indexes,
            clustered collections, index management (list, drop,
            hide, usage stats, sizes, collMod), the write cost of
            indexes

   HOW TO PRACTICE: block by block, predict first.
   Needs bench_orders from 01 (built automatically if missing).
   ============================================================ */

use("companyDB");

function plan(explainOut) {
    const es = explainOut.executionStats;
    let s = explainOut.queryPlanner.winningPlan;
    if (s.queryPlan) s = s.queryPlan;
    const stages = [];
    while (s) { stages.push(s.stage + (s.indexName ? "(" + s.indexName + ")" : "")); s = s.inputStage || (s.inputStages && s.inputStages[0]); }
    return { plan: stages.reverse().join(" -> "), nReturned: es.nReturned, keysExamined: es.totalKeysExamined, docsExamined: es.totalDocsExamined, ms: es.executionTimeMillis };
}
function ensureBench(n = 200000) {                        // same builder as in 01 (each file is self-sufficient)
    if (db.bench_orders.estimatedDocumentCount() >= n) { print("bench_orders ready:", db.bench_orders.estimatedDocumentCount()); return; }
    db.bench_orders.drop();
    const cities = ["Delhi", "Mumbai", "Pune", "Bangalore", "Chennai", "Noida", "Kolkata", "Hyderabad"];
    const tagPool = ["gift", "bulk", "priority", "fragile", "return", "b2b"];
    const start = ISODate("2024-01-01").getTime(), span = 730 * 86400000;
    const t0 = Date.now();
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
    print("built bench_orders:", db.bench_orders.countDocuments(), "docs in", Date.now() - t0, "ms");
}
ensureBench();
db.bench_orders.dropIndexes();


/* ============================================================
   1. PARTIAL INDEX  -  index only the documents you query
   ============================================================ */

// 3 % of orders are Pending. An index on totalAmount for Pending orders only is tiny.
db.bench_orders.createIndex({ totalAmount: -1 }, { partialFilterExpression: { status: "Pending" }, name: "ix_pending_amount" });
db.bench_orders.stats().indexSizes;                       // ix_pending_amount is much smaller than a full index would be

// A query that IMPLIES the filter uses it ...
plan(db.bench_orders.find({ status: "Pending", totalAmount: { $gte: 150000 } }).explain("executionStats"));   // IXSCAN(ix_pending_amount)
// ... a query that does not guarantee status = "Pending" cannot
plan(db.bench_orders.find({ totalAmount: { $gte: 150000 } }).explain("executionStats"));                        // COLLSCAN
plan(db.bench_orders.find({ status: { $in: ["Pending", "Cancelled"] }, totalAmount: { $gte: 150000 } }).explain("executionStats"));   // COLLSCAN

// Partial unique: "each customer may have at most ONE Pending order" - a business rule enforced by an index.
// (On the 19 real orders: Pending = 1015 for customer 1 and 1017 for customer 3 -> the rule holds today.)
db.orders.aggregate([ { $out: "l11_orders" } ]);
db.l11_orders.createIndex({ customerId: 1 }, { unique: true, partialFilterExpression: { status: "Pending" }, name: "uq_one_pending_per_customer" });
try {
    db.l11_orders.insertOne({ _id: 1020, customerId: 1, status: "Pending", totalAmount: 1 });       // 2nd Pending for customer 1
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 90));   // E11000 ... uq_one_pending_per_customer
}
db.l11_orders.insertOne({ _id: 1021, customerId: 1, status: "Completed", totalAmount: 1 });          // Completed is not indexed -> fine
db.l11_orders.insertOne({ _id: 1022, customerId: 2, status: "Pending", totalAmount: 1 });            // first Pending for customer 2 -> fine
db.l11_orders.countDocuments();                            // 21


/* ============================================================
   2. TTL INDEX  -  automatic expiry
   ============================================================ */

db.l11_sessions.drop();
db.l11_sessions.createIndex({ createdAt: 1 }, { expireAfterSeconds: 3600 });      // delete 1 h after createdAt
db.l11_sessions.insertMany([
    { user: "old",  createdAt: new Date(Date.now() - 2 * 3600 * 1000) },           // already expired
    { user: "new",  createdAt: new Date() },
    { user: "text", createdAt: "2020-01-01" }                                      // NOT a Date -> never expires
]);
db.l11_sessions.getIndexes().find(i => i.expireAfterSeconds).expireAfterSeconds;  // 3600
// The TTL monitor runs every 60 seconds - "old" disappears within a minute of insert (check later with countDocuments()).
db.l11_sessions.countDocuments();                          // 3 now, 2 after the next TTL pass
// Change the expiry without rebuilding: collMod
db.runCommand({ collMod: "l11_sessions", index: { keyPattern: { createdAt: 1 }, expireAfterSeconds: 60 } });
// Server-wide TTL counters
db.serverStatus().metrics.ttl;                             // { deletedDocuments, passes, ... }


/* ============================================================
   3. TEXT INDEX  -  word search
   ============================================================ */

db.products.aggregate([ { $out: "l11_products" } ]);
db.l11_products.updateMany({}, [ { $set: { description: { $concat: ["A great ", { $toLower: "$category" }, " item: ", "$name", " with fast shipping"] } } } ]);
db.l11_products.createIndex({ name: "text", description: "text" }, { weights: { name: 10, description: 1 }, name: "tx_products" });

db.l11_products.find({ $text: { $search: "laptop" } }, { _id: 0, name: 1 });                       // Laptop
db.l11_products.find({ $text: { $search: "furniture" } }, { _id: 0, name: 1 });                    // Chair, Desk, Bookshelf (from description)
db.l11_products.find({ $text: { $search: "laptop mouse" } }, { _id: 0, name: 1 });                 // OR of words: Laptop, Mouse
db.l11_products.find({ $text: { $search: "\"fast shipping\"" } }).count();                         // phrase: 11
db.l11_products.find({ $text: { $search: "electronics -mouse" } }, { _id: 0, name: 1 });           // exclude a word
db.l11_products.find({ $text: { $search: "SHIPPING" } }).count();                                  // case-insensitive: 11
db.l11_products.find({ $text: { $search: "items" } }).count();                                     // stemming: "items" matches "item" -> 11

// Relevance score
db.l11_products.find(
    { $text: { $search: "laptop electronics" } }, { _id: 0, name: 1, score: { $meta: "textScore" } }
).sort({ score: { $meta: "textScore" } }).limit(3);                                                // Laptop first (name weight 10)

// Only ONE text index per collection
try {
    db.l11_products.createIndex({ category: "text" });
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 60));
}
plan(db.l11_products.find({ $text: { $search: "laptop" } }).explain("executionStats"));            // TEXT_MATCH ... IXSCAN(tx_products)
// For real search (typo tolerance, facets, autocomplete) use Atlas Search ($search) or an external engine.


/* ============================================================
   4. HASHED INDEX  -  equality only (sharding)
   ============================================================ */

db.bench_orders.createIndex({ employeeId: "hashed" });
plan(db.bench_orders.find({ employeeId: 105 }).explain("executionStats"));               // IXSCAN(employeeId_hashed)
plan(db.bench_orders.find({ employeeId: { $gt: 105 } }).explain("executionStats"));      // COLLSCAN - hashes have no order
// Hashed indexes spread monotonically increasing keys (dates, ObjectIds) evenly across shards - Level 18.


/* ============================================================
   5. WILDCARD INDEX  -  unknown field names
   ============================================================ */

// Give some orders a free-form "meta" sub-document with varying keys
db.bench_orders.updateMany({ orderNo: { $lte: 5000 } }, [ { $set: { meta: { $cond: [ { $eq: [ { $mod: ["$orderNo", 2] }, 0 ] }, { color: "red", size: "L" }, { source: "web", promo: "SUMMER" } ] } } } ]);
db.bench_orders.createIndex({ "meta.$**": 1 });
plan(db.bench_orders.find({ "meta.color": "red" }).explain("executionStats"));            // IXSCAN(meta.$**_1), ~2500
plan(db.bench_orders.find({ "meta.promo": "SUMMER" }).explain("executionStats"));         // same index, different path
// Wildcard indexes cannot be used for a plain sort on their fields and index every path -> use for truly dynamic schemas only.


/* ============================================================
   6. COLLATION INDEX  -  case-insensitive lookups
   ============================================================ */

db.bench_orders.createIndex({ city: 1 }, { collation: { locale: "en", strength: 2 }, name: "ix_city_ci" });
plan(db.bench_orders.find({ city: "delhi" }).collation({ locale: "en", strength: 2 }).explain("executionStats"));   // IXSCAN(ix_city_ci), ~25000
plan(db.bench_orders.find({ city: "delhi" }).explain("executionStats"));                                            // COLLSCAN, 0 results - no collation, wrong case
plan(db.bench_orders.find({ city: "Delhi" }).explain("executionStats"));                                            // COLLSCAN (the index has a different collation)
// Rule: the query's collation must match the index's collation exactly (or the field must be non-string).


/* ============================================================
   7. CLUSTERED COLLECTION  (5.3+)  -  the collection IS the index
   ============================================================ */

db.l11_clustered.drop();
db.createCollection("l11_clustered", { clusteredIndex: { key: { _id: 1 }, unique: true, name: "clustered_id" } });
const ins = db.l11_clustered.insertMany(Array.from({ length: 1000 }, (_, i) => ({ _id: i, v: i * 2 })));
Object.keys(ins.insertedIds).length;                      // 1000
db.l11_clustered.getIndexes();                            // the clustered index shows as an index, but there is no separate _id B-tree
db.getCollectionInfos({ name: "l11_clustered" })[0].options.clusteredIndex;
plan(db.l11_clustered.find({ _id: { $gte: 990 } }).explain("executionStats"));   // CLUSTERED_IXSCAN - a range scan on the data itself
// Like SQL Server's clustered index: documents stored in _id order. Good for time-based ids / append-only data, saves the _id index RAM.


/* ============================================================
   8. MANAGEMENT: list, drop, hide, usage, sizes
   ============================================================ */

db.bench_orders.getIndexes().map(i => i.name);
db.bench_orders.dropIndex({ "meta.$**": 1 });             // by key pattern
db.bench_orders.dropIndex("employeeId_hashed");           // by name

// hideIndex: the index is maintained but the planner ignores it -> safe way to test "can I drop this?"
db.bench_orders.createIndex({ customerId: 1 });
db.bench_orders.hideIndex("customerId_1");
plan(db.bench_orders.find({ customerId: 42 }).explain("executionStats"));   // COLLSCAN while hidden
db.bench_orders.unhideIndex("customerId_1");
plan(db.bench_orders.find({ customerId: 42 }).explain("executionStats"));   // IXSCAN again

// Usage counters since the last restart (check EVERY replica set member before dropping!)
db.bench_orders.aggregate([ { $indexStats: {} }, { $project: { name: 1, ops: "$accesses.ops", since: "$accesses.since" } } ]);

// Sizes
db.bench_orders.totalIndexSize();
db.bench_orders.stats().indexSizes;
db.bench_orders.stats({ scale: 1024 * 1024 }).totalIndexSize;   // MB

// Several indexes in one call: the shell helper takes KEY PATTERNS (options apply to all) ...
db.bench_orders.createIndexes([ { orderDate: 1 }, { status: 1, city: 1 } ]);
// ... the database COMMAND takes full specs (individual names / options):
db.runCommand({ createIndexes: "bench_orders", indexes: [ { key: { employeeId: 1, orderDate: -1 }, name: "ix_emp_date" } ] });
db.bench_orders.getIndexes().map(i => i.name);           // ..., orderDate_1, status_1_city_1, ix_emp_date

// Index builds: look at running builds with currentOp; kill one with killOp if needed
db.currentOp({ "command.createIndexes": { $exists: true } }).inprog.length;   // 0 (they were fast)


/* ============================================================
   9. THE COST OF INDEXES ON WRITES
   ============================================================ */

function timedInsert(coll, n) {
    const t0 = Date.now();
    db[coll].insertMany(Array.from({ length: n }, (_, i) => ({ a: i, b: i % 100, c: "x" + (i % 1000), d: new Date(), e: [i % 3, i % 5], f: i * 1.5 })), { ordered: false });
    return Date.now() - t0;
}
db.l11_cost0.drop(); db.l11_cost6.drop();
db.l11_cost6.createIndexes([ { a: 1 }, { b: 1 }, { c: 1 }, { d: 1 }, { e: 1 }, { f: 1, b: 1 } ]);
db.l11_cost6.getIndexes().length;                        // 7
print("20000 inserts, _id only  :", timedInsert("l11_cost0", 20000), "ms");
print("20000 inserts, 6 indexes :", timedInsert("l11_cost6", 20000), "ms");     // noticeably slower (2-4x is typical)
// Every index also costs RAM (the working set should fit the WiredTiger cache) and disk. Index what you query, nothing more.


/* ============================================================
   CLEANUP  (bench_orders stays for Level 12, without indexes)
   ============================================================ */
db.bench_orders.dropIndexes();
db.bench_orders.updateMany({ meta: { $exists: true } }, { $unset: { meta: "" } });
db.l11_sessions.drop(); db.l11_products.drop(); db.l11_clustered.drop(); db.l11_cost0.drop(); db.l11_cost6.drop(); db.l11_orders.drop();

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
