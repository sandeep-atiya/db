/* ============================================================
   LEVEL 09 - AGGREGATION ADVANCED  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Read-only except Q14/Q15 (l09_ex_* collections, dropped).
   ============================================================ */

use("companyDB");

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Every order with the customer's name and city (id, customerName, city).
   Q2.  Every employee with the department NAME; Anjali must show "(none)".
   Q3.  Department names with their headcount, INCLUDING Legal (0).
   Q4.  Units sold per product NAME, best seller first (Cancelled orders excluded).
   Q5.  Customers who never ordered (name).
   Q6.  Each employee with the name of their manager ("(none)" if no manager).
   Q7.  All people reporting (directly or indirectly) to Priya (103): names only.
   Q8.  Rank all orders by totalAmount (highest = 1) with $rank; show id, amount, rank.
   Q9.  Running total of Completed revenue per customer ordered by date
        (customerId, orderId, totalAmount, runningTotal) - customers 1 and 2 only.
   Q10. For each order, the previous order's totalAmount of the SAME customer (LAG).
   Q11. Histogram of product prices: [0, 1000, 10000, 100000] with count and names.
   Q12. In ONE query ($facet): total number of employees, average salary, and the
        3 highest-paid names.
   Q13. PIVOT: one document per department with columns "active" and "inactive"
        (counts of employees).
   Q14. Materialise "revenue per category" into l09_ex_category_stats with $merge,
        run it twice, and show the collection.
   Q15. Create a view vw_l09_ex_employee_dept that joins employees with department
        name and shows name, salary, department. Query the view for department "IT".
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
db.orders.aggregate([
    { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "c" } },
    { $project: { customerName: { $first: "$c.name" }, city: { $first: "$c.city" } } },
    { $limit: 3 }
]);

// Q2
db.employees.aggregate([
    { $lookup: { from: "departments", localField: "departmentId", foreignField: "_id", as: "d" } },
    { $project: { _id: 0, name: 1, department: { $ifNull: [ { $first: "$d.name" }, "(none)" ] } } }
]);

// Q3
db.departments.aggregate([
    { $lookup: { from: "employees", localField: "_id", foreignField: "departmentId", as: "staff" } },
    { $project: { _id: 0, name: 1, headcount: { $size: "$staff" } } },
    { $sort: { headcount: -1, name: 1 } }
]);                                                       // IT 3, Sales 3, Finance 2, Marketing 2, HR 1, Legal 0

// Q4
db.orders.aggregate([
    { $match: { status: { $ne: "Cancelled" } } },
    { $unwind: "$items" },
    { $group: { _id: "$items.productId", units: { $sum: "$items.qty" } } },
    { $lookup: { from: "products", localField: "_id", foreignField: "_id", as: "p" } },
    { $project: { _id: 0, product: { $first: "$p.name" }, units: 1 } },
    { $sort: { units: -1 } }
]);                                                       // Pen 150, Notebook 20, Mouse 14, Monitor 7, ...

// Q5
db.customers.aggregate([
    { $lookup: { from: "orders", localField: "_id", foreignField: "customerId", as: "o" } },
    { $match: { o: { $size: 0 } } },
    { $project: { _id: 0, name: 1 } }
]);                                                       // Hina Khan

// Q6
db.employees.aggregate([
    { $lookup: { from: "employees", localField: "managerId", foreignField: "_id", as: "m" } },
    { $project: { _id: 0, name: 1, manager: { $ifNull: [ { $first: "$m.name" }, "(none)" ] } } }
]);

// Q7
db.employees.aggregate([
    { $match: { _id: 103 } },
    { $graphLookup: { from: "employees", startWith: "$_id", connectFromField: "_id", connectToField: "managerId", as: "team" } },
    { $project: { _id: 0, team: "$team.name" } }
]);                                                       // Neha, Vikram

