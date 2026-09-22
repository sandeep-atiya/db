/* ============================================================
   LEVEL 11 - INDEXES  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Uses bench_orders (built by 01_Practice) and small l11_ex_*
   collections. All indexes are dropped at the end.
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
function ensureBench(n = 200000) {                        // builds the benchmark collection if 01_Practice was not run
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
ensureBench();
db.bench_orders.dropIndexes();

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Show that find({ city: "Pune", status: "Cancelled" }) on bench_orders is
        a COLLSCAN. Create ONE index that makes it an IXSCAN with
        keysExamined == nReturned. Which field goes first and why?
   Q2.  The app runs find({ status: "Pending" }).sort({ orderDate: -1 }).limit(20).
        Create the index that avoids an in-memory SORT and prove it with explain.
   Q3.  Will the index from Q2 help find({ orderDate: { $gte: ISODate("2025-10-01") } })?
        Prove your answer.
   Q4.  Enforce that orderNo is unique. Then try to create a unique index on
        customerId - what happens and why?
   Q5.  Create l11_ex_users with 3 documents: two WITHOUT a phone field and one
        with phone "1". Create a unique index on phone that still allows the two
        documents without a phone.
   Q6.  Create a TTL index on l11_ex_tokens.expiresAt that deletes documents AS
        SOON AS expiresAt passes (hint: expireAfterSeconds 0).
   Q7.  Create a partial index that only indexes Cancelled orders by totalAmount,
        then show one query that uses it and one that cannot.
   Q8.  Make find({ tags: "b2b" }) use an index. Is that index multikey?
   Q9.  Create a text index on l11_ex_articles (title weight 5, body weight 1),
        insert 3 articles, and search for a word that appears only in one body.
   Q10. Hide the index from Q1, show the plan falls back to COLLSCAN, unhide it.
   Q11. List every index of bench_orders with its size in KB, then drop them all
        except _id in one call.
   Q12. (Think) A colleague adds indexes { a: 1 }, { a: 1, b: 1 } and { a: 1, b: 1, c: 1 }.
        Which are redundant? What does each extra index cost?
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
plan(db.bench_orders.find({ city: "Pune", status: "Cancelled" }).explain("executionStats"));          // COLLSCAN, 200000 docs
db.bench_orders.createIndex({ city: 1, status: 1 }, { name: "ix_city_status" });
plan(db.bench_orders.find({ city: "Pune", status: "Cancelled" }).explain("executionStats"));          // IXSCAN(ix_city_status): keys == docs == nReturned (~750)
// Both are equalities, so either order works for THIS query; put the field you also query alone (or the more selective one) first.
// { status: 1, city: 1 } would serve { status } alone; { city: 1, status: 1 } serves { city } alone.

// Q2
db.bench_orders.createIndex({ status: 1, orderDate: -1 }, { name: "ix_status_date" });
plan(db.bench_orders.find({ status: "Pending" }).sort({ orderDate: -1 }).limit(20).explain("executionStats"));   // IXSCAN -> FETCH -> LIMIT, no SORT, 20 keys

// Q3
plan(db.bench_orders.find({ orderDate: { $gte: ISODate("2025-10-01") } }).explain("executionStats"));            // COLLSCAN - orderDate is not a prefix

// Q4
db.bench_orders.createIndex({ orderNo: 1 }, { unique: true });
try {
    db.bench_orders.createIndex({ customerId: 1 }, { unique: true });
} catch (e) {
    print("EXPECTED ERROR:", e.message.substring(0, 70));   // E11000: customers have many orders -> duplicates exist -> build fails
}

// Q5
db.l11_ex_users.drop();
db.l11_ex_users.insertMany([ { name: "a" }, { name: "b" }, { name: "c", phone: "1" } ]);
db.l11_ex_users.createIndex({ phone: 1 }, { unique: true, partialFilterExpression: { phone: { $exists: true } } });
db.l11_ex_users.insertOne({ name: "d" });                                                   // fine
try { db.l11_ex_users.insertOne({ name: "e", phone: "1" }); } catch (e) { print("EXPECTED ERROR:", e.message.substring(0, 60)); }

// Q6
db.l11_ex_tokens.drop();
db.l11_ex_tokens.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
db.l11_ex_tokens.insertOne({ token: "abc", expiresAt: new Date(Date.now() + 5 * 60 * 1000) });   // gone ~5 min from now (next TTL pass after expiry)

// Q7
db.bench_orders.createIndex({ totalAmount: 1 }, { partialFilterExpression: { status: "Cancelled" }, name: "ix_cancelled_amount" });
plan(db.bench_orders.find({ status: "Cancelled", totalAmount: { $lt: 1000 } }).explain("executionStats"));   // IXSCAN(ix_cancelled_amount)
plan(db.bench_orders.find({ totalAmount: { $lt: 1000 } }).explain("executionStats"));                        // COLLSCAN (status not guaranteed)

// Q8
db.bench_orders.createIndex({ tags: 1 });
const q8 = db.bench_orders.find({ tags: "b2b" }).explain("executionStats");
plan(q8);                                                                                       // IXSCAN(tags_1)
(q8.queryPlanner.winningPlan.queryPlan || q8.queryPlanner.winningPlan).inputStage.isMultiKey;   // true

// Q9
db.l11_ex_articles.drop();
db.l11_ex_articles.insertMany([
    { title: "MongoDB indexes", body: "B-tree structures for fast lookups" },
    { title: "Sharding basics", body: "Distribute data across shards with a shard key" },
    { title: "Replication", body: "Oplog, elections and failover explained" }
]);
db.l11_ex_articles.createIndex({ title: "text", body: "text" }, { weights: { title: 5, body: 1 } });
db.l11_ex_articles.find({ $text: { $search: "oplog" } }, { _id: 0, title: 1 });               // Replication

// Q10
db.bench_orders.hideIndex("ix_city_status");
plan(db.bench_orders.find({ city: "Pune", status: "Cancelled" }).explain("executionStats"));    // falls back to ix_status_date (5841 keys for 691 docs) - or COLLSCAN if no other index fits
db.bench_orders.unhideIndex("ix_city_status");

// Q11
const sizes = db.bench_orders.stats().indexSizes;
Object.keys(sizes).map(k => ({ index: k, KB: Math.round(sizes[k] / 1024) }));
db.bench_orders.dropIndexes();                                                                  // everything except _id
db.bench_orders.getIndexes().map(i => i.name);                                                  // [ '_id_' ]

// Q12
// { a: 1 } and { a: 1, b: 1 } are redundant: { a: 1, b: 1, c: 1 } serves every query they serve (prefix rule).
// Each extra index costs: slower inserts/updates/deletes on a, b, c; RAM in the cache; disk; longer index builds and backups.

db.l11_ex_users.drop(); db.l11_ex_tokens.drop(); db.l11_ex_articles.drop();
