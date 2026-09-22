/* ============================================================
   LEVEL 09 - AGGREGATION ADVANCED  |  01_Practice_Unwind_Lookup.js
   ------------------------------------------------------------
   Topics : $unwind (preserveNullAndEmptyArrays, includeArrayIndex),
            $lookup equality / pipeline / self, LEFT vs INNER vs
            anti-join, $graphLookup (recursive), $unionWith,
            multi-collection reports

   HOW TO PRACTICE: block by block, predict first. Read-only.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. $unwind - one document per array element
   ============================================================ */

db.orders.aggregate([ { $match: { _id: 1008 } }, { $unwind: "$items" } ]);                       // 3 documents, items is now an object
db.orders.aggregate([ { $unwind: "$items" }, { $count: "orderLines" } ]);                          // 26 (= OrderDetails rows in SQL)

// includeArrayIndex keeps the position
db.orders.aggregate([ { $match: { _id: 1008 } }, { $unwind: { path: "$items", includeArrayIndex: "lineNo" } }, { $project: { _id: 0, lineNo: 1, "items.productId": 1 } } ]);

// Missing / empty arrays DROP the document ...
db.employees.aggregate([ { $unwind: "$skills" }, { $count: "rows" } ]);                            // 25 (Anjali [] and Meera missing are gone)
// ... unless you preserve them (LEFT JOIN feeling)
db.employees.aggregate([ { $unwind: { path: "$skills", preserveNullAndEmptyArrays: true } }, { $count: "rows" } ]);   // 27
db.employees.aggregate([ { $unwind: { path: "$skills", preserveNullAndEmptyArrays: true } }, { $match: { skills: { $exists: false } } }, { $project: { _id: 0, name: 1 } } ]);   // Anjali, Meera


/* ============================================================
   2. $unwind + $group: counting array elements
   ============================================================ */

// Skill frequency (most common skills)
db.employees.aggregate([ { $unwind: "$skills" }, { $sortByCount: "$skills" }, { $limit: 5 } ]);   // Excel 3, MongoDB 3, SQL 3, Sales 3, ...

// Units sold and revenue per product (from the embedded order lines)
db.orders.aggregate([
    { $match: { status: { $ne: "Cancelled" } } },
    { $unwind: "$items" },
    { $group: { _id: "$items.productId", units: { $sum: "$items.qty" }, revenue: { $sum: { $multiply: ["$items.qty", "$items.unitPrice"] } } } },
    { $sort: { revenue: -1 } }
]);                                                       // 1: 4 units 300000, 6: 7 units 175000, 5: 3 units 45000 ... 8 (Pen): 150 units 1500

// Distinct skills count (the right way, compare Level 08 Q7)
db.employees.aggregate([ { $unwind: "$skills" }, { $group: { _id: "$skills" } }, { $count: "distinctSkills" } ]);   // 16

// Number of lines per order WITHOUT unwind ($size) vs WITH unwind (+ $first to keep parent fields)
db.orders.aggregate([ { $project: { lines: { $size: "$items" } } }, { $sort: { lines: -1, _id: 1 } }, { $limit: 3 } ]);
db.orders.aggregate([ { $unwind: "$items" }, { $group: { _id: "$_id", lines: { $sum: 1 }, total: { $first: "$totalAmount" } } }, { $sort: { lines: -1, _id: 1 } }, { $limit: 3 } ]);
// $first: "$totalAmount" - NOT $sum, otherwise the parent value is counted once per line


/* ============================================================
   3. $lookup - the JOIN  (equality form)
   ============================================================ */

// orders -> customers  (localField customerId = foreignField _id)
db.orders.aggregate([
    { $match: { _id: { $in: [1001, 1019] } } },
    { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "customer" } }
]);                                                       // customer is an ARRAY with 1 document

// Flatten it: $unwind, or $first / $arrayElemAt
db.orders.aggregate([
    { $match: { _id: { $in: [1001, 1019] } } },
    { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "customer" } },
    { $unwind: "$customer" },
    { $project: { _id: 1, totalAmount: 1, customerName: "$customer.name", city: "$customer.city" } }
]);
db.orders.aggregate([
    { $match: { _id: 1001 } },
    { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "customer" } },
    { $set: { customer: { $first: "$customer" } } },
    { $project: { _id: 1, "customer.name": 1 } }
]);

