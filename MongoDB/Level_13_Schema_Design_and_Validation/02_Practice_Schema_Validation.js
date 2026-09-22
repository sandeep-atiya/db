/* ============================================================
   LEVEL 13 - SCHEMA VALIDATION  |  02_Practice_Schema_Validation.js
   ------------------------------------------------------------
   Topics : $jsonSchema (types, required, enum, min/max, pattern,
            arrays, nested objects, additionalProperties), reading
            validation errors, updates vs validation, numeric type
            traps, query-operator validators ($expr), collMod,
            validationLevel / validationAction, bypass, finding
            existing documents that violate a schema

   HOW TO PRACTICE: block by block, predict first.
   Creates l13_employees_v / l13_orders_v (dropped in CLEANUP).
   ============================================================ */

use("companyDB");
db.l13_employees_v.drop();


/* ============================================================
   1. A VALIDATED COLLECTION
   ============================================================ */

const employeeSchema = {
    bsonType: "object",
    title: "Employee",
    required: ["_id", "name", "salary", "departmentId", "hireDate"],
    properties: {
        _id:          { bsonType: "int", minimum: 100, description: "numeric employee id >= 100" },
        name:         { bsonType: "string", minLength: 2, maxLength: 50 },
        email:        { bsonType: "string", pattern: "^[^@\\s]+@[^@\\s]+\\.[a-z]{2,}$" },
        departmentId: { bsonType: ["int", "null"] },
        salary:       { bsonType: ["int", "long", "double", "decimal"], minimum: 1, maximum: 1000000 },
        hireDate:     { bsonType: "date" },
        active:       { bsonType: "bool" },
        status:       { enum: ["active", "on-leave", "left"] },
        skills:       { bsonType: "array", items: { bsonType: "string" }, uniqueItems: true, maxItems: 20 },
        address:      { bsonType: "object", required: ["city"], properties: { city: { bsonType: "string" }, state: { bsonType: "string" }, pincode: { bsonType: "int", minimum: 100000, maximum: 999999 } }, additionalProperties: false },
        managerId:    { bsonType: ["int", "null"] }
    },
    additionalProperties: false                            // nothing outside this list (so every allowed field must be declared, including _id)
};
db.createCollection("l13_employees_v", { validator: { $jsonSchema: employeeSchema }, validationLevel: "strict", validationAction: "error" });

// A valid document
db.l13_employees_v.insertOne({ _id: 201, name: "Isha", email: "isha@example.com", departmentId: 3, salary: 52000, hireDate: ISODate("2025-01-15"), active: true, status: "active",
                              skills: ["Recruiting"], address: { city: "Delhi", state: "Delhi", pincode: 110001 }, managerId: 105 });


/* ============================================================
   2. READING A VALIDATION ERROR
   ============================================================ */

function tryInsert(doc) {
    try {
        db.l13_employees_v.insertOne(doc);
        print("inserted", doc._id);
    } catch (e) {
        const d = e.errInfo && e.errInfo.details;
        const rules = d && d.schemaRulesNotSatisfied ? d.schemaRulesNotSatisfied.map(r => r.operatorName + (r.propertiesNotSatisfied ? ":" + r.propertiesNotSatisfied.map(p => p.propertyName).join(",") : r.missingProperties ? ":" + r.missingProperties.join(",") : "")) : [];
        print("EXPECTED ERROR:", e.message, "->", rules.join(" | "));
    }
}
tryInsert({ _id: 202, name: "X", salary: 1000, departmentId: 1, hireDate: new Date() });                                 // name too short -> properties:name
tryInsert({ _id: 203, name: "NoSalary", departmentId: 1, hireDate: new Date() });                                        // required:salary
tryInsert({ _id: 204, name: "BadMail", email: "not-an-email", salary: 1000, departmentId: 1, hireDate: new Date() });    // pattern
tryInsert({ _id: 205, name: "Status", status: "fired", salary: 1000, departmentId: 1, hireDate: new Date() });           // enum
tryInsert({ _id: 206, name: "Extra", nickname: "Ex", salary: 1000, departmentId: 1, hireDate: new Date() });             // additionalProperties
tryInsert({ _id: 207, name: "Dup", skills: ["SQL", "SQL"], salary: 1000, departmentId: 1, hireDate: new Date() });       // uniqueItems
tryInsert({ _id: 208, name: "Addr", address: { state: "Delhi" }, salary: 1000, departmentId: 1, hireDate: new Date() }); // nested required city
tryInsert({ _id: 209, name: "StrDate", salary: 1000, departmentId: 1, hireDate: "2025-01-01" });                          // date as string
tryInsert({ _id: "E210", name: "StrId", salary: 1000, departmentId: 1, hireDate: new Date() });                          // _id must be int
db.l13_employees_v.countDocuments();                       // still 1


