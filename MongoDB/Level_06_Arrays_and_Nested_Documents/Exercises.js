/* ============================================================
   LEVEL 06 - ARRAYS & NESTED DOCS  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Q1-Q7 read the base collections; Q8-Q15 modify the copies
   l06_ex_employees / l06_ex_orders created below.
   ============================================================ */

use("companyDB");
db.employees.aggregate([{ $out: "l06_ex_employees" }]);
db.orders.aggregate([{ $out: "l06_ex_orders" }]);

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Employees who know BOTH "MongoDB" and "SQL" (name).
   Q2.  Employees with exactly 2 skills (name, skills).
   Q3.  Customers with at least one tag AND whose first tag is "vip" (name, tags).
   Q4.  Orders containing a Keyboard (3) with qty >= 2 in the same line (id).
   Q5.  Products that have a rating of exactly 5 and also a rating below 4
        (any elements) - then the products that have ONE rating between
        3.5 and 4.5 ($elemMatch). Compare the results.
   Q6.  Orders with 3 or more line items (id).
   Q7.  Employees whose address has a pincode starting with 4 (name, address.pincode).
        Hint: pincode is a number - think $gte / $lt.
   Q8.  Add "Docker" to Rahul's (101) skills only if it is not already there; run twice.
   Q9.  Add "Excel" and "PowerPoint" to Anjali (110) at the FRONT of her skills.
   Q10. Remove "Excel" from every employee who has it. How many were modified?
   Q11. In order 1008, set the qty of the Keyboard line (productId 3) to 4 using $.
   Q12. In every order, add discount: 0 to EVERY line item ($[]).
   Q13. In every Completed order, set discount: 5 on lines whose unitPrice > 20000
        (arrayFilters). Which orders changed?
   Q14. Keep only the last 2 skills of Sneha (106) using $push with $slice.
   Q15. Change Pooja's (108) city to "Faridabad" without touching state / pincode,
        then remove her pincode.
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
db.employees.find({ skills: { $all: ["MongoDB", "SQL"] } }, { _id: 0, name: 1 });              // Pooja

// Q2
db.employees.find({ skills: { $size: 2 } }, { _id: 0, name: 1, skills: 1 });                  // Priya, Neha, Ravi, Vikram, Deepak

// Q3
db.customers.find({ "tags.0": "vip" }, { _id: 0, name: 1, tags: 1 });                         // Aarav, Bhavna, Esha

// Q4
db.orders.find({ items: { $elemMatch: { productId: 3, qty: { $gte: 2 } } } }, { _id: 1 });     // 1007

// Q5
db.products.find({ ratings: 5, ratings: { $lt: 4 } }).count();                                 // careful: duplicate key! only { $lt: 4 } survives -> 3
db.products.find({ $and: [ { ratings: 5 }, { ratings: { $lt: 4 } } ] }, { _id: 0, name: 1, ratings: 1 });   // Keyboard [3,4,5]
db.products.find({ ratings: { $elemMatch: { $gte: 3.5, $lte: 4.5 } } }, { _id: 0, name: 1, ratings: 1 });   // Laptop, Mouse, Keyboard, Chair, Monitor, Bookshelf

// Q6
db.orders.find({ "items.2": { $exists: true } }, { _id: 1 });                                  // 1008

// Q7
db.employees.find({ "address.pincode": { $gte: 400000, $lt: 500000 } }, { _id: 0, name: 1, "address.pincode": 1 });   // Priya, Neha, Karan, Vikram, Meera

// Q8
db.l06_ex_employees.updateOne({ _id: 101 }, { $addToSet: { skills: "Docker" } });              // modifiedCount 1
db.l06_ex_employees.updateOne({ _id: 101 }, { $addToSet: { skills: "Docker" } });              // modifiedCount 0
db.l06_ex_employees.findOne({ _id: 101 }, { _id: 0, skills: 1 });

// Q9
db.l06_ex_employees.updateOne({ _id: 110 }, { $push: { skills: { $each: ["Excel", "PowerPoint"], $position: 0 } } });
db.l06_ex_employees.findOne({ _id: 110 }, { _id: 0, skills: 1 });                              // [ 'Excel', 'PowerPoint' ]

// Q10
db.l06_ex_employees.updateMany({ skills: "Excel" }, { $pull: { skills: "Excel" } });           // modifiedCount 4 (Neha, Ravi, Sneha, Anjali)
db.l06_ex_employees.countDocuments({ skills: "Excel" });                                       // 0

// Q11
db.l06_ex_orders.updateOne({ _id: 1008, "items.productId": 3 }, { $set: { "items.$.qty": 4 } });
db.l06_ex_orders.findOne({ _id: 1008 }, { _id: 0, items: 1 });

// Q12
db.l06_ex_orders.updateMany({}, { $set: { "items.$[].discount": 0 } });                        // 19 modified
db.l06_ex_orders.findOne({ _id: 1002 }, { _id: 0, items: 1 });

// Q13
db.l06_ex_orders.updateMany({ status: "Completed" }, { $set: { "items.$[i].discount": 5 } }, { arrayFilters: [ { "i.unitPrice": { $gt: 20000 } } ] });
db.l06_ex_orders.find({ "items.discount": 5 }, { _id: 1 });                                    // 1001, 1003, 1005, 1008, 1013, 1014, 1018

// Q14
db.l06_ex_employees.updateOne({ _id: 106 }, { $push: { skills: { $each: [], $slice: -2 } } });
db.l06_ex_employees.findOne({ _id: 106 }, { _id: 0, skills: 1 });                              // [ 'Accounting', 'SQL' ]
// (Q10 already pulled "Excel", so Sneha had 2 skills left and nothing changed: modifiedCount 0.
//  On the original [ 'Accounting', 'Excel', 'SQL' ] the result would be [ 'Excel', 'SQL' ].)

// Q15
db.l06_ex_employees.updateOne({ _id: 108 }, { $set: { "address.city": "Faridabad" } });
db.l06_ex_employees.updateOne({ _id: 108 }, { $unset: { "address.pincode": "" } });
db.l06_ex_employees.findOne({ _id: 108 }, { _id: 0, address: 1 });                             // { city: 'Faridabad', state: 'Delhi' }

db.l06_ex_employees.drop();
db.l06_ex_orders.drop();
