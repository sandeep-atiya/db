/* ============================================================
   LEVEL 03 - FIND & QUERY OPERATORS  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   All questions use companyDB (read-only). Show only the
   fields named in the question.
   ============================================================ */

use("companyDB");

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  Employees (name, salary) earning between 60000 and 75000 inclusive.
   Q2.  Employees in department 1 or 4 with salary above 70000 (name, departmentId, salary).
   Q3.  Orders that are Completed AND worth 30000 or more (id, totalAmount).
   Q4.  Orders that are NOT Completed (id, status) - two different ways.
   Q5.  Customers whose name starts with "A" or "B" (name) using ONE regex.
   Q6.  Employees whose email contains "ee" (name, email).
   Q7.  Employees hired in 2023 (name, hireDate) - use a date range, not a string.
   Q8.  Products with stock below 20 OR price above 20000 (name, price, stock).
   Q9.  Employees who have the skill "Excel" (name, skills).
   Q10. Orders that contain product 2 (Mouse) with quantity 2 or more IN THE SAME LINE (id, items).
   Q11. Products whose price is more than 100 times their stock (name, price, stock).
   Q12. Customers who have no orders? Not possible in find() alone - explain why,
        then answer "customers with no tags field" (name) instead.
   Q13. Employees whose address.city is Delhi AND who report to someone (managerId not null) (name, managerId).
   Q14. Everything about the first Pending order (one document).
   Q15. Count the orders paid by UPI.
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================================ */

// Q1
db.employees.find({ salary: { $gte: 60000, $lte: 75000 } }, { _id: 0, name: 1, salary: 1 });
// Amit, Priya, Ravi, Karan, Pooja, Vikram, Deepak (7)

// Q2
db.employees.find({ departmentId: { $in: [1, 4] }, salary: { $gt: 70000 } }, { _id: 0, name: 1, departmentId: 1, salary: 1 });
// Rahul, Sneha, Deepak

// Q3
db.orders.find({ status: "Completed", totalAmount: { $gte: 30000 } }, { _id: 1, totalAmount: 1 });
// 1001, 1005, 1008, 1012, 1014, 1018

// Q4
db.orders.find({ status: { $ne: "Completed" } }, { _id: 1, status: 1 });            // 1006, 1015, 1017
db.orders.find({ status: { $in: ["Pending", "Cancelled"] } }, { _id: 1, status: 1 });
// (or { status: { $nin: ["Completed"] } })

// Q5
db.customers.find({ name: /^[AB]/ }, { _id: 0, name: 1 });                          // Aarav Sharma, Bhavna Mehta

// Q6
db.employees.find({ email: /ee/ }, { _id: 0, name: 1, email: 1 });                  // Deepak, Meera

// Q7
db.employees.find({ hireDate: { $gte: ISODate("2023-01-01"), $lt: ISODate("2024-01-01") } }, { _id: 0, name: 1, hireDate: 1 });
// Amit, Karan, Pooja

// Q8
db.products.find({ $or: [ { stock: { $lt: 20 } }, { price: { $gt: 20000 } } ] }, { _id: 0, name: 1, price: 1, stock: 1 });
// Laptop, Desk, Monitor, Headphones, Bookshelf

// Q9
db.employees.find({ skills: "Excel" }, { _id: 0, name: 1, skills: 1 });             // Neha, Ravi, Sneha

// Q10
db.orders.find({ items: { $elemMatch: { productId: 2, qty: { $gte: 2 } } } }, { _id: 1, items: 1 });   // 1002, 1016
// Compare with the WRONG version that matches across different items:
db.orders.find({ "items.productId": 2, "items.qty": { $gte: 2 } }, { _id: 1 });     // 1002, 1007 (!), 1016  - 1007 has Mouse qty 1 but Keyboard qty 2

// Q11
db.products.find({ $expr: { $gt: ["$price", { $multiply: ["$stock", 100] }] } }, { _id: 0, name: 1, price: 1, stock: 1 });
// Laptop (75000 > 1000), Chair (8000 > 2000), Desk (15000 > 1500), Monitor (25000 > 2500),
// Headphones (3000 > 0), Bookshelf (12000 > 500), Webcam (4500 > 3000)  -> 7 products

// Q12
// find() looks at ONE collection; "has no orders" needs data from orders -> $lookup in aggregation (Level 09).
db.customers.find({ tags: { $exists: false } }, { _id: 0, name: 1 });              // Farhan Ali, Hina Khan

// Q13
db.employees.find({ "address.city": "Delhi", managerId: { $ne: null } }, { _id: 0, name: 1, managerId: 1 });   // Pooja

// Q14
db.orders.findOne({ status: "Pending" });                                            // 1015

// Q15
db.orders.countDocuments({ "payment.method": "UPI" });                              // 7
