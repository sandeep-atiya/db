/* ============================================================
   00_SETUP  |  02_Insert_Sample_Data.js
   ------------------------------------------------------------
   Loads the sample data used by EVERY level.
   Safe to re-run: collections are emptied first.

   The data is small on purpose so you can predict results by hand,
   but it contains the "tricky" cases interviewers love:
     - employee with departmentId: null AND no email field (Anjali 110)
     - employee with an EMPTY skills array (Anjali) vs NO skills field (Meera 112)
     - department with no employees (Legal 6)
     - duplicate salaries (Amit & Pooja = 65000)  -> ranking practice
     - inactive employee (Meera, active: false)
     - customer with email: null (Farhan 6) vs email MISSING (Hina 8)
     - customer with no orders (Hina 8)
     - product never ordered (Webcam 11), product with 0 stock (Headphones 9)
     - product with empty ratings [] (Desk, Webcam) vs no ratings field (Notebook)
     - order with employeeId: null = online order (1019)
     - order status Pending / Completed / Cancelled
     - orders spread over 9 months (Jan -> Sep 2025)

   Numbers are stored as plain JS numbers - exactly what a Node.js app
   would store: whole numbers become BSON int (32-bit), fractions become
   double. Level 02 shows NumberInt / NumberLong / NumberDecimal.
   ============================================================ */

use("companyDB");

/* ---------- Empty the collections (keeps indexes) ---------- */
db.departments.deleteMany({});
db.employees.deleteMany({});
db.customers.deleteMany({});
db.products.deleteMany({});
db.orders.deleteMany({});

/* ---------- 1. departments (6) ---------- */
db.departments.insertMany([
    { _id: 1, name: "IT",        location: "Delhi" },
    { _id: 2, name: "Sales",     location: "Mumbai" },
    { _id: 3, name: "HR",        location: "Delhi" },
    { _id: 4, name: "Finance",   location: "Bangalore" },
    { _id: 5, name: "Marketing", location: "Pune" },
    { _id: 6, name: "Legal",     location: "Delhi" }        // no employees ($lookup / anti-join practice)
]);

/* ---------- 2. employees (12) ---------- */
db.employees.insertMany([
    { _id: 101, name: "Rahul",  email: "rahul@example.com",  departmentId: 1, salary: 85000, hireDate: ISODate("2022-01-10"), managerId: null,
      skills: ["Java", "MongoDB", "NodeJS"],        address: { city: "Delhi",     state: "Delhi",       pincode: 110001 }, active: true },   // IT head
    { _id: 102, name: "Amit",   email: "amit@example.com",   departmentId: 1, salary: 65000, hireDate: ISODate("2023-03-15"), managerId: 101,
      skills: ["JavaScript", "React", "MongoDB"],   address: { city: "Noida",     state: "UP",          pincode: 201301 }, active: true },
    { _id: 103, name: "Priya",  email: "priya@example.com",  departmentId: 2, salary: 75000, hireDate: ISODate("2021-07-20"), managerId: null,
      skills: ["Sales", "Negotiation"],             address: { city: "Mumbai",    state: "Maharashtra", pincode: 400001 }, active: true },   // Sales head
    { _id: 104, name: "Neha",   email: "neha@example.com",   departmentId: 2, salary: 55000, hireDate: ISODate("2024-02-12"), managerId: 103,
      skills: ["Sales", "Excel"],                   address: { city: "Mumbai",    state: "Maharashtra", pincode: 400050 }, active: true },
    { _id: 105, name: "Ravi",   email: "ravi@example.com",   departmentId: 3, salary: 60000, hireDate: ISODate("2022-11-01"), managerId: null,
      skills: ["Recruiting", "Excel"],              address: { city: "Delhi",     state: "Delhi",       pincode: 110020 }, active: true },   // HR head
    { _id: 106, name: "Sneha",  email: "sneha@example.com",  departmentId: 4, salary: 90000, hireDate: ISODate("2020-05-18"), managerId: null,
      skills: ["Accounting", "Excel", "SQL"],       address: { city: "Bangalore", state: "Karnataka",   pincode: 560001 }, active: true },   // Finance head (highest paid)
    { _id: 107, name: "Karan",  email: "karan@example.com",  departmentId: 5, salary: 70000, hireDate: ISODate("2023-08-25"), managerId: null,
      skills: ["SEO", "Content", "Analytics"],      address: { city: "Pune",      state: "Maharashtra", pincode: 411001 }, active: true },   // Marketing head
    { _id: 108, name: "Pooja",  email: "pooja@example.com",  departmentId: 1, salary: 65000, hireDate: ISODate("2023-06-01"), managerId: 101,
      skills: ["Python", "MongoDB", "SQL"],         address: { city: "Delhi",     state: "Delhi",       pincode: 110005 }, active: true },   // same salary as Amit
    { _id: 109, name: "Vikram", email: "vikram@example.com", departmentId: 2, salary: 62000, hireDate: ISODate("2022-09-14"), managerId: 103,
      skills: ["Sales", "CRM"],                     address: { city: "Pune",      state: "Maharashtra", pincode: 411014 }, active: true },
    { _id: 110, name: "Anjali",                              departmentId: null, salary: 48000, hireDate: ISODate("2024-05-20"), managerId: null,
      skills: [],                                   address: { city: "Delhi",     state: "Delhi",       pincode: 110001 }, active: true },   // contractor: NO email field, null dept, EMPTY skills
    { _id: 111, name: "Deepak", email: "deepak@example.com", departmentId: 4, salary: 72000, hireDate: ISODate("2021-03-03"), managerId: 106,
      skills: ["Accounting", "SQL"],                address: { city: "Bangalore", state: "Karnataka",   pincode: 560034 }, active: true },
    { _id: 112, name: "Meera",  email: "meera@example.com",  departmentId: 5, salary: 58000, hireDate: ISODate("2024-01-08"), managerId: 107,
                                                    address: { city: "Mumbai",    state: "Maharashtra", pincode: 400001 }, active: false }   // NO skills field, inactive
]);

