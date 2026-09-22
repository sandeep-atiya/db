/* ============================================================
   INTERVIEW PREP  |  Top_Query_Patterns.js
   ------------------------------------------------------------
   The 30 query patterns that come up again and again in MongoDB
   interviews (the same list as the SQL Server course, translated),
   all runnable on companyDB.
   Practice: read the title, WRITE IT YOURSELF, then compare.
   Every pattern is independent - run any block alone.
   Temporary collections are prefixed ip_ and dropped at the end.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. Nth HIGHEST SALARY  (3 ways)   -> 2nd highest = 85000 (Rahul)
   ============================================================ */
// 1a. DENSE_RANK with $setWindowFields (best: handles ties, returns names)
const N = 2;
db.employees.aggregate([
    { $setWindowFields: { sortBy: { salary: -1 }, output: { rnk: { $denseRank: {} } } } },
    { $match: { rnk: N } },
    { $project: { _id: 0, name: 1, salary: 1 } }
]);
// 1b. Distinct salaries, sort, skip (OFFSET/FETCH style)
db.employees.aggregate([ { $group: { _id: "$salary" } }, { $sort: { _id: -1 } }, { $skip: N - 1 }, { $limit: 1 } ]);   // 85000
// 1c. Classic: max salary below the max
db.employees.aggregate([
    { $group: { _id: null, max: { $max: "$salary" }, all: { $push: "$salary" } } },
    { $project: { _id: 0, secondHighest: { $max: { $filter: { input: "$all", as: "s", cond: { $lt: ["$$s", "$max"] } } } } } }
]);   // 85000


/* ============================================================
   2. FIND DUPLICATES  /  DELETE DUPLICATES (keep one)
   ============================================================ */
db.ip_customers.drop();
db.customers.aggregate([ { $project: { name: 1, city: 1 } }, { $out: "ip_customers" } ]);
db.ip_customers.insertMany([ { _id: 9, name: "Aarav Sharma", city: "Delhi" }, { _id: 10, name: "Aarav Sharma", city: "Delhi" }, { _id: 11, name: "Divya Nair", city: "Pune" } ]);
// 2a. Find duplicates by name + city
db.ip_customers.aggregate([
    { $group: { _id: { name: "$name", city: "$city" }, n: { $sum: 1 }, ids: { $push: "$_id" } } },
    { $match: { n: { $gt: 1 } } }
]);   // Aarav Sharma (3), Divya Nair (2)
// 2b. Delete duplicates, keep the lowest _id
const dupIds = db.ip_customers.aggregate([
    { $sort: { _id: 1 } },
    { $group: { _id: { name: "$name", city: "$city" }, ids: { $push: "$_id" } } },
    { $project: { extra: { $slice: ["$ids", 1, { $size: "$ids" }] } } },      // everything except the first
    { $unwind: "$extra" }
]).map(d => d.extra).toArray();
db.ip_customers.deleteMany({ _id: { $in: dupIds } });      // 3 deleted
db.ip_customers.countDocuments();                          // 8


/* ============================================================
   3. TOP-N PER GROUP  (highest paid employee in each department)
   ============================================================ */
db.employees.aggregate([
    { $sort: { salary: -1 } },
    { $group: { _id: "$departmentId", name: { $first: "$name" }, salary: { $first: "$salary" } } },
    { $sort: { _id: 1 } }
]);
// 3b. top 2 orders per customer with $topN
db.orders.aggregate([ { $group: { _id: "$customerId", top2: { $topN: { n: 2, sortBy: { totalAmount: -1 }, output: { order: "$_id", amount: "$totalAmount" } } } } }, { $sort: { _id: 1 } } ]);
// 3c. rank within group (ties returned too with $rank)
db.employees.aggregate([ { $setWindowFields: { partitionBy: "$departmentId", sortBy: { salary: -1 }, output: { r: { $rank: {} } } } }, { $match: { r: 1 } }, { $project: { _id: 0, departmentId: 1, name: 1 } } ]);