/* ============================================================
   3. THE NUMERIC TYPE TRAP
   ============================================================ */

tryInsert({ _id: 210, name: "Half", salary: 52000.5, departmentId: 1, hireDate: new Date() });          // ok: double is in the salary list
tryInsert({ _id: 211, name: "Dept", salary: 1000, departmentId: 1.5, hireDate: new Date() });           // departmentId is "int" | "null" -> 1.5 rejected
tryInsert({ _id: 212.0, name: "IdDouble", salary: 1000, departmentId: 1, hireDate: new Date() });       // 212.0 is stored as int by mongosh -> ok
tryInsert({ _id: NumberLong(213), name: "IdLong", salary: 1000, departmentId: 1, hireDate: new Date() });   // long is NOT int -> rejected
// Lesson: list every numeric type you accept ([ "int", "long", "double", "decimal" ]) or use bsonType: "number".


/* ============================================================
   4. UPDATES ARE VALIDATED TOO  (strict)
   ============================================================ */

try {
    db.l13_employees_v.updateOne({ _id: 201 }, { $set: { salary: -5 } });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                    // Document failed validation (minimum)
}
try {
    db.l13_employees_v.updateOne({ _id: 201 }, { $unset: { salary: "" } });
} catch (e) {
    print("EXPECTED ERROR:", e.message);                    // removing a required field
}
db.l13_employees_v.updateOne({ _id: 201 }, { $set: { salary: 55000 } });   // fine
// Validation does NOT check uniqueness or references -> unique indexes + application logic:
db.l13_employees_v.createIndex({ email: 1 }, { unique: true, partialFilterExpression: { email: { $type: "string" } } });


/* ============================================================
   5. QUERY-OPERATOR VALIDATORS  (rules between fields)
   ============================================================ */

db.l13_orders_v.drop();
db.createCollection("l13_orders_v", { validator: {
    $and: [
        { $jsonSchema: { bsonType: "object", required: ["customerId", "items", "totalAmount", "status"],
                         properties: { status: { enum: ["Pending", "Completed", "Cancelled"] },
                                       items: { bsonType: "array", minItems: 1, items: { bsonType: "object", required: ["productId", "qty", "unitPrice"],
                                                properties: { qty: { bsonType: "int", minimum: 1 }, unitPrice: { bsonType: "number", minimum: 0 } } } } } } },
        // totalAmount must equal the sum of the lines ($expr can compare / compute across fields)
        { $expr: { $eq: [ "$totalAmount", { $sum: { $map: { input: "$items", as: "i", in: { $multiply: ["$$i.qty", "$$i.unitPrice"] } } } } ] } },
        // a Cancelled order cannot be marked paid
        { $nor: [ { status: "Cancelled", "payment.paid": true } ] }
    ]
} });
db.l13_orders_v.insertOne({ _id: 1, customerId: 1, status: "Pending", items: [ { productId: 2, qty: 2, unitPrice: 1000 } ], totalAmount: 2000, payment: { paid: false } });   // ok
try {
    db.l13_orders_v.insertOne({ _id: 2, customerId: 1, status: "Pending", items: [ { productId: 2, qty: 2, unitPrice: 1000 } ], totalAmount: 1999 });
} catch (e) { print("EXPECTED ERROR: total mismatch ->", e.message); }
try {
    db.l13_orders_v.insertOne({ _id: 3, customerId: 1, status: "Cancelled", items: [ { productId: 2, qty: 1, unitPrice: 1000 } ], totalAmount: 1000, payment: { paid: true } });
} catch (e) { print("EXPECTED ERROR: cancelled but paid ->", e.message); }
try {
    db.l13_orders_v.insertOne({ _id: 4, customerId: 1, status: "Pending", items: [], totalAmount: 0 });
} catch (e) { print("EXPECTED ERROR: empty items ->", e.message); }


