/* ============================================================
   LEVEL 12 - QUERY PERFORMANCE  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Uses bench_orders (built if missing). Indexes dropped at the end.
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

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  The app's hottest query: find({ city: "Delhi", status: "Pending", totalAmount: { $gte: 50000 } })
        .sort({ orderDate: -1 }).limit(10). Design the index with ESR, create it, and prove
        with plan(): no SORT stage and keysExamined close to nReturned.
   Q2.  Make find({ employeeId: 105 }, { _id: 0, employeeId: 1, orderNo: 1 }) covered.
        Prove docsExamined is 0.
   Q3.  Explain why find({ city: { $ne: "Delhi" } }) is slow even with an index on city.
        Show the numbers.
   Q4.  Rewrite find({ $expr: { $eq: [{ $toUpper: "$city" }, "PUNE"] } }) so it can use an
        index on city (data is stored capitalised). Compare both plans.
   Q5.  Turn on the profiler for operations slower than 30 ms, run a collection scan,
        and print the profile entry's planSummary and docsExamined. Turn it off.
   Q6.  Run a deliberately slow query with maxTimeMS(1) and catch the error.
   Q7.  Show that after creating an index the plan cache for bench_orders is empty, run
        the Q1 query twice, and check that the plan is now cached (isCached / list()).
   Q8.  Aggregation: [ { $project: { customerId: 1, totalAmount: 1 } }, { $match: { customerId: 7 } } ]
        - does the $match use an index on customerId? Prove it with explain.
   Q9.  For countDocuments({ status: "Pending" }): which stage do you expect with an index
        on status? Prove it.
   Q10. (Think) A dashboard query does $group over all 200k orders every 5 seconds. List
        three ways to make it cheap.
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1  E: city, status  S: orderDate  R: totalAmount
db.bench_orders.createIndex({ city: 1, status: 1, orderDate: -1, totalAmount: 1 }, { name: "ix_q1_esr" });
plan(db.bench_orders.find({ city: "Delhi", status: "Pending", totalAmount: { $gte: 50000 } }).sort({ orderDate: -1 }).limit(10).explain("executionStats"));
// IXSCAN(ix_q1_esr) -> FETCH -> LIMIT ; keysExamined ~15 for nReturned 10 (walks Delhi/Pending newest-first, skipping cheap orders)

// Q2
db.bench_orders.createIndex({ employeeId: 1, orderNo: 1 });
plan(db.bench_orders.find({ employeeId: 105 }, { _id: 0, employeeId: 1, orderNo: 1 }).explain("executionStats"));   // PROJECTION_COVERED, docsExamined 0

// Q3
db.bench_orders.createIndex({ city: 1 });
plan(db.bench_orders.find({ city: { $ne: "Delhi" } }).explain("executionStats"));
// IXSCAN with two ranges (< Delhi, > Delhi) returning 175000 keys + 175000 FETCHes: 7/8 of the collection. Not selective -> a COLLSCAN is as good or better.

// Q4
plan(db.bench_orders.find({ $expr: { $eq: [ { $toUpper: "$city" }, "PUNE" ] } }).explain("executionStats"));   // COLLSCAN: function on the field
plan(db.bench_orders.find({ city: "Pune" }).explain("executionStats"));                                          // IXSCAN(city_1): store data in a canonical form and query it as stored
// (case-insensitive needs: a collation index + collation on the query, or a lowercased copy of the field)

// Q5
db.setProfilingLevel(1, { slowms: 30 });
db.bench_orders.find({ tags: "gift", status: "Cancelled" }).toArray().length;   // COLLSCAN (no index on tags)
db.system.profile.find({ ns: "companyDB.bench_orders" }).sort({ ts: -1 }).limit(1).map(p => ({ planSummary: p.planSummary, docsExamined: p.docsExamined, millis: p.millis })).toArray();
db.setProfilingLevel(0);

// Q6
try { db.bench_orders.find({ tags: "gift", status: "Cancelled" }).maxTimeMS(1).toArray(); } catch (e) { print("EXPECTED ERROR:", e.codeName); }   // MaxTimeMSExpired

// Q7
db.bench_orders.createIndex({ orderNo: 1 });                // any index change clears the cache
db.bench_orders.getPlanCache().list().length;               // 0
db.bench_orders.find({ city: "Delhi", status: "Pending", totalAmount: { $gte: 50000 } }).sort({ orderDate: -1 }).limit(10).toArray().length;
db.bench_orders.find({ city: "Mumbai", status: "Cancelled", totalAmount: { $gte: 1000 } }).sort({ orderDate: -1 }).limit(10).toArray().length;
db.bench_orders.find({ city: "Pune", status: "Pending", totalAmount: { $gte: 50000 } }).sort({ orderDate: -1 }).limit(10).explain().queryPlanner.winningPlan.isCached;   // true (same shape)
db.bench_orders.getPlanCache().list().length;               // >= 1

// Q8
db.bench_orders.createIndex({ customerId: 1 });
const q8 = db.bench_orders.aggregate([ { $project: { customerId: 1, totalAmount: 1 } }, { $match: { customerId: 7 } } ]).explain("executionStats");
plan(q8.stages ? q8.stages[0].$cursor : q8);                 // IXSCAN(customerId_1): the optimiser moved $match before $project

// Q9
db.bench_orders.createIndex({ status: 1 });
plan(db.bench_orders.explain("executionStats").count({ status: "Pending" }));   // COUNT_SCAN(status_1), docsExamined 0

// Q10
// 1) Pre-aggregate: $merge the group result into a summary collection on a schedule / on write (computed pattern), read that.
// 2) Incremental counters: $inc a stats document on every order write instead of recomputing.
// 3) Reduce the input: $match on an indexed time range (only today's orders), project only needed fields, or use a covered
//    query for the group key; cache the dashboard result in the app for 5 s; run on a secondary (readPreference).

db.bench_orders.dropIndexes();