/* ============================================================
   4. EMPLOYEES EARNING MORE THAN THEIR MANAGER   (SELF JOIN)
   ============================================================ */
db.employees.aggregate([
    { $lookup: { from: "employees", localField: "managerId", foreignField: "_id", as: "m" } },
    { $unwind: "$m" },
    { $match: { $expr: { $gt: ["$salary", "$m.salary"] } } },
    { $project: { _id: 0, name: 1, salary: 1, manager: "$m.name", managerSalary: "$m.salary" } }
]);   // [] in this data (managers earn more)
// Employee + manager list, managers on top
db.employees.aggregate([
    { $lookup: { from: "employees", localField: "managerId", foreignField: "_id", as: "m" } },
    { $project: { _id: 0, name: 1, manager: { $ifNull: [ { $first: "$m.name" }, "(none)" ] }, isTop: { $eq: ["$managerId", null] } } },
    { $sort: { isTop: -1, name: 1 } }
]);


/* ============================================================
   5. DEPARTMENT-WISE MAX SALARY WITH EMPLOYEE NAME
   ============================================================ */
db.employees.aggregate([
    { $group: { _id: "$departmentId", maxSal: { $max: "$salary" }, people: { $push: { name: "$name", salary: "$salary" } } } },
    { $project: { top: { $filter: { input: "$people", as: "p", cond: { $eq: ["$$p.salary", "$maxSal"] } } } } },   // ties kept
    { $sort: { _id: 1 } }
]);


/* ============================================================
   6. CUSTOMERS WITH NO ORDERS  (3 ways)  -> Hina Khan
   ============================================================ */
db.customers.aggregate([ { $lookup: { from: "orders", localField: "_id", foreignField: "customerId", as: "o" } }, { $match: { o: [] } }, { $project: { _id: 0, name: 1 } } ]);
db.customers.find({ _id: { $nin: db.orders.distinct("customerId") } }, { _id: 0, name: 1 });                       // NOT IN with a list from distinct
db.customers.aggregate([ { $lookup: { from: "orders", let: { c: "$_id" }, pipeline: [ { $match: { $expr: { $eq: ["$customerId", "$$c"] } } }, { $limit: 1 } ], as: "o" } }, { $match: { o: { $size: 0 } } }, { $project: { _id: 0, name: 1 } } ]);   // NOT EXISTS (stops at first match)


/* ============================================================
   7. COUNT PER GROUP INCLUDING ZERO  (departments with 0 employees)
   ============================================================ */
db.departments.aggregate([
    { $lookup: { from: "employees", localField: "_id", foreignField: "departmentId", as: "e" } },
    { $project: { _id: 0, name: 1, employees: { $size: "$e" } } },
    { $sort: { employees: -1 } }
]);   // Legal = 0


/* ============================================================
   8. RUNNING TOTAL  and  MONTH-OVER-MONTH GROWTH
   ============================================================ */
db.orders.aggregate([
    { $match: { status: "Completed" } },
    { $setWindowFields: { sortBy: { orderDate: 1 }, output: { running: { $sum: "$totalAmount", window: { documents: ["unbounded", "current"] } } } } },
    { $project: { orderDate: 1, totalAmount: 1, running: 1 } }, { $limit: 5 }
]);
db.orders.aggregate([
    { $match: { status: "Completed" } },
    { $group: { _id: { $dateTrunc: { date: "$orderDate", unit: "month" } }, revenue: { $sum: "$totalAmount" } } },
    { $setWindowFields: { sortBy: { _id: 1 }, output: { prev: { $shift: { output: "$revenue", by: -1 } } } } },
    { $project: { _id: 0, month: { $dateToString: { format: "%Y-%m", date: "$_id" } }, revenue: 1, prev: 1,
                  growthPct: { $cond: [ { $or: [ { $eq: ["$prev", null] }, { $eq: ["$prev", 0] } ] }, null, { $round: [ { $multiply: [ { $divide: [ { $subtract: ["$revenue", "$prev"] }, "$prev" ] }, 100 ] }, 1 ] } ] } } }
]);


