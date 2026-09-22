/* ============================================================
   LEVEL 06 - ARRAYS & NESTED DOCS  |  01_Practice_Query_Arrays_Nested.js
   ------------------------------------------------------------
   Topics : contains / exact / $all / $in / $nin / $size,
            positional dot notation, arrays of embedded documents,
            $elemMatch (documents and scalars), the different-element
            trap, empty vs missing arrays, negation, nested docs

   HOW TO PRACTICE: block by block, predict first. Read-only.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. ARRAYS OF SCALARS: contains, exact, $all, $in, $nin
   ============================================================ */

// contains
db.employees.find({ skills: "SQL" }, { _id: 0, name: 1, skills: 1 });                          // Sneha, Pooja, Deepak
// exact array (same elements, same order)
db.employees.find({ skills: ["Accounting", "SQL"] }, { _id: 0, name: 1 });                     // Deepak
db.employees.find({ skills: ["SQL", "Accounting"] }, { _id: 0, name: 1 });                     // [] - order differs
// all of (any order)
db.employees.find({ skills: { $all: ["SQL", "Accounting"] } }, { _id: 0, name: 1 });           // Sneha, Deepak
// any of
db.employees.find({ skills: { $in: ["Java", "Python"] } }, { _id: 0, name: 1 });               // Rahul, Pooja
// none of (also matches missing skills -> Meera)
db.employees.find({ skills: { $nin: ["Sales", "Excel", "SQL", "MongoDB"] } }, { _id: 0, name: 1 });   // Karan, Anjali, Meera

// customers tags
db.customers.find({ tags: "vip" }, { _id: 0, name: 1 });                                        // Aarav, Bhavna, Esha
db.customers.find({ tags: { $all: ["vip", "newsletter"] } }, { _id: 0, name: 1 });              // Esha


/* ============================================================
   2. $size, length tricks, position
   ============================================================ */

db.employees.find({ skills: { $size: 3 } }, { _id: 0, name: 1 });                                // Rahul, Amit, Sneha, Karan, Pooja
db.employees.find({ skills: { $size: 0 } }, { _id: 0, name: 1 });                                // Anjali
// $size only does equality. "at least 3":
db.employees.find({ "skills.2": { $exists: true } }, { _id: 0, name: 1 });                       // same 5 as $size: 3 here
// "more than 2" with $expr (guard against missing arrays)
db.employees.find({ $expr: { $gt: [ { $size: { $ifNull: ["$skills", []] } }, 2 ] } }, { _id: 0, name: 1 });
// by position
db.employees.find({ "skills.0": "Sales" }, { _id: 0, name: 1 });                                 // Priya, Neha, Vikram
db.employees.find({ "skills.1": /SQL|Excel/ }, { _id: 0, name: 1, skills: 1 });                  // second skill is SQL or Excel


/* ============================================================
   3. EMPTY ARRAY vs MISSING FIELD
   ============================================================ */

db.employees.find({ skills: [] }, { _id: 0, name: 1 });                                          // Anjali
db.employees.find({ skills: { $exists: false } }, { _id: 0, name: 1 });                          // Meera
db.employees.find({ skills: { $exists: true, $ne: [] } }).count();                               // 10 (has a non-empty array)
db.products.find({ ratings: { $in: [[], null] } }, { _id: 0, name: 1 });                         // Desk, Webcam (empty) + Notebook (missing = null)


/* ============================================================
   4. ARRAYS OF EMBEDDED DOCUMENTS (orders.items)
   ============================================================ */

db.orders.find({ "items.productId": 6 }, { _id: 1, "items.productId": 1 });                      // 1003, 1005, 1013, 1018
db.orders.find({ "items.qty": { $gte: 10 } }, { _id: 1 });                                       // 1010, 1016, 1017
db.orders.find({ "items.0.productId": 1 }, { _id: 1 });                                          // first line is a Laptop: 1001, 1008, 1014

