/* ============================================================
   LEVEL 09  |  02_Practice_Window_Facet_Bucket.js
   ------------------------------------------------------------
   Topics : $setWindowFields ($rank / $denseRank / $documentNumber,
            partitions, running totals, $shift = LAG/LEAD, moving
            average, month-over-month growth), $facet, $bucket,
            $bucketAuto, $replaceRoot / $replaceWith, $sample

   HOW TO PRACTICE: block by block, predict first. Read-only.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. RANK vs DENSE_RANK vs ROW_NUMBER  (Amit & Pooja tie at 65000)
   ============================================================ */

db.employees.aggregate([
    { $setWindowFields: { sortBy: { salary: -1 }, output: {
        rowNum: { $documentNumber: {} },
        rnk:    { $rank: {} },
        dense:  { $denseRank: {} } } } },
    { $project: { _id: 0, name: 1, salary: 1, rowNum: 1, rnk: 1, dense: 1 } }
]);
// ... Karan 70000 5/5/5, Amit 65000 6/6/6, Pooja 65000 7/6/6, Vikram 62000 8/8/7 ...

// Nth highest salary the SQL way: DENSE_RANK = N
db.employees.aggregate([
    { $setWindowFields: { sortBy: { salary: -1 }, output: { dense: { $denseRank: {} } } } },
    { $match: { dense: 2 } },
    { $project: { _id: 0, name: 1, salary: 1 } }
]);                                                       // Rahul 85000

// Top-N per group with PARTITION BY (rank within department)
db.employees.aggregate([
    { $setWindowFields: { partitionBy: "$departmentId", sortBy: { salary: -1 }, output: { r: { $rank: {} } } } },
    { $match: { r: { $lte: 2 } } },
    { $project: { _id: 0, departmentId: 1, name: 1, salary: 1, r: 1 } },
    { $sort: { departmentId: 1, r: 1 } }
]);


/* ============================================================
   2. RUNNING TOTAL, LAG / LEAD, MOVING AVERAGE
   ============================================================ */

// Running total of order amounts by date (SUM OVER ORDER BY ... ROWS UNBOUNDED PRECEDING)
// NOTE: $rank / $denseRank / $documentNumber demand a sortBy with EXACTLY ONE field (orderDate is unique here).
//       Need a tiebreaker? Build a composite sort field first ($set: { k: { $concat: [...] } }) or use $shift / $sum, which accept several keys.
db.orders.aggregate([
    { $match: { status: "Completed" } },
    { $setWindowFields: { sortBy: { orderDate: 1 }, output: {
        running: { $sum: "$totalAmount", window: { documents: ["unbounded", "current"] } },
        seq:     { $documentNumber: {} } } } },
    { $project: { _id: 1, orderDate: 1, totalAmount: 1, running: 1, seq: 1 } },
    { $limit: 5 }
]);                                                       // 1001 75000 -> 75000, 1002 -> 85000, 1003 -> 110000, 1004 -> 125000, 1005 -> 175000

// LAG / LEAD with $shift
db.orders.aggregate([
    { $match: { status: "Completed" } },
    { $setWindowFields: { sortBy: { orderDate: 1, _id: 1 }, output: {
        prevAmount: { $shift: { output: "$totalAmount", by: -1, default: null } },
        nextAmount: { $shift: { output: "$totalAmount", by: 1,  default: null } } } } },
    { $project: { _id: 1, totalAmount: 1, prevAmount: 1, nextAmount: 1, diff: { $subtract: ["$totalAmount", "$prevAmount"] } } },
    { $limit: 4 }
]);

// Moving average over the current and 2 previous orders
db.orders.aggregate([
    { $match: { status: "Completed" } },
    { $setWindowFields: { sortBy: { orderDate: 1, _id: 1 }, output: {
        mov3: { $avg: "$totalAmount", window: { documents: [-2, 0] } } } } },
    { $project: { _id: 1, totalAmount: 1, mov3: { $round: ["$mov3", 0] } } },
    { $limit: 4 }
]);                                                       // 75000, 42500, 36667, 16667

// Partitioned running total: per customer
db.orders.aggregate([
    { $setWindowFields: { partitionBy: "$customerId", sortBy: { orderDate: 1 }, output: {
        spentSoFar: { $sum: "$totalAmount", window: { documents: ["unbounded", "current"] } },
        orderNo:    { $documentNumber: {} } } } },
    { $match: { customerId: 1 } },
    { $project: { _id: 1, orderDate: 1, totalAmount: 1, orderNo: 1, spentSoFar: 1 } }
]);                                                       // 1001 75000, 1004 90000, 1009 96000, 1015 128000

// Range window by DATE: revenue in the 30 days before each order (unit: "day")
db.orders.aggregate([
    { $setWindowFields: { sortBy: { orderDate: 1 }, output: {
        last30d: { $sum: "$totalAmount", window: { range: [-30, 0], unit: "day" } } } } },
    { $project: { _id: 1, orderDate: 1, totalAmount: 1, last30d: 1 } },
    { $limit: 4 }
]);


/* ============================================================
   3. MONTH-OVER-MONTH GROWTH  ($group per month, then $shift)
   ============================================================ */