/* ============================================================
   9. RANK vs DENSE_RANK vs ROW_NUMBER  (Amit & Pooja tie at 65000)
   ============================================================ */
db.employees.aggregate([
    { $setWindowFields: { sortBy: { salary: -1 }, output: { rowNum: { $documentNumber: {} }, rnk: { $rank: {} }, dense: { $denseRank: {} } } } },
    { $project: { _id: 0, name: 1, salary: 1, rowNum: 1, rnk: 1, dense: 1 } }
]);   // Amit 6/6/6, Pooja 7/6/6, Vikram 8/8/7


/* ============================================================
   10. GAPS IN A SEQUENCE  (missing order ids)  and  ISLANDS (streaks)
   ============================================================ */
db.ip_orders.drop();
db.orders.aggregate([ { $match: { _id: { $nin: [1004, 1005, 1011] } } }, { $project: { _id: 1 } }, { $out: "ip_orders" } ]);
// 10a. Gaps with LEAD ($shift)
db.ip_orders.aggregate([
    { $setWindowFields: { sortBy: { _id: 1 }, output: { next: { $shift: { output: "$_id", by: 1 } } } } },
    { $match: { $expr: { $gt: [ { $subtract: ["$next", "$_id"] }, 1 ] } } },
    { $project: { _id: 0, gapStart: { $add: ["$_id", 1] }, gapEnd: { $subtract: ["$next", 1] } } }
]);   // 1004-1005, 1011-1011
// 10b. Islands: consecutive-day login streaks (row-number difference trick)
db.ip_logins.drop();
db.ip_logins.insertMany([
    { user: "amit", d: ISODate("2025-03-01") }, { user: "amit", d: ISODate("2025-03-02") }, { user: "amit", d: ISODate("2025-03-03") }, { user: "amit", d: ISODate("2025-03-06") }, { user: "amit", d: ISODate("2025-03-07") },
    { user: "neha", d: ISODate("2025-03-01") }, { user: "neha", d: ISODate("2025-03-03") }, { user: "neha", d: ISODate("2025-03-04") }, { user: "neha", d: ISODate("2025-03-05") }
]);
db.ip_logins.aggregate([
    { $setWindowFields: { partitionBy: "$user", sortBy: { d: 1 }, output: { rn: { $documentNumber: {} } } } },
    { $set: { grp: { $dateSubtract: { startDate: "$d", unit: "day", amount: "$rn" } } } },     // same value for a run of consecutive days
    { $group: { _id: { user: "$user", grp: "$grp" }, start: { $min: "$d" }, end: { $max: "$d" }, days: { $sum: 1 } } },
    { $project: { _id: 0, user: "$_id.user", start: 1, end: 1, days: 1 } },
    { $sort: { user: 1, start: 1 } }
]);   // amit: 3 days + 2 days ; neha: 1 day + 3 days


/* ============================================================
   11. PIVOT: order counts per status per customer  ($arrayToObject and $cond)
   ============================================================ */
db.orders.aggregate([
    { $group: { _id: { c: "$customerId", s: "$status" }, n: { $sum: 1 } } },
    { $group: { _id: "$_id.c", kv: { $push: { k: "$_id.s", v: "$n" } } } },
    { $replaceWith: { $mergeObjects: [ { customerId: "$_id", Completed: 0, Pending: 0, Cancelled: 0 }, { $arrayToObject: "$kv" } ] } },
    { $sort: { customerId: 1 } }
]);
db.orders.aggregate([ { $group: { _id: "$customerId",
    Completed: { $sum: { $cond: [ { $eq: ["$status", "Completed"] }, 1, 0 ] } },
    Pending:   { $sum: { $cond: [ { $eq: ["$status", "Pending"] }, 1, 0 ] } },
    Cancelled: { $sum: { $cond: [ { $eq: ["$status", "Cancelled"] }, 1, 0 ] } } } }, { $sort: { _id: 1 } } ]);   // fixed-column version