// LEFT JOIN vs INNER JOIN: employees -> departments (Anjali has departmentId null)
db.employees.aggregate([
    { $lookup: { from: "departments", localField: "departmentId", foreignField: "_id", as: "dept" } },
    { $project: { _id: 0, name: 1, dept: "$dept.name" } }
]);                                                       // Anjali: dept: [] (empty array = no match, document kept = LEFT JOIN)
db.employees.aggregate([
    { $lookup: { from: "departments", localField: "departmentId", foreignField: "_id", as: "dept" } },
    { $unwind: "$dept" },                                 // drops Anjali = INNER JOIN
    { $count: "withDepartment" }
]);                                                       // 11
db.employees.aggregate([
    { $lookup: { from: "departments", localField: "departmentId", foreignField: "_id", as: "dept" } },
    { $unwind: { path: "$dept", preserveNullAndEmptyArrays: true } },
    { $project: { _id: 0, name: 1, department: { $ifNull: ["$dept.name", "(none)"] } } }
]);                                                       // 12 rows, Anjali -> (none)   = LEFT JOIN + ISNULL


/* ============================================================
   4. ONE-TO-MANY and ANTI-JOIN (NOT EXISTS)
   ============================================================ */

// departments -> employees: headcount per department INCLUDING zero (Legal)
db.departments.aggregate([
    { $lookup: { from: "employees", localField: "_id", foreignField: "departmentId", as: "staff" } },
    { $project: { _id: 0, name: 1, headcount: { $size: "$staff" }, payroll: { $sum: "$staff.salary" } } },
    { $sort: { headcount: -1 } }
]);                                                       // Legal 0 / 0

// Departments with NO employees (anti-join)
db.departments.aggregate([
    { $lookup: { from: "employees", localField: "_id", foreignField: "departmentId", as: "staff" } },
    { $match: { staff: { $size: 0 } } },
    { $project: { _id: 0, name: 1 } }
]);                                                       // Legal

// Customers with no orders
db.customers.aggregate([
    { $lookup: { from: "orders", localField: "_id", foreignField: "customerId", as: "orders" } },
    { $match: { orders: [] } },
    { $project: { _id: 0, name: 1 } }
]);                                                       // Hina Khan

// Products never ordered: foreignField can be a field INSIDE an array ("items.productId")
db.products.aggregate([
    { $lookup: { from: "orders", localField: "_id", foreignField: "items.productId", as: "orders" } },
    { $match: { orders: { $size: 0 } } },
    { $project: { _id: 0, name: 1 } }
]);                                                       // Webcam


/* ============================================================
   5. $lookup WITH A PIPELINE (correlated subquery, extra conditions)
   ============================================================ */

// For each customer: only their COMPLETED orders, projected small, newest first, max 2
db.customers.aggregate([
    { $lookup: {
        from: "orders",
        let: { cid: "$_id" },                             // outer value -> variable
        pipeline: [
            { $match: { $expr: { $and: [ { $eq: ["$customerId", "$$cid"] }, { $eq: ["$status", "Completed"] } ] } } },
            { $sort: { orderDate: -1 } },
            { $limit: 2 },
            { $project: { _id: 1, orderDate: 1, totalAmount: 1 } }
        ],
        as: "lastCompleted"
    } },
    { $project: { _id: 0, name: 1, lastCompleted: 1 } }
]);

// 5.0+: localField/foreignField AND a pipeline together (join key + filter)
db.customers.aggregate([
    { $lookup: { from: "orders", localField: "_id", foreignField: "customerId",
                 pipeline: [ { $match: { status: "Pending" } }, { $project: { _id: 1, totalAmount: 1 } } ], as: "pendingOrders" } },
    { $match: { pendingOrders: { $ne: [] } } },
    { $project: { _id: 0, name: 1, pendingOrders: 1 } }
]);                                                       // Aarav (1015), Chirag (1017)

// Uncorrelated lookup (no let / no match on the outer doc) = attach the same list to every document
db.departments.aggregate([
    { $match: { _id: 1 } },
    { $lookup: { from: "products", pipeline: [ { $match: { category: "Electronics" } }, { $project: { _id: 0, name: 1 } } ], as: "catalog" } }
]);