/* ---------- 3. customers (8) ---------- */
db.customers.insertMany([
    { _id: 1, name: "Aarav Sharma", email: "aarav@example.com",  city: "Delhi",     createdDate: ISODate("2024-11-05"), tags: ["vip", "early-adopter"] },
    { _id: 2, name: "Bhavna Mehta", email: "bhavna@example.com", city: "Mumbai",    createdDate: ISODate("2024-12-12"), tags: ["vip"] },
    { _id: 3, name: "Chirag Patel", email: "chirag@example.com", city: "Delhi",     createdDate: ISODate("2025-01-08"), tags: [] },
    { _id: 4, name: "Divya Nair",   email: "divya@example.com",  city: "Pune",      createdDate: ISODate("2025-01-25"), tags: ["newsletter"] },
    { _id: 5, name: "Esha Kapoor",  email: "esha@example.com",   city: "Bangalore", createdDate: ISODate("2025-02-10"), tags: ["vip", "newsletter"] },
    { _id: 6, name: "Farhan Ali",   email: null,                 city: "Mumbai",    createdDate: ISODate("2025-03-01") },                        // email: null, no tags
    { _id: 7, name: "Gaurav Singh", email: "gaurav@example.com", city: "Chennai",   createdDate: ISODate("2025-04-20"), tags: ["newsletter"] },
    { _id: 8, name: "Hina Khan",                                 city: "Delhi",     createdDate: ISODate("2025-06-15") }                         // NO email field, no tags, no orders
]);

