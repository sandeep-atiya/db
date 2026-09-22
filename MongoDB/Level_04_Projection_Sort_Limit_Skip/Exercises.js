/* ============================================================
   LEVEL 04 - PROJECTION, SORT, LIMIT, SKIP  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   All questions use companyDB (read-only).
   ============================================================ */

use("companyDB");

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Name and city (from address) of every employee, no _id.
   Q2.  Every product field EXCEPT tags and ratings, for Furniture only.
   Q3.  The 3 most expensive products (name, price).
   Q4.  Employees sorted by department ascending then salary descending,
        showing departmentId, name, salary (no _id).
   Q5.  Page 2 of orders sorted by orderDate ascending, 4 per page (id, orderDate).
   Q6.  The same page 2 with KEYSET pagination: you know the last orderDate
        of page 1 is 2025-02-03 (order 1004) - do not use skip.
   Q7.  Order 1008 with only its first two items.
   Q8.  For orders that contain product 6 (Monitor), show just that line item
        using the positional $ projection (id + items.$).
   Q9.  Every employee's name and a computed field "monthlyTax" = 10 % of salary.
   Q10. The oldest order (one document, id + orderDate) - two ways.
   Q11. How many orders were placed by customer 1? How many documents are in
        products (estimated)?
   Q12. Distinct cities of employees; distinct payment methods used in orders.
   Q13. Sort products by name case-insensitively and show the first 3 names.
   Q14. The employee with the 3rd highest salary (name, salary) using skip/limit.
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
db.employees.find({}, { _id: 0, name: 1, "address.city": 1 });

// Q2
db.products.find({ category: "Furniture" }, { tags: 0, ratings: 0 });                // Chair, Desk, Bookshelf

// Q3
db.products.find({}, { _id: 0, name: 1, price: 1 }).sort({ price: -1 }).limit(3);   // Laptop, Monitor, Desk

// Q4
db.employees.find({}, { _id: 0, departmentId: 1, name: 1, salary: 1 }).sort({ departmentId: 1, salary: -1 });

// Q5
db.orders.find({}, { _id: 1, orderDate: 1 }).sort({ orderDate: 1 }).skip(4).limit(4);   // 1005, 1006, 1007, 1008

// Q6
db.orders.find({ orderDate: { $gt: ISODate("2025-02-03") } }, { _id: 1, orderDate: 1 }).sort({ orderDate: 1 }).limit(4);   // 1005..1008
// (With duplicate dates you would also need the _id tiebreaker - see the practice file.)

// Q7
db.orders.find({ _id: 1008 }, { items: { $slice: 2 } });                             // Laptop + Mouse lines

// Q8
db.orders.find({ "items.productId": 6 }, { _id: 1, "items.$": 1 });                  // 1003, 1005, 1013, 1018

// Q9
db.employees.find({}, { _id: 0, name: 1, monthlyTax: { $multiply: ["$salary", 0.10] } });

// Q10
db.orders.find({}, { _id: 1, orderDate: 1 }).sort({ orderDate: 1 }).limit(1);        // 1001
db.orders.findOne({}, { _id: 1, orderDate: 1 }, { sort: { orderDate: 1 } });         // 1001

// Q11
db.orders.countDocuments({ customerId: 1 });                                          // 4
db.products.estimatedDocumentCount();                                                 // 11

// Q12
db.employees.distinct("address.city");                                                // Bangalore, Delhi, Mumbai, Noida, Pune
db.orders.distinct("payment.method");                                                 // COD, Card, UPI

// Q13
db.products.find({}, { _id: 0, name: 1 }).sort({ name: 1 }).collation({ locale: "en", strength: 2 }).limit(3);   // Bookshelf, Chair, Desk

// Q14
db.employees.find({}, { _id: 0, name: 1, salary: 1 }).sort({ salary: -1, _id: 1 }).skip(2).limit(1);   // Priya 75000