// THE TRAP: conditions matched by DIFFERENT elements
db.orders.find({ "items.productId": 8, "items.qty": 1 }, { _id: 1, items: 1 });                  // 1017 - Pen qty 100 + Headphones qty 1
// $elemMatch: ONE element must satisfy everything
db.orders.find({ items: { $elemMatch: { productId: 8, qty: 1 } } }, { _id: 1 });                  // []
db.orders.find({ items: { $elemMatch: { productId: 8, qty: { $gte: 50 } } } }, { _id: 1 });      // 1010, 1017

// exact embedded document as an element (all fields, same order)
db.orders.find({ items: { productId: 1, qty: 1, unitPrice: 75000 } }, { _id: 1 });               // 1001, 1008
db.orders.find({ items: { productId: 1, unitPrice: 75000 } }, { _id: 1 });                       // [] - qty missing -> no exact match

// orders with at least 2 lines
db.orders.find({ "items.1": { $exists: true } }, { _id: 1 });                                    // 1002, 1007, 1008, 1010, 1013, 1017
// orders with EXACTLY 1 line
db.orders.find({ items: { $size: 1 } }).count();                                                 // 13


/* ============================================================
   5. $elemMatch ON SCALAR ARRAYS  (two operators, same element)
   ============================================================ */

// "a rating between 3 and 4 inclusive" - WITHOUT $elemMatch: any element >= 3 AND any (maybe other) element <= 4
db.products.find({ ratings: { $gte: 3, $lte: 4 } }, { _id: 0, name: 1, ratings: 1 });            // all 8 products with ratings: some element >= 3 and some element <= 4
db.products.find({ ratings: { $gte: 4.5, $lte: 3.5 } }, { _id: 0, name: 1, ratings: 1 });        // Laptop, Keyboard, Monitor - impossible range, still matches!
db.products.find({ ratings: { $elemMatch: { $gte: 4.5, $lte: 3.5 } } }).count();                 // 0 - correct
db.products.find({ ratings: { $elemMatch: { $gte: 2, $lte: 3 } } }, { _id: 0, name: 1, ratings: 1 });   // Keyboard, Pen, Headphones

// any element > 4  (simple single operator - no $elemMatch needed)
db.products.find({ ratings: { $gt: 4 } }, { _id: 0, name: 1, ratings: 1 });                      // Laptop, Keyboard, Monitor


/* ============================================================
   6. NEGATION WITH ARRAYS
   ============================================================ */

db.orders.find({ "items.productId": { $ne: 2 } }).count();                                       // 15: orders with NO mouse line at all ($ne on array = no element equals)
db.orders.find({ items: { $not: { $elemMatch: { productId: 2 } } } }).count();                    // 15 - same, explicit
db.employees.find({ skills: { $not: { $size: 0 } } }).count();                                    // 11 (non-empty OR missing)


/* ============================================================
   7. NESTED DOCUMENTS (recap + more)
   ============================================================ */

db.employees.find({ "address.city": "Delhi", "address.pincode": { $gte: 110005 } }, { _id: 0, name: 1, address: 1 });   // Ravi, Pooja
db.orders.find({ "payment.method": { $in: ["COD", "UPI"] }, "payment.paid": true }, { _id: 1 }).count();               // 8 (2 COD + 6 UPI paid)
// Nested field existence
db.orders.find({ "payment.refundedAt": { $exists: true } }).count();                             // 0
// Sorting by a nested field
db.employees.find({}, { _id: 0, name: 1, "address.pincode": 1 }).sort({ "address.pincode": -1 }).limit(3);  // Deepak 560034, Sneha 560001, Vikram 411014


/* ============================================================
   8. SORTING ON AN ARRAY FIELD
   ============================================================ */

// ascending: uses the SMALLEST element; descending: the LARGEST
db.products.find({ ratings: { $exists: true, $ne: [] } }, { _id: 0, name: 1, ratings: 1 }).sort({ ratings: 1 }).limit(3);    // Headphones [2,3] first
db.products.find({ ratings: { $exists: true, $ne: [] } }, { _id: 0, name: 1, ratings: 1 }).sort({ ratings: -1 }).limit(3);   // Laptop / Keyboard / Monitor (max 5)

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Update_Arrays.js
   ------------------------------------------------------------ */