/* ---------- 4. products (11) ---------- */
db.products.insertMany([
    { _id: 1,  name: "Laptop",     category: "Electronics", price: 75000, stock: 10,   tags: ["computer", "portable"],    ratings: [5, 4, 5] },
    { _id: 2,  name: "Mouse",      category: "Electronics", price: 1000,  stock: 100,  tags: ["accessory"],               ratings: [4, 4] },
    { _id: 3,  name: "Keyboard",   category: "Electronics", price: 2500,  stock: 50,   tags: ["accessory"],               ratings: [3, 4, 5] },
    { _id: 4,  name: "Chair",      category: "Furniture",   price: 8000,  stock: 20,   tags: ["office", "ergonomic"],     ratings: [4] },
    { _id: 5,  name: "Desk",       category: "Furniture",   price: 15000, stock: 15,   tags: ["office"],                  ratings: [] },
    { _id: 6,  name: "Monitor",    category: "Electronics", price: 25000, stock: 25,   tags: ["computer", "display"],     ratings: [5, 5, 4] },
    { _id: 7,  name: "Notebook",   category: "Stationery",  price: 50,    stock: 500,  tags: ["paper"] },                                        // no ratings field
    { _id: 8,  name: "Pen",        category: "Stationery",  price: 10,    stock: 1000, tags: ["writing"],                 ratings: [3] },
    { _id: 9,  name: "Headphones", category: "Electronics", price: 3000,  stock: 0,    tags: ["audio", "accessory"],      ratings: [2, 3] },      // out of stock
    { _id: 10, name: "Bookshelf",  category: "Furniture",   price: 12000, stock: 5,    tags: ["office", "storage"],       ratings: [4, 4, 4] },
    { _id: 11, name: "Webcam",     category: "Electronics", price: 4500,  stock: 30,   tags: ["computer", "accessory"],   ratings: [] }           // never ordered
]);

/* ---------- 5. orders (19)  Jan -> Sep 2025 ---------- */
/* items = the order lines (OrderDetails in SQL) embedded as an array.
   totalAmount always equals the sum of qty * unitPrice.                   */