db.orders.aggregate([
    { $match: { status: "Completed" } },
    { $group: { _id: { $dateTrunc: { date: "$orderDate", unit: "month" } }, revenue: { $sum: "$totalAmount" } } },
    { $setWindowFields: { sortBy: { _id: 1 }, output: { prev: { $shift: { output: "$revenue", by: -1 } } } } },
    { $project: { _id: 0, month: { $dateToString: { format: "%Y-%m", date: "$_id" } }, revenue: 1, prev: 1,
                  growthPct: { $cond: [ { $or: [ { $eq: ["$prev", null] }, { $eq: ["$prev", 0] } ] }, null,
                               { $round: [ { $multiply: [ { $divide: [ { $subtract: ["$revenue", "$prev"] }, "$prev" ] }, 100 ] }, 1 ] } ] } } }
]);                                                       // 2025-02: 65000 vs 110000 -> -40.9 ; 2025-03: 84500 -> 30 ; ...


/* ============================================================
   4. $facet - several results in one pass
   ============================================================ */

db.orders.aggregate([
    { $match: { status: "Completed" } },                  // filter BEFORE $facet (indexes usable here, not inside)
    { $facet: {
        byStatus:   [ { $sortByCount: "$payment.method" } ],
        top3:       [ { $sort: { totalAmount: -1 } }, { $limit: 3 }, { $project: { _id: 1, totalAmount: 1 } } ],
        summary:    [ { $group: { _id: null, n: { $sum: 1 }, revenue: { $sum: "$totalAmount" }, avg: { $avg: "$totalAmount" } } } ],
        perMonth:   [ { $group: { _id: { $month: "$orderDate" }, n: { $sum: 1 } } }, { $sort: { _id: 1 } } ]
    } }
]);                                                       // ONE document with 4 arrays

// Typical use: paginated results + total count for the UI in one query
db.products.aggregate([
    { $match: { category: "Electronics" } },
    { $facet: {
        page:  [ { $sort: { price: -1 } }, { $skip: 0 }, { $limit: 3 }, { $project: { _id: 0, name: 1, price: 1 } } ],
        total: [ { $count: "n" } ]
    } },
    { $project: { page: 1, total: { $first: "$total.n" } } }
]);                                                       // page: Laptop, Monitor, Webcam ; total: 6


/* ============================================================
   5. $bucket and $bucketAuto  (histograms)
   ============================================================ */

db.employees.aggregate([
    { $bucket: { groupBy: "$salary", boundaries: [40000, 60000, 80000, 100000], default: "other",
                 output: { n: { $sum: 1 }, names: { $push: "$name" } } } }
]);                                                       // 40000: 3 (Neha, Anjali, Meera), 60000: 7, 80000: 2 (Rahul, Sneha)

db.orders.aggregate([
    { $bucketAuto: { groupBy: "$totalAmount", buckets: 3, output: { n: { $sum: 1 }, avg: { $avg: "$totalAmount" } } } }
]);                                                       // 3 buckets with ~equal counts, boundaries chosen by the server

// $bucket with a computed groupBy: months of tenure
db.employees.aggregate([
    { $bucket: { groupBy: { $year: "$hireDate" }, boundaries: [2020, 2022, 2024, 2026], output: { n: { $sum: 1 } } } }
]);                                                       // 2020-21: 3, 2022-23: 6, 2024-25: 3


/* ============================================================
   6. $replaceRoot / $replaceWith  (promote a sub-document)
   ============================================================ */

// After a $lookup, make the customer the top-level document but keep the order id and amount
db.orders.aggregate([
    { $match: { _id: 1001 } },
    { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "c" } },
    { $replaceWith: { $mergeObjects: [ { $first: "$c" }, { orderId: "$_id", amount: "$totalAmount" } ] } }
]);                                                       // { _id: 1, name: 'Aarav Sharma', ..., orderId: 1001, amount: 75000 }

// Promote each address to be the document
db.employees.aggregate([ { $match: { departmentId: 4 } }, { $replaceRoot: { newRoot: "$address" } } ]);

// $replaceRoot fails on a missing field -> guard with $ifNull
db.employees.aggregate([ { $match: { _id: 112 } }, { $replaceWith: { $ifNull: ["$missingField", { note: "no such field" }] } } ]);


/* ============================================================
   7. $sample and a "top-N per group with the rest bucketed"
   ============================================================ */

db.customers.aggregate([ { $sample: { size: 3 } }, { $project: { _id: 0, name: 1 } } ]);

// Top 2 products by revenue + "Other" (classic dashboard chart shape)
db.orders.aggregate([
    { $unwind: "$items" },
    { $group: { _id: "$items.productId", revenue: { $sum: { $multiply: ["$items.qty", "$items.unitPrice"] } } } },
    { $setWindowFields: { sortBy: { revenue: -1 }, output: { r: { $rank: {} } } } },
    { $group: { _id: { $cond: [ { $lte: ["$r", 2] }, "$_id", "Other" ] }, revenue: { $sum: "$revenue" } } },
    { $sort: { revenue: -1 } }
]);                                                       // 1 (Laptop) 300000, 6 (Monitor) 175000, Other 143000

/* ------------------------------------------------------------
   DONE. Next: 03_Practice_Array_Expressions_Out_Merge_Views.js
   ------------------------------------------------------------ */
