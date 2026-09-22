/* ============================================================
   LEVEL 03 - FIND & QUERY OPERATORS  |  01_Practice_Filtering.js
   ------------------------------------------------------------
   Topics : find / findOne, cursors, equality, comparison operators,
            implicit AND, $in / $nin, $and / $or / $nor / $not,
            ranges, dates, booleans, $exists / $type recap

   HOW TO PRACTICE: block by block, predict the output first.
   Read-only: nothing is modified.
   Projections { _id: 0, name: 1, ... } are used only to keep the
   output short - Level 04 explains them.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. find vs findOne
   ============================================================ */

db.employees.find({}, { _id: 0, name: 1 });            // cursor -> all 12 names
db.employees.findOne({ _id: 103 });                     // ONE document (Priya)
db.employees.findOne({ _id: 999 });                     // null - no error
db.employees.find({ _id: 999 });                        // empty cursor - prints nothing

// find() is lazy: the cursor object, then the data
const cur = db.employees.find({ departmentId: 2 }, { _id: 0, name: 1 });
cur.hasNext();                                          // true
cur.next();                                             // { name: 'Priya' }
cur.next();                                             // { name: 'Neha' }
cur.toArray();                                          // the REST: [ { name: 'Vikram' } ]
cur.hasNext();                                          // false - exhausted

db.employees.find({ departmentId: 1 }).forEach(e => print(e.name + " earns " + e.salary));
db.employees.find({ departmentId: 1 }).map(e => e.salary);                          // prints [ 85000, 65000, 65000 ] - but it is still a CURSOR
db.employees.find({ departmentId: 1 }).map(e => e.salary).toArray();                // a real JS array (needed for $in, .length, etc.)
db.employees.find({ departmentId: 1 }).count();                                     // 3  (deprecated style)
db.employees.countDocuments({ departmentId: 1 });                                   // 3  (preferred)


/* ============================================================
   2. EQUALITY  { field: value }
   ============================================================ */

db.employees.find({ departmentId: 1 }, { _id: 0, name: 1 });            // Rahul, Amit, Pooja
db.employees.find({ name: "Rahul" }, { _id: 0, name: 1, salary: 1 });   // exact, case-sensitive
db.employees.find({ name: "rahul" }).count();                            // 0
db.employees.find({ active: false }, { _id: 0, name: 1 });              // Meera
db.orders.find({ status: "Pending" }, { _id: 1, totalAmount: 1 });       // 1015, 1017

// Equality on a DATE must hit the exact millisecond
db.orders.find({ orderDate: ISODate("2025-01-05") }, { _id: 1 });        // 1001 (stored at midnight UTC)
db.orders.find({ orderDate: ISODate("2025-01-05T10:00:00Z") }).count();  // 0


/* ============================================================
   3. COMPARISON  $gt $gte $lt $lte $ne  (SQL > >= < <= <>)
   ============================================================ */

db.employees.find({ salary: { $gt: 70000 } }, { _id: 0, name: 1, salary: 1 });        // Rahul, Priya, Sneha, Deepak
db.employees.find({ salary: { $gte: 70000 } }, { _id: 0, name: 1, salary: 1 });       // + Karan (70000)
db.employees.find({ salary: { $lt: 60000 } }, { _id: 0, name: 1, salary: 1 });        // Neha, Anjali, Meera
db.employees.find({ salary: { $ne: 65000 } }).count();                                 // 10 (Amit & Pooja excluded)

// BETWEEN = two operators on the same field (one object -> both must hold)
db.employees.find({ salary: { $gte: 60000, $lte: 70000 } }, { _id: 0, name: 1, salary: 1 });   // Amit, Ravi, Karan, Pooja, Vikram

// Dates: half-open range [start, next) - the safe pattern for "March 2025"
db.orders.find({ orderDate: { $gte: ISODate("2025-03-01"), $lt: ISODate("2025-04-01") } }, { _id: 1, orderDate: 1 });   // 1007, 1008

// $ne / $nin also match documents where the field is MISSING
db.employees.find({ email: { $ne: "rahul@example.com" } }).count();     // 11 - includes Anjali (no email field)
db.employees.find({ email: { $ne: "rahul@example.com" }, email: { $exists: true } }).count();   // careful: same key twice! -> only $exists survives -> 11 (see section 5)
db.employees.find({ skills: { $ne: "SQL" } }, { _id: 0, name: 1 });     // everyone WITHOUT "SQL" in skills - including Meera (no skills) -> 9


/* ============================================================
   4. $in / $nin   (SQL IN / NOT IN)
   ============================================================ */