db.orders.insertMany([
    { _id: 1001, customerId: 1, employeeId: 103,  orderDate: ISODate("2025-01-05"), status: "Completed", totalAmount: 75000,
      items: [ { productId: 1, qty: 1, unitPrice: 75000 } ],                                                           payment: { method: "Card", paid: true } },
    { _id: 1002, customerId: 2, employeeId: 104,  orderDate: ISODate("2025-01-12"), status: "Completed", totalAmount: 10000,
      items: [ { productId: 4, qty: 1, unitPrice: 8000 }, { productId: 2, qty: 2, unitPrice: 1000 } ],                 payment: { method: "UPI",  paid: true } },
    { _id: 1003, customerId: 3, employeeId: 103,  orderDate: ISODate("2025-01-20"), status: "Completed", totalAmount: 25000,
      items: [ { productId: 6, qty: 1, unitPrice: 25000 } ],                                                           payment: { method: "Card", paid: true } },
    { _id: 1004, customerId: 1, employeeId: 104,  orderDate: ISODate("2025-02-03"), status: "Completed", totalAmount: 15000,
      items: [ { productId: 5, qty: 1, unitPrice: 15000 } ],                                                           payment: { method: "COD",  paid: true } },
    { _id: 1005, customerId: 4, employeeId: 103,  orderDate: ISODate("2025-02-14"), status: "Completed", totalAmount: 50000,
      items: [ { productId: 6, qty: 2, unitPrice: 25000 } ],                                                           payment: { method: "Card", paid: true } },
    { _id: 1006, customerId: 5, employeeId: 104,  orderDate: ISODate("2025-02-28"), status: "Cancelled", totalAmount: 8000,
      items: [ { productId: 4, qty: 1, unitPrice: 8000 } ],                                                            payment: { method: "UPI",  paid: false } },
    { _id: 1007, customerId: 2, employeeId: 109,  orderDate: ISODate("2025-03-10"), status: "Completed", totalAmount: 6000,
      items: [ { productId: 3, qty: 2, unitPrice: 2500 }, { productId: 2, qty: 1, unitPrice: 1000 } ],                 payment: { method: "UPI",  paid: true } },
    { _id: 1008, customerId: 6, employeeId: 109,  orderDate: ISODate("2025-03-18"), status: "Completed", totalAmount: 78500,
      items: [ { productId: 1, qty: 1, unitPrice: 75000 }, { productId: 2, qty: 1, unitPrice: 1000 }, { productId: 3, qty: 1, unitPrice: 2500 } ],
                                                                                                                       payment: { method: "Card", paid: true } },
    { _id: 1009, customerId: 1, employeeId: 103,  orderDate: ISODate("2025-04-02"), status: "Completed", totalAmount: 6000,
      items: [ { productId: 9, qty: 2, unitPrice: 3000 } ],                                                            payment: { method: "COD",  paid: true } },
    { _id: 1010, customerId: 3, employeeId: 104,  orderDate: ISODate("2025-04-15"), status: "Completed", totalAmount: 1500,
      items: [ { productId: 7, qty: 20, unitPrice: 50 }, { productId: 8, qty: 50, unitPrice: 10 } ],                   payment: { method: "UPI",  paid: true } },
    { _id: 1011, customerId: 7, employeeId: 109,  orderDate: ISODate("2025-05-06"), status: "Completed", totalAmount: 12000,
      items: [ { productId: 10, qty: 1, unitPrice: 12000 } ],                                                          payment: { method: "Card", paid: true } },
    { _id: 1012, customerId: 2, employeeId: 103,  orderDate: ISODate("2025-05-21"), status: "Completed", totalAmount: 30000,
      items: [ { productId: 5, qty: 2, unitPrice: 15000 } ],                                                           payment: { method: "Card", paid: true } },
    { _id: 1013, customerId: 4, employeeId: 104,  orderDate: ISODate("2025-06-01"), status: "Completed", totalAmount: 27500,
      items: [ { productId: 6, qty: 1, unitPrice: 25000 }, { productId: 3, qty: 1, unitPrice: 2500 } ],                payment: { method: "UPI",  paid: true } },
    { _id: 1014, customerId: 5, employeeId: 109,  orderDate: ISODate("2025-06-19"), status: "Completed", totalAmount: 150000,
      items: [ { productId: 1, qty: 2, unitPrice: 75000 } ],                                                           payment: { method: "Card", paid: true } },
    { _id: 1015, customerId: 1, employeeId: 103,  orderDate: ISODate("2025-07-07"), status: "Pending",   totalAmount: 32000,
      items: [ { productId: 4, qty: 4, unitPrice: 8000 } ],                                                            payment: { method: "COD",  paid: false } },
    { _id: 1016, customerId: 6, employeeId: 104,  orderDate: ISODate("2025-07-25"), status: "Completed", totalAmount: 10000,
      items: [ { productId: 2, qty: 10, unitPrice: 1000 } ],                                                           payment: { method: "UPI",  paid: true } },
    { _id: 1017, customerId: 3, employeeId: 109,  orderDate: ISODate("2025-08-09"), status: "Pending",   totalAmount: 4000,
      items: [ { productId: 9, qty: 1, unitPrice: 3000 }, { productId: 8, qty: 100, unitPrice: 10 } ],                 payment: { method: "COD",  paid: false } },
    { _id: 1018, customerId: 7, employeeId: 103,  orderDate: ISODate("2025-08-30"), status: "Completed", totalAmount: 75000,
      items: [ { productId: 6, qty: 3, unitPrice: 25000 } ],                                                           payment: { method: "Card", paid: true } },
    { _id: 1019, customerId: 2, employeeId: null, orderDate: ISODate("2025-09-05"), status: "Completed", totalAmount: 2500,
      items: [ { productId: 3, qty: 1, unitPrice: 2500 } ],                                                            payment: { method: "UPI",  paid: true } }   // online order: no salesperson
]);

/* ---------- Verify document counts ---------- */
print("Document counts:");
["departments", "employees", "customers", "products", "orders"].forEach(c =>
    print("  " + c.padEnd(12) + db[c].countDocuments())
);
// expect: departments 6, employees 12, customers 8, products 11, orders 19

/* ---------- Sanity check: every order total = sum of its lines ---------- */
const mismatches = db.orders.aggregate([
    { $project: { totalAmount: 1,
                  lineTotal: { $sum: { $map: { input: "$items", as: "i", in: { $multiply: ["$$i.qty", "$$i.unitPrice"] } } } } } },
    { $match: { $expr: { $ne: ["$totalAmount", "$lineTotal"] } } }
]).toArray();
print("Orders whose total <> sum of lines:", mismatches.length);   // expect 0