/* ============================================================
   12. STRING AGGREGATION  (employees per department, comma separated)
   ============================================================ */
db.departments.aggregate([
    { $lookup: { from: "employees", localField: "_id", foreignField: "departmentId", pipeline: [ { $sort: { name: 1 } } ], as: "e" } },
    { $project: { _id: 0, name: 1, members: { $reduce: { input: "$e.name", initialValue: "", in: { $concat: [ "$$value", { $cond: [ { $eq: ["$$value", ""] }, "", ", " ] }, "$$this" ] } } } } }
]);


/* ============================================================
   13. HIERARCHY  (org chart with level and path)
   ============================================================ */
db.employees.aggregate([
    { $match: { managerId: null } },
    { $graphLookup: { from: "employees", startWith: "$_id", connectFromField: "_id", connectToField: "managerId", as: "reports", depthField: "lvl" } },
    { $project: { _id: 0, head: "$name", reports: { $map: { input: { $sortArray: { input: "$reports", sortBy: { lvl: 1, name: 1 } } }, as: "r", in: { $concat: [ "$$r.name", " (level ", { $toString: { $add: ["$$r.lvl", 1] } }, ")" ] } } } } },
    { $sort: { head: 1 } }
]);
// Path of one employee up to the top
db.employees.aggregate([ { $match: { _id: 111 } }, { $graphLookup: { from: "employees", startWith: "$managerId", connectFromField: "managerId", connectToField: "_id", as: "chain", depthField: "d" } },
    { $project: { _id: 0, path: { $reduce: { input: { $sortArray: { input: "$chain", sortBy: { d: -1 } } }, initialValue: "", in: { $concat: ["$$value", "$$this.name", " > "] } } } } },
    { $set: { path: { $concat: ["$path", "Deepak"] } } } ]);   // Sneha > Deepak


/* ============================================================
   14. FIRST AND LAST ORDER PER CUSTOMER  (one row per customer)
   ============================================================ */