/* ============================================================
   6. SELF JOIN: employee -> manager
   ============================================================ */

db.employees.aggregate([
    { $lookup: { from: "employees", localField: "managerId", foreignField: "_id", as: "mgr" } },
    { $project: { _id: 0, name: 1, manager: { $ifNull: [ { $first: "$mgr.name" }, "(none)" ] } } },
    { $sort: { manager: 1, name: 1 } }
]);

// Employees earning more than their manager (0 here - managers earn more in this data)
db.employees.aggregate([
    { $lookup: { from: "employees", localField: "managerId", foreignField: "_id", as: "mgr" } },
    { $unwind: "$mgr" },
    { $match: { $expr: { $gt: ["$salary", "$mgr.salary"] } } },
    { $count: "earnMoreThanManager" }
]);                                                       // [] (no document -> nothing printed)


/* ============================================================
   7. $graphLookup - recursive (org chart)
   ============================================================ */

// Everyone under Rahul (101), directly or indirectly. connectFromField _id -> connectToField managerId
db.employees.aggregate([
    { $match: { _id: 101 } },
    { $graphLookup: { from: "employees", startWith: "$_id", connectFromField: "_id", connectToField: "managerId", as: "reports", depthField: "level" } },
    { $project: { _id: 0, name: 1, reports: { $map: { input: "$reports", as: "r", in: { name: "$$r.name", level: "$$r.level" } } } } }
]);                                                       // Amit (0), Pooja (0)

// The chain of managers ABOVE an employee: connectFromField managerId -> connectToField _id
db.employees.aggregate([
    { $match: { _id: 111 } },                             // Deepak -> Sneha
    { $graphLookup: { from: "employees", startWith: "$managerId", connectFromField: "managerId", connectToField: "_id", as: "chain", depthField: "level" } },
    { $project: { _id: 0, name: 1, "chain.name": 1, "chain.level": 1 } }
]);

// Whole company: every employee with the size of their subtree
db.employees.aggregate([
    { $graphLookup: { from: "employees", startWith: "$_id", connectFromField: "_id", connectToField: "managerId", as: "subtree", maxDepth: 5 } },
    { $project: { _id: 0, name: 1, teamSize: { $size: "$subtree" } } },
    { $match: { teamSize: { $gt: 0 } } },
    { $sort: { teamSize: -1, name: 1 } }
]);                                                       // Rahul 2, Priya 2, Karan 1, Sneha 1


/* ============================================================
   8. A MULTI-COLLECTION REPORT  (orders + customers + employees + products)
   ============================================================ */

db.orders.aggregate([
    { $match: { status: "Completed" } },
    { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "c" } },
    { $lookup: { from: "employees", localField: "employeeId", foreignField: "_id", as: "e" } },
    { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "p" } },
    { $project: {
        _id: 1, orderDate: 1,
        customer: { $first: "$c.name" },
        salesperson: { $ifNull: [ { $first: "$e.name" }, "(online)" ] },
        product: { $first: "$p.name" },
        category: { $first: "$p.category" },
        qty: "$items.qty",
        lineTotal: { $multiply: ["$items.qty", "$items.unitPrice"] }
    } },
    { $sort: { orderDate: 1, _id: 1 } },
    { $limit: 5 }
]);

// Revenue per CATEGORY (needs the join through the array)
db.orders.aggregate([
    { $match: { status: "Completed" } },
    { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "p" } },
    { $group: { _id: { $first: "$p.category" }, revenue: { $sum: { $multiply: ["$items.qty", "$items.unitPrice"] } } } },
    { $sort: { revenue: -1 } }
]);                                                       // Electronics 507500, Furniture 65000, Stationery 1500


/* ============================================================
   9. $unionWith  (UNION ALL)
   ============================================================ */

db.employees.aggregate([
    { $project: { _id: 0, name: 1, kind: "employee" } },
    { $unionWith: { coll: "customers", pipeline: [ { $project: { _id: 0, name: 1, kind: "customer" } } ] } },
    { $sort: { name: 1 } },
    { $limit: 5 }
]);
db.employees.aggregate([ { $unionWith: "customers" }, { $count: "people" } ]);   // 20

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Window_Facet_Bucket.js
   ------------------------------------------------------------ */