db.employees.find({ departmentId: { $in: [1, 3] } }, { _id: 0, name: 1, departmentId: 1 });   // IT + HR: Rahul, Amit, Ravi, Pooja
db.orders.find({ status: { $in: ["Pending", "Cancelled"] } }, { _id: 1, status: 1 });         // 1006, 1015, 1017
db.employees.find({ departmentId: { $nin: [1, 2] } }, { _id: 0, name: 1, departmentId: 1 });  // includes Anjali (null)

// $in with a regex inside the list
db.employees.find({ name: { $in: [/^A/, /^P/] } }, { _id: 0, name: 1 });                       // Amit, Priya, Pooja, Anjali

// $in on an ARRAY field: any element in the list?
db.employees.find({ skills: { $in: ["SQL", "React"] } }, { _id: 0, name: 1, skills: 1 });    // Amit, Sneha, Pooja, Deepak


/* ============================================================
   5. IMPLICIT AND  vs  $and
   ============================================================ */

// Two different fields -> just list them
db.employees.find({ departmentId: 2, salary: { $gt: 60000 } }, { _id: 0, name: 1, salary: 1 });   // Priya, Vikram

// TRAP: the same key twice in one JS object keeps only the LAST one
db.employees.find({ salary: { $gt: 60000 }, salary: { $lt: 70000 } }).count();     // 11 - only $lt: 70000 survived!
// Correct ways:
db.employees.find({ salary: { $gt: 60000, $lt: 70000 } }).count();                 // 3 (Amit, Pooja, Vikram - Ravi 60000 and Karan 70000 are excluded)
db.employees.find({ $and: [ { salary: { $gt: 60000 } }, { salary: { $lt: 70000 } } ] }).count();   // 3

// $and is REQUIRED when two $or (or two of the same operator) must both hold: (IT or Sales) AND (salary > 70000 or active false)
db.employees.find({
    $and: [
        { $or: [ { departmentId: 1 }, { departmentId: 2 } ] },
        { $or: [ { salary: { $gt: 70000 } }, { active: false } ] }
    ]
}, { _id: 0, name: 1, departmentId: 1, salary: 1 });                               // Rahul, Priya


/* ============================================================
   6. $or  /  $nor
   ============================================================ */

db.employees.find({ $or: [ { departmentId: 3 }, { salary: { $gte: 85000 } } ] }, { _id: 0, name: 1 });   // Rahul, Ravi, Sneha

// Mixing AND and OR: top-level fields are ANDed with the $or
db.orders.find({ customerId: 1, $or: [ { status: "Pending" }, { totalAmount: { $gt: 50000 } } ] }, { _id: 1, status: 1, totalAmount: 1 });   // 1001, 1015

// $nor = none of the conditions may be true
db.employees.find({ $nor: [ { departmentId: 1 }, { departmentId: 2 }, { departmentId: null } ] }, { _id: 0, name: 1 });   // HR, Finance, Marketing people


/* ============================================================
   7. $not  (field level negation)
   ============================================================ */

db.employees.find({ salary: { $not: { $gt: 65000 } } }, { _id: 0, name: 1, salary: 1 });   // salary <= 65000 (and any doc without salary)
db.employees.find({ name: { $not: /a/i } }, { _id: 0, name: 1 });                            // [] - every name contains an a/A (NOT LIKE '%a%')
db.products.find({ ratings: { $not: { $size: 0 } } }).count();                               // 9 (non-empty or missing ratings)


/* ============================================================
   8. $exists / $type  (element operators, recap from Level 02)
   ============================================================ */

db.employees.find({ email: { $exists: false } }, { _id: 0, name: 1 });                 // Anjali
db.customers.find({ tags: { $exists: true } }).count();                                 // 6
db.customers.find({ email: { $exists: true, $type: "string" } }).count();              // 6 (Farhan's null excluded)
db.employees.find({ managerId: { $type: "number" } }, { _id: 0, name: 1, managerId: 1 });   // the 6 with a manager


/* ============================================================
   9. BOOLEAN AND NULL FILTERS
   ============================================================ */

db.employees.find({ active: true }).count();                                            // 11
db.orders.find({ "payment.paid": false }, { _id: 1, status: 1 });                       // 1006, 1015, 1017
db.orders.find({ employeeId: null }, { _id: 1, customerId: 1 });                        // 1019 (online order)
db.employees.find({ departmentId: null }, { _id: 0, name: 1 });                         // Anjali


/* ============================================================
   10. QUERY ON _id  (the primary key)
   ============================================================ */

db.employees.find({ _id: { $in: [101, 106] } }, { _id: 1, name: 1 });
db.orders.find({ _id: { $gte: 1017 } }, { _id: 1 });                                     // 1017, 1018, 1019
db.orders.find({ _id: { $mod: [2, 0] } }, { _id: 1 }).count();                           // even order ids -> 9

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Regex_Expr_Nested.js
   ------------------------------------------------------------ */