db.orders.aggregate([
    { $sort: { orderDate: 1 } },
    { $group: { _id: "$customerId", firstOrder: { $first: "$_id" }, firstDate: { $first: "$orderDate" }, lastOrder: { $last: "$_id" }, orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" } } },
    { $sort: { revenue: -1 } }
]);


/* ============================================================
   15. PERCENT OF TOTAL  (revenue share per category)
   ============================================================ */
db.orders.aggregate([
    { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "p" } },
    { $group: { _id: { $first: "$p.category" }, revenue: { $sum: { $multiply: ["$items.qty", "$items.unitPrice"] } } } },
    { $setWindowFields: { output: { total: { $sum: "$revenue" } } } },      // window over everything = grand total on every row
    { $project: { _id: 0, category: "$_id", revenue: 1, pct: { $round: [ { $multiply: [ { $divide: ["$revenue", "$total"] }, 100 ] }, 2 ] } } },
    { $sort: { revenue: -1 } }
]);


/* ============================================================
   16. BEST-SELLING PRODUCT / PRODUCTS NEVER SOLD
   ============================================================ */
db.orders.aggregate([ { $unwind: "$items" }, { $group: { _id: "$items.productId", units: { $sum: "$items.qty" } } }, { $sort: { units: -1 } }, { $limit: 1 },
    { $lookup: { from: "products", localField: "_id", foreignField: "_id", as: "p" } }, { $project: { _id: 0, product: { $first: "$p.name" }, units: 1 } } ]);   // Pen 150
db.products.aggregate([ { $lookup: { from: "orders", localField: "_id", foreignField: "items.productId", as: "o" } }, { $match: { o: [] } }, { $project: { _id: 0, name: 1 } } ]);   // Webcam


/* ============================================================
   17. MEDIAN SALARY
   ============================================================ */
db.employees.aggregate([ { $group: { _id: null, median: { $median: { input: "$salary", method: "approximate" } }, p90: { $percentile: { input: "$salary", p: [0.9], method: "approximate" } } } } ]);   // 7.0+: 65000
db.employees.aggregate([                                                                  // manual: middle element(s) of the sorted list
    { $sort: { salary: 1 } }, { $group: { _id: null, s: { $push: "$salary" } } },
    { $project: { _id: 0, median: { $let: { vars: { n: { $size: "$s" } }, in: { $cond: [ { $eq: [ { $mod: ["$$n", 2] }, 0 ] },
        { $avg: [ { $arrayElemAt: ["$s", { $subtract: [ { $divide: ["$$n", 2] }, 1 ] }] }, { $arrayElemAt: ["$s", { $divide: ["$$n", 2] }] } ] },
        { $arrayElemAt: ["$s", { $floor: { $divide: ["$$n", 2] } }] } ] } } } } }
]);   // 65000


/* ============================================================
   18. ODD / EVEN ROWS
   ============================================================ */
db.employees.aggregate([ { $setWindowFields: { sortBy: { _id: 1 }, output: { rn: { $documentNumber: {} } } } }, { $match: { $expr: { $eq: [ { $mod: ["$rn", 2] }, 1 ] } } }, { $project: { _id: 1, name: 1, rn: 1 } } ]);   // odd


/* ============================================================
   19. SWAP VALUES WITH ONE UPDATE  (pipeline update)
   ============================================================ */
db.ip_swap.drop();
db.ip_swap.insertMany([ { _id: 1, gender: "M" }, { _id: 2, gender: "F" }, { _id: 3, gender: "M" } ]);
db.ip_swap.updateMany({}, [ { $set: { gender: { $switch: { branches: [ { case: { $eq: ["$gender", "M"] }, then: "F" }, { case: { $eq: ["$gender", "F"] }, then: "M" } ], default: "$gender" } } } } ]);
db.ip_swap.find();   // F, M, F


/* ============================================================
   20. COMPARE TWO COLLECTIONS  (rows that differ)
   ============================================================ */
db.ip_products2.drop();
db.products.aggregate([ { $out: "ip_products2" } ]);
db.ip_products2.updateOne({ _id: 2 }, { $set: { price: 999 } });
db.ip_products2.deleteOne({ _id: 11 });
db.products.aggregate([
    { $lookup: { from: "ip_products2", localField: "_id", foreignField: "_id", as: "b" } },
    { $set: { b: { $ifNull: [ { $first: "$b" }, null ] } } },     // $first of an empty array is MISSING, and missing is not $eq null -> $ifNull
    { $match: { $expr: { $or: [ { $eq: ["$b", null] }, { $ne: ["$price", "$b.price"] } ] } } },
    { $project: { _id: 1, name: 1, price: 1, otherPrice: "$b.price", status: { $cond: [ { $eq: ["$b", null] }, "only in original", "differs" ] } } }
]);   // Mouse differs (1000 vs 999), Webcam only in original
// Documents only in the copy: swap the collections in the $lookup (or $unionWith + $group count = 1).


/* ============================================================
   21. EMPLOYEES HIRED IN THE LAST N MONTHS / SAME MONTH AS SOMEONE
   ============================================================ */
const asOf = ISODate("2025-12-31");
db.employees.find({ hireDate: { $gte: new Date(asOf.getTime() - 30 * 30 * 86400000) } }, { _id: 0, name: 1, hireDate: 1 });   // ~last 30 months
db.employees.aggregate([
    { $group: { _id: { $month: "$hireDate" }, people: { $push: "$name" }, n: { $sum: 1 } } },
    { $match: { n: { $gt: 1 } } }, { $sort: { _id: 1 } }
]);   // Jan: Rahul, Meera ; Mar: Amit, Deepak ; May: Sneha, Anjali


/* ============================================================
   22. CONDITIONAL AGGREGATION  (completed vs cancelled per salesperson)
   ============================================================ */
db.orders.aggregate([
    { $group: { _id: "$employeeId", all: { $sum: 1 },
        completed: { $sum: { $cond: [ { $eq: ["$status", "Completed"] }, 1, 0 ] } },
        cancelled: { $sum: { $cond: [ { $eq: ["$status", "Cancelled"] }, 1, 0 ] } },
        completedRevenue: { $sum: { $cond: [ { $eq: ["$status", "Completed"] }, "$totalAmount", 0 ] } } } },
    { $lookup: { from: "employees", localField: "_id", foreignField: "_id", as: "e" } },
    { $project: { _id: 0, salesperson: { $ifNull: [ { $first: "$e.name" }, "(online)" ] }, all: 1, completed: 1, cancelled: 1, completedRevenue: 1 } },
    { $sort: { completedRevenue: -1 } }
]);


/* ============================================================
   23. COMMA LIST -> VALUES  and use them in a filter
   ============================================================ */
const ids = "101,103,106".split(",").map(Number);
db.employees.find({ _id: { $in: ids } }, { _id: 1, name: 1 });
db.employees.aggregate([ { $match: { $expr: { $in: ["$_id", { $map: { input: { $split: ["101,103,106", ","] }, as: "s", in: { $toInt: "$$s" } } }] } } }, { $project: { name: 1 } } ]);   // server-side split


/* ============================================================
   24. THE "NOT IN + NULL" TRAP  (MongoDB version)
   ============================================================ */
// departments with no employees: $nin over distinct departmentId (contains null) still works in MongoDB - no three-valued logic
db.departments.find({ _id: { $nin: db.employees.distinct("departmentId") } }, { name: 1 });   // Legal (null in the list is harmless)
// but $nin with null EXCLUDES documents whose field is null or missing: { departmentId: { $nin: [null] } } = "has a department"
db.employees.find({ departmentId: { $nin: [null] } }).count();                                  // 11


/* ============================================================
   25. LEFT JOIN + FILTER PLACEMENT  (the ON vs WHERE trap)
   ============================================================ */
// Wrong: filtering AFTER the lookup + unwind turns it into an INNER JOIN (customers without Completed orders vanish)
db.customers.aggregate([ { $lookup: { from: "orders", localField: "_id", foreignField: "customerId", as: "o" } }, { $unwind: "$o" }, { $match: { "o.status": "Completed" } }, { $group: { _id: "$name", completed: { $sum: 1 } } }, { $count: "customersReturned" } ]);   // 7
// Right: filter INSIDE the $lookup pipeline (= ON clause) so unmatched customers stay with 0
db.customers.aggregate([ { $lookup: { from: "orders", localField: "_id", foreignField: "customerId", pipeline: [ { $match: { status: "Completed" } } ], as: "o" } }, { $project: { _id: 0, name: 1, completed: { $size: "$o" } } }, { $sort: { completed: -1, name: 1 } } ]);   // 8 rows, Hina 0


/* ============================================================
   26. QUARTILES / NTILE  (top 25 % earners)
   ============================================================ */
db.employees.aggregate([
    { $setWindowFields: { sortBy: { salary: -1 }, output: { rn: { $documentNumber: {} }, n: { $count: {} } } } },
    { $project: { _id: 0, name: 1, salary: 1, quartile: { $ceil: { $divide: [ { $multiply: ["$rn", 4] }, "$n" ] } } } },
    { $match: { quartile: 1 } }
]);   // Sneha, Rahul, Priya
db.employees.aggregate([ { $bucketAuto: { groupBy: "$salary", buckets: 4, output: { names: { $push: "$name" } } } } ]);   // server-chosen boundaries


/* ============================================================
   27. DATE SERIES + LEFT JOIN  (show months with zero orders)
   ============================================================ */
db.orders.aggregate([
    { $group: { _id: { $dateTrunc: { date: "$orderDate", unit: "month" } }, orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" } } },
    { $densify: { field: "_id", range: { step: 1, unit: "month", bounds: [ ISODate("2025-01-01"), ISODate("2026-01-01") ] } } },   // fills Oct-Dec
    { $fill: { output: { orders: { value: 0 }, revenue: { value: 0 } } } },
    { $project: { _id: 0, month: { $dateToString: { format: "%Y-%m", date: "$_id" } }, orders: 1, revenue: 1 } },
    { $sort: { month: 1 } }
]);


/* ============================================================
   28. UPDATE FROM ANOTHER COLLECTION / FROM EMBEDDED DATA
   ============================================================ */
db.ip_orders2.drop();
db.orders.aggregate([ { $out: "ip_orders2" } ]);
db.ip_orders2.updateMany({}, { $set: { totalAmount: 0 } });
// 28a. recompute from the embedded items (pipeline update)
db.ip_orders2.updateMany({}, [ { $set: { totalAmount: { $sum: { $map: { input: "$items", as: "i", in: { $multiply: ["$$i.qty", "$$i.unitPrice"] } } } } } } ]);
db.ip_orders2.aggregate([ { $group: { _id: null, total: { $sum: "$totalAmount" } } } ]);   // 618000 restored
// 28b. from ANOTHER collection: aggregate the source and $merge into the target (SQL UPDATE ... FROM)
db.ip_orders2.updateMany({}, { $set: { customerCity: null } });
db.customers.aggregate([ { $project: { customerCity: "$city" } }, { $lookup: { from: "ip_orders2", localField: "_id", foreignField: "customerId", as: "o" } }, { $unwind: "$o" },
    { $project: { _id: "$o._id", customerCity: 1 } }, { $merge: { into: "ip_orders2", on: "_id", whenMatched: "merge", whenNotMatched: "discard" } } ]);
db.ip_orders2.findOne({ _id: 1001 }, { _id: 1, customerCity: 1 });   // Delhi


/* ============================================================
   29. CUSTOMERS WHO BOUGHT FROM EVERY CATEGORY  (relational division)
   ============================================================ */
db.orders.aggregate([
    { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "p" } },
    { $group: { _id: "$customerId", cats: { $addToSet: { $first: "$p.category" } } } },
    { $lookup: { from: "products", pipeline: [ { $group: { _id: "$category" } } ], as: "all" } },
    { $match: { $expr: { $eq: [ { $size: { $setDifference: ["$all._id", "$cats"] } }, 0 ] } } }
]);   // [] nobody bought all 3 categories
// Relaxed: at least 2 categories
db.orders.aggregate([ { $unwind: "$items" }, { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "p" } },
    { $group: { _id: "$customerId", cats: { $addToSet: { $first: "$p.category" } } } }, { $match: { $expr: { $gte: [ { $size: "$cats" }, 2 ] } } }, { $sort: { _id: 1 } } ]);   // 1, 2, 3, 5, 7


/* ============================================================
   30. PAGINATION  (page 2, 5 rows per page)  - offset and keyset
   ============================================================ */
const pageNo = 2, pageSize = 5;
db.employees.find({}, { _id: 1, name: 1 }).sort({ _id: 1 }).skip((pageNo - 1) * pageSize).limit(pageSize);          // 106..110
db.employees.find({ _id: { $gt: 105 } }, { _id: 1, name: 1 }).sort({ _id: 1 }).limit(pageSize);                      // keyset: same page, no skip
db.employees.aggregate([ { $facet: { items: [ { $sort: { _id: 1 } }, { $skip: 5 }, { $limit: 5 }, { $project: { name: 1 } } ], total: [ { $count: "n" } ] } }, { $project: { items: 1, total: { $first: "$total.n" } } } ]);   // page + total in one round trip


/* ============================================================
   CLEANUP
   ============================================================ */
["ip_customers", "ip_orders", "ip_logins", "ip_swap", "ip_products2", "ip_orders2"].forEach(c => db[c].drop());