// Q8
db.orders.aggregate([
    { $setWindowFields: { sortBy: { totalAmount: -1 }, output: { rank: { $rank: {} } } } },
    { $project: { totalAmount: 1, rank: 1 } },
    { $limit: 4 }
]);                                                       // 1014 1, 1008 2, 1001 3, 1018 3

// Q9
db.orders.aggregate([
    { $match: { status: "Completed", customerId: { $in: [1, 2] } } },
    { $setWindowFields: { partitionBy: "$customerId", sortBy: { orderDate: 1 }, output: { runningTotal: { $sum: "$totalAmount", window: { documents: ["unbounded", "current"] } } } } },
    { $project: { customerId: 1, totalAmount: 1, runningTotal: 1 } }
]);                                                       // c1: 75000, 90000, 96000 ; c2: 10000, 16000, 46000, 48500

// Q10
db.orders.aggregate([
    { $setWindowFields: { partitionBy: "$customerId", sortBy: { orderDate: 1 }, output: { prevAmount: { $shift: { output: "$totalAmount", by: -1, default: null } } } } },
    { $sort: { customerId: 1, orderDate: 1 } },              // sort BEFORE projecting orderDate away
    { $project: { customerId: 1, totalAmount: 1, prevAmount: 1 } },
    { $limit: 5 }
]);                                                       // c1: 1001 null, 1004 75000, 1009 15000, 1015 6000 ; c2: 1002 null

// Q11
db.products.aggregate([
    { $bucket: { groupBy: "$price", boundaries: [0, 1000, 10000, 100000], output: { n: { $sum: 1 }, names: { $push: "$name" } } } }
]);                                                       // 0: 2 (Notebook, Pen), 1000: 5, 10000: 4

// Q12
db.employees.aggregate([
    { $facet: {
        count: [ { $count: "n" } ],
        avg:   [ { $group: { _id: null, avgSalary: { $avg: "$salary" } } } ],
        top3:  [ { $sort: { salary: -1 } }, { $limit: 3 }, { $project: { _id: 0, name: 1 } } ]
    } },
    { $project: { count: { $first: "$count.n" }, avgSalary: { $round: [ { $first: "$avg.avgSalary" }, 0 ] }, top3: "$top3.name" } }
]);                                                       // 12, 67083, [ Sneha, Rahul, Priya ]

// Q13
db.employees.aggregate([
    { $group: { _id: { d: "$departmentId", a: { $cond: ["$active", "active", "inactive"] } }, n: { $sum: 1 } } },
    { $group: { _id: "$_id.d", kv: { $push: { k: "$_id.a", v: "$n" } } } },
    { $replaceWith: { $mergeObjects: [ { departmentId: "$_id", active: 0, inactive: 0 }, { $arrayToObject: "$kv" } ] } },
    { $sort: { departmentId: 1 } }
]);                                                       // 5: active 1, inactive 1 ; others inactive 0

// Q14
db.l09_ex_category_stats.drop();
const q14 = [
    { $match: { status: "Completed" } },
    { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "p" } },
    { $group: { _id: { $first: "$p.category" }, revenue: { $sum: { $multiply: ["$items.qty", "$items.unitPrice"] } } } },
    { $merge: { into: "l09_ex_category_stats", on: "_id", whenMatched: "replace", whenNotMatched: "insert" } }
];
db.orders.aggregate(q14);
db.orders.aggregate(q14);                                 // idempotent: still 3 documents
db.l09_ex_category_stats.find().sort({ revenue: -1 });   // Electronics 507500, Furniture 65000, Stationery 1500

// Q15
db.vw_l09_ex_employee_dept.drop();
db.createView("vw_l09_ex_employee_dept", "employees", [
    { $lookup: { from: "departments", localField: "departmentId", foreignField: "_id", as: "d" } },
    { $project: { _id: 0, name: 1, salary: 1, department: { $first: "$d.name" } } }
]);
db.vw_l09_ex_employee_dept.find({ department: "IT" });    // Rahul, Amit, Pooja

db.l09_ex_category_stats.drop(); db.vw_l09_ex_employee_dept.drop();