/* ============================================================
   6. ADDING VALIDATION TO AN EXISTING COLLECTION  (collMod, levels, actions)
   ============================================================ */

// A collection with data that does NOT all satisfy the new rule
db.l13_legacy.drop();
db.l13_legacy.insertMany([ { _id: 1, name: "ok", age: 30 }, { _id: 2, name: "bad", age: "thirty" }, { _id: 3, name: "bad2" } ]);

// Add the validator with collMod. Existing documents are NOT checked at this moment.
db.runCommand({ collMod: "l13_legacy", validator: { $jsonSchema: { bsonType: "object", required: ["age"], properties: { age: { bsonType: "int", minimum: 0 } } } }, validationLevel: "strict", validationAction: "error" });
db.getCollectionInfos({ name: "l13_legacy" })[0].options;   // validator, validationLevel, validationAction

// strict: updating an already-invalid document fails unless the update fixes it
try {
    db.l13_legacy.updateOne({ _id: 2 }, { $set: { name: "bad-renamed" } });
} catch (e) { print("EXPECTED ERROR (strict):", e.message); }
db.l13_legacy.updateOne({ _id: 2 }, { $set: { age: 30 } });   // fixing it is allowed

// moderate: documents that are ALREADY invalid are left alone on update (lets you migrate gradually)
db.runCommand({ collMod: "l13_legacy", validationLevel: "moderate" });
db.l13_legacy.updateOne({ _id: 3 }, { $set: { name: "still-bad-but-allowed" } });   // ok: _id 3 was invalid before, moderate skips it
try {
    db.l13_legacy.insertOne({ _id: 4, name: "new", age: "x" });                       // new documents are still validated
} catch (e) { print("EXPECTED ERROR (moderate still validates inserts):", e.message); }

// warn: log a warning in mongod.log, but ACCEPT the write - the way to test a validator in production first
db.runCommand({ collMod: "l13_legacy", validationAction: "warn", validationLevel: "strict" });
db.l13_legacy.insertOne({ _id: 5, name: "accepted-with-warning", age: "x" });        // inserted!
db.l13_legacy.countDocuments();                            // 4


/* ============================================================
   7. FINDING THE DOCUMENTS THAT VIOLATE A SCHEMA  ($jsonSchema as a QUERY operator)
   ============================================================ */

const legacySchema = { bsonType: "object", required: ["age"], properties: { age: { bsonType: "int", minimum: 0 } } };
db.l13_legacy.find({ $nor: [ { $jsonSchema: legacySchema } ] }, { _id: 1, age: 1 });   // 3 (missing age), 5 ("x")
db.l13_legacy.find({ $jsonSchema: legacySchema }).count();                            // 2 valid
// Same trick on the real employees collection with the schema from section 1:
db.employees.find({ $nor: [ { $jsonSchema: employeeSchema } ] }, { _id: 1 }).count();   // 0 - the base data satisfies the whole schema
db.employees.find({ $jsonSchema: { required: ["email"] } }).count();                    // 11 (Anjali has no email)
// -> a cheap way to audit a collection BEFORE switching a validator on (or to find documents to migrate).


/* ============================================================
   8. BYPASSING AND REMOVING VALIDATION
   ============================================================ */

db.runCommand({ collMod: "l13_legacy", validationAction: "error" });
db.l13_legacy.insertOne({ _id: 6, name: "migration-load", age: "unknown" }, { bypassDocumentValidation: true });   // needs the bypassDocumentValidation privilege
db.runCommand({ collMod: "l13_legacy", validator: {} });    // remove the validator entirely
db.getCollectionInfos({ name: "l13_legacy" })[0].options;   // {}


/* ============================================================
   CLEANUP
   ============================================================ */
db.l13_employees_v.drop(); db.l13_orders_v.drop(); db.l13_legacy.drop();

/* ------------------------------------------------------------
   DONE. Next: Exercises.js
   ------------------------------------------------------------ */
