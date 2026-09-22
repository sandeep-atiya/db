/* ============================================================
   LEVEL 04  |  02_Practice_Sort_Limit_Skip_Count.js
   ------------------------------------------------------------
   Topics : sort (multi-key, missing values, types, strings,
            collation, ties), limit, skip, pagination (offset vs
            keyset), countDocuments / estimatedDocumentCount,
            distinct, natural order

   HOW TO PRACTICE: block by block, predict first.
   Uses companyDB (read-only) + a throwaway l04_ collection.
   ============================================================ */

use("companyDB");


/* ============================================================
   1. SORT
   ============================================================ */

db.employees.find({}, { _id: 0, name: 1, salary: 1 }).sort({ salary: -1 });          // Sneha 90000 ... Anjali 48000
db.employees.find({}, { _id: 0, name: 1, salary: 1 }).sort({ salary: 1 });

// Multi-key: department ascending, then salary descending. KEY ORDER MATTERS.
db.employees.find({}, { _id: 0, departmentId: 1, name: 1, salary: 1 }).sort({ departmentId: 1, salary: -1 });
// null dept (Anjali) first, then IT: Rahul 85000, Amit 65000 / Pooja 65000 (tie!), Sales: Priya, Vikram, Neha ...

// Ties: Amit and Pooja both 65000 - their relative order is NOT guaranteed. Add a tiebreaker:
db.employees.find({ salary: 65000 }, { _id: 1, name: 1 }).sort({ salary: -1, _id: 1 });   // Amit (102) always before Pooja (108)

// Sort on a nested field
db.employees.find({}, { _id: 0, name: 1, "address.city": 1 }).sort({ "address.city": 1, name: 1 });

// Sort on a date (newest first)
db.orders.find({}, { _id: 1, orderDate: 1 }).sort({ orderDate: -1 }).limit(3);       // 1019, 1018, 1017


/* ============================================================
   2. SORT: missing fields, mixed types, strings
   ============================================================ */

// Missing field sorts as null -> FIRST ascending, LAST descending
db.employees.find({}, { _id: 0, name: 1, email: 1 }).sort({ email: 1 }).limit(2);    // Anjali (no email) first
db.employees.find({}, { _id: 0, name: 1, email: 1 }).sort({ email: -1 }).limit(2);   // vikram@, sneha@

// Strings sort byte-wise: uppercase before lowercase
db.l04_names.drop();
db.l04_names.insertMany([{ n: "banana" }, { n: "Apple" }, { n: "cherry" }, { n: "apple" }, { n: "Banana" }, { n: "10" }, { n: "9" }, { n: "100" }]);
db.l04_names.find({}, { _id: 0 }).sort({ n: 1 });                                    // "10","100","9","Apple","Banana","apple","banana","cherry"

// Collation: case-insensitive (strength 2) and numeric ordering for digit strings
db.l04_names.find({}, { _id: 0 }).sort({ n: 1 }).collation({ locale: "en", strength: 2 });               // apple/Apple, banana/Banana, cherry (10,100,9 first)
db.l04_names.find({}, { _id: 0 }).sort({ n: 1 }).collation({ locale: "en", numericOrdering: true });     // "9","10","100", then words
// Collation also affects EQUALITY:
db.l04_names.find({ n: "APPLE" }).count();                                                                // 0
db.l04_names.find({ n: "APPLE" }).collation({ locale: "en", strength: 2 }).count();                      // 2


/* ============================================================
   3. LIMIT AND SKIP  (TOP / OFFSET-FETCH)
   ============================================================ */

db.employees.find({}, { _id: 0, name: 1, salary: 1 }).sort({ salary: -1 }).limit(3);          // top 3 earners
db.employees.find({}, { _id: 0, name: 1, salary: 1 }).sort({ salary: -1 }).skip(3).limit(3);  // ranks 4-6

