/* ============================================================
   LEVEL 03 - FIND & QUERY OPERATORS  |  02_Practice_Regex_Expr_Nested.js
   ------------------------------------------------------------
   Topics : $regex (LIKE), $expr (compare fields), $mod, $where,
            nested documents (dot notation), arrays basics,
            $comment, cursor batching

   HOW TO PRACTICE: block by block, predict first. Read-only.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. $regex  =  LIKE
   ============================================================ */

// LIKE 'Ra%'   -> anchored prefix (can use an index on name)
db.employees.find({ name: /^Ra/ }, { _id: 0, name: 1 });                          // Rahul, Ravi
db.employees.find({ name: { $regex: "^Ra" } }, { _id: 0, name: 1 });              // same, operator form (needed from JSON / drivers)

// LIKE '%a'    -> anchored suffix
db.employees.find({ name: /a$/ }, { _id: 0, name: 1 });                           // Priya, Neha, Sneha, Pooja, Meera

// LIKE '%ee%'  -> unanchored (full scan of the values)
db.employees.find({ name: /ee/ }, { _id: 0, name: 1 });                           // Deepak, Meera

// case-insensitive:  i
db.employees.find({ name: /^ra/i }, { _id: 0, name: 1 });                         // Rahul, Ravi
db.employees.find({ name: { $regex: "^ra", $options: "i" } }, { _id: 0, name: 1 });

// LIKE 'A_it' -> . is one character;  LIKE '[PN]%' -> character class
db.employees.find({ name: /^A.it$/ }, { _id: 0, name: 1 });                       // Amit
db.employees.find({ name: /^[PN]/ }, { _id: 0, name: 1 });                        // Priya, Neha, Pooja

// emails ending in example.com  (escape the dot)
db.customers.find({ email: /@example\.com$/ }).count();                           // 6

// regex on array elements: any skill that contains "SQL"
db.employees.find({ skills: /SQL/ }, { _id: 0, name: 1, skills: 1 });             // Sneha, Pooja, Deepak

// exact whole-word, case-insensitive: the "LOWER(name) = 'rahul'" pattern
db.employees.find({ name: /^rahul$/i }, { _id: 0, name: 1 });                     // Rahul

// Index note: /^Ra/ uses the index (range scan "Ra".."Rb"); /Ra/ and /^ra/i scan every key.


/* ============================================================
   2. $expr  =  compare fields of the SAME document
   ============================================================ */

// Products whose inventory value (price * stock) > 500000
db.products.find({ $expr: { $gt: [ { $multiply: ["$price", "$stock"] }, 500000 ] } }, { _id: 0, name: 1, price: 1, stock: 1 });
// Laptop (750000), Monitor (625000)

// Orders with more than one line item
db.orders.find({ $expr: { $gt: [ { $size: "$items" }, 1 ] } }, { _id: 1, "items.productId": 1 });   // 1002, 1007, 1008, 1010, 1013, 1017

// Employees whose pincode "looks like" their city code region: address.pincode > 400000 (a normal operator does this better!)
db.employees.find({ $expr: { $gt: ["$address.pincode", 400000] } }).count();       // 7
db.employees.find({ "address.pincode": { $gt: 400000 } }).count();                 // 7 - prefer this form: it can use an index

// Field vs field: orders where a single line item covers the whole order (items[0].qty * unitPrice == totalAmount)
db.orders.find({ $expr: { $eq: [ "$totalAmount", { $multiply: [ { $arrayElemAt: ["$items.qty", 0] }, { $arrayElemAt: ["$items.unitPrice", 0] } ] } ] } }).count();   // 13 (single-line orders)

// $expr with $and and dates: hired in the same year they turned... (dates: Level 10). Simple: hired before 2022-01-01
db.employees.find({ $expr: { $lt: ["$hireDate", ISODate("2022-01-01")] } }, { _id: 0, name: 1, hireDate: 1 });   // Priya, Sneha, Deepak


/* ============================================================
   3. $mod  and  $where  (rarely needed)
   ============================================================ */

db.employees.find({ _id: { $mod: [2, 1] } }, { _id: 1, name: 1 });                // odd employee ids

// $where runs JavaScript per document on the server: SLOW, no index, avoid. Shown once so you recognise it.
db.employees.find({ $where: "this.salary > 80000" }, { _id: 0, name: 1 });         // Rahul, Sneha
// Same thing, the right way:
db.employees.find({ salary: { $gt: 80000 } }, { _id: 0, name: 1 });


/* ============================================================
   4. NESTED DOCUMENTS - dot notation
   ============================================================ */

db.employees.find({ "address.city": "Delhi" }, { _id: 0, name: 1, "address.city": 1 });               // Rahul, Ravi, Pooja, Anjali
db.employees.find({ "address.state": "Maharashtra", salary: { $gt: 60000 } }, { _id: 0, name: 1 });    // Priya, Karan, Vikram
db.orders.find({ "payment.method": "COD" }, { _id: 1, "payment.paid": 1 });                            // 1004, 1009, 1015, 1017
db.orders.find({ "payment.method": "COD", "payment.paid": false }, { _id: 1 });                         // 1015, 1017

// Whole-document equality (rarely what you want): must list every field in the same order
db.orders.find({ payment: { method: "COD", paid: false } }, { _id: 1 });                                // 1015, 1017 - works because payment has exactly these 2 fields
db.orders.find({ payment: { paid: false, method: "COD" } }, { _id: 1 });                                // [] - order differs


/* ============================================================
   5. ARRAYS - the basics (Level 06 goes deep)
   ============================================================ */

// "contains": equality on an array field matches if ANY element equals
db.employees.find({ skills: "MongoDB" }, { _id: 0, name: 1 });                    // Rahul, Amit, Pooja

// exact array: same elements, same order
db.employees.find({ skills: ["Sales", "Excel"] }, { _id: 0, name: 1 });           // Neha
db.employees.find({ skills: ["Excel", "Sales"] }, { _id: 0, name: 1 });           // [] - order matters

// by position
db.employees.find({ "skills.0": "Sales" }, { _id: 0, name: 1 });                  // Priya, Neha, Vikram

// array of embedded documents: any element's field
db.orders.find({ "items.productId": 1 }, { _id: 1 });                              // orders containing a Laptop: 1001, 1008, 1014
db.orders.find({ "items.qty": { $gte: 10 } }, { _id: 1 });                         // 1010, 1016, 1017

// THE TRAP: two conditions on "items.*" may be satisfied by DIFFERENT elements
db.orders.find({ "items.productId": 8, "items.qty": 1 }, { _id: 1 });             // 1017: productId 8 (qty 100) and qty 1 (product 9) -> matched by 2 different items!
db.orders.find({ items: { $elemMatch: { productId: 8, qty: 1 } } }, { _id: 1 });  // [] - $elemMatch needs ONE element with both


/* ============================================================
   6. $comment and cursor batching  (good to know)
   ============================================================ */

// $comment shows up in the logs / profiler / currentOp - tag your queries
db.employees.find({ departmentId: 1, $comment: "L03 demo query" }).count();       // 3

// The server returns documents in batches; the shell asks for more as you iterate.
const c = db.orders.find().batchSize(5);          // first batch of 5, then getMore
c.objsLeftInBatch();                              // 0 until the first next()
c.next()._id;                                     // 1001
c.objsLeftInBatch();                              // 4

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