// The ORDER OF THE METHOD CALLS DOES NOT MATTER for find(): the server does sort -> skip -> limit
db.employees.find({}, { _id: 0, name: 1, salary: 1 }).limit(3).sort({ salary: -1 });          // same top 3
db.employees.find({}, { _id: 0, name: 1, salary: 1 }).skip(3).sort({ salary: -1 }).limit(3);  // same ranks 4-6

// limit(0) = no limit
db.employees.find().limit(0).count();                                                          // 12

// "Second highest salary" the SQL OFFSET way (ties ignored - see Level 09 for $denseRank)
db.employees.find({}, { _id: 0, name: 1, salary: 1 }).sort({ salary: -1 }).skip(1).limit(1);  // Rahul 85000


/* ============================================================
   4. PAGINATION: offset (skip) vs keyset (range)
   ============================================================ */

const pageSize = 5;

// Offset pagination: page 2 -> skip 5. Simple, but skip reads & throws away 5 docs (page 1000 -> 4995 docs!)
db.employees.find({}, { _id: 1, name: 1 }).sort({ _id: 1 }).skip(pageSize * 1).limit(pageSize);   // 106..110

// Keyset pagination: remember the last _id of the previous page, ask for the next ones. O(pageSize) always.
const page1 = db.employees.find({}, { _id: 1, name: 1 }).sort({ _id: 1 }).limit(pageSize).toArray();
const lastId = page1[page1.length - 1]._id;                                                     // 105
db.employees.find({ _id: { $gt: lastId } }, { _id: 1, name: 1 }).sort({ _id: 1 }).limit(pageSize);   // 106..110 - same page, no skip

// Keyset with a NON-unique sort key (salary desc) needs the tiebreaker in the condition too:
// "after (salary 65000, _id 102)"  ->  salary < 65000  OR  (salary == 65000 AND _id > 102)
db.employees.find(
    { $or: [ { salary: { $lt: 65000 } }, { salary: 65000, _id: { $gt: 102 } } ] },
    { _id: 1, name: 1, salary: 1 }
).sort({ salary: -1, _id: 1 }).limit(3);                                                        // Pooja 65000, Vikram 62000, Ravi 60000
// (Style note: never START a line with ".sort" - the shell would read it as a REPL command.)


/* ============================================================
   5. COUNTING
   ============================================================ */

db.employees.countDocuments();                                   // 12 - exact, scans (uses the _id index)
db.employees.countDocuments({ departmentId: 2 });                // 3  - exact with a filter
db.employees.countDocuments({}, { skip: 10 });                   // 2  - count honours skip / limit options
db.employees.estimatedDocumentCount();                           // 12 - from metadata, no filter possible, instant
db.employees.find({ departmentId: 2 }).count();                  // 3  - DEPRECATED cursor.count()

// countDocuments returns 0 for an unknown collection - no error
db.nothing_here.countDocuments();                                // 0


/* ============================================================
   6. DISTINCT
   ============================================================ */

db.employees.distinct("departmentId");                           // [ null, 1, 2, 3, 4, 5 ]  (sorted, includes null)
db.products.distinct("category");                                // [ 'Electronics', 'Furniture', 'Stationery' ]
db.employees.distinct("address.city");                           // nested field
db.employees.distinct("skills");                                 // ARRAY field -> every element, flattened
db.employees.distinct("skills", { departmentId: 1 });            // with a filter: skills in IT
db.orders.distinct("items.productId");                           // products ever ordered (10 of 11 - no Webcam)
db.orders.distinct("items.productId").length;                    // 10

// Same with aggregation (no 16 MB result limit, can count too)
db.employees.aggregate([{ $group: { _id: "$address.city" } }, { $sort: { _id: 1 } }]);


/* ============================================================
   7. NATURAL ORDER (no sort) - do not rely on it
   ============================================================ */

db.employees.find({}, { _id: 1 }).limit(3);                      // 101, 102, 103 today ... but only because of insertion order
db.employees.find({}, { _id: 1 }).sort({ $natural: -1 }).limit(3);   // reverse storage order - a shell trick, not a guarantee


/* ============================================================
   CLEANUP
   ============================================================ */
db.l04_names.drop();

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
