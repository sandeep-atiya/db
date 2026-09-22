/* ============================================================
   LEVEL 13 - SCHEMA DESIGN & VALIDATION  |  Exercises.js
   ------------------------------------------------------------
   Try each question in the "YOUR ANSWER" area FIRST.
   Then scroll down to SOLUTIONS and compare.
   Design questions have a written answer; coding questions use
   l13_ex_* collections (dropped at the end).
   ============================================================ */

use("companyDB");

/* ------------------------------------------------------------
   QUESTIONS
   ------------------------------------------------------------
   Q1.  (Design) A blog: posts have an author, up to ~50 comments, and tags. Each
        author writes thousands of posts. Where do author, comments and tags go?
   Q2.  (Design) A hotel booking app: rooms, guests, bookings (a booking has 1 room,
        1 guest, dates, price). What do you embed, what do you reference, and which
        fields would you copy into the booking (extended reference)?
   Q3.  (Design) An IoT platform stores 1 reading per second per device for 10 000
        devices. Why is one document per reading a problem? Give two solutions.
   Q4.  (Design) Product catalog: 2000 products with wildly different attributes
        (RAM for laptops, colour for chairs). Which pattern keeps queries indexable?
   Q5.  Build l13_ex_carts using the SUBSET idea: a cart document with the last 3
        items embedded (recentItems, capped with $slice) and every item also in
        l13_ex_cart_items. Add 5 items and show both.
   Q6.  Build l13_ex_customers with a COMPUTED field orderCount and totalSpent
        loaded from companyDB.orders with $merge. Then simulate a new order of 999
        for customer 8 with one atomic update.
   Q7.  Model employees <-> projects (many:many) with the array on the PROJECT side
        only, in l13_ex_projects. Write the two queries: projects of employee 111,
        members (names!) of project "Audit".
   Q8.  Create l13_ex_products with a validator: name (string, required), price
        (number >= 0, required), category (enum Electronics/Furniture/Stationery),
        tags (array of unique strings, max 5). Insert one valid and three invalid
        documents (one per rule) inside try/catch.
   Q9.  Add a validator to a copy of companyDB.customers (l13_ex_customers2)
        requiring email to be a string, using validationLevel "moderate". Show that
        updating Farhan's (email null) city still works, but inserting a customer
        without email fails.
   Q10. Using $jsonSchema as a QUERY, list the customers that would violate the
        Q9 rule.
   Q11. Create a time series collection l13_ex_temps (timeField ts, metaField room)
        and insert 3 readings; then group by room with $avg.
   Q12. (Think) When would you deliberately store the same product name in every
        order line instead of looking it up? What is the risk and how is it managed?
   ------------------------------------------------------------ */

// YOUR ANSWERS HERE (write below, run, compare)










/* ============================================================
   SOLUTIONS
   ============================================------------- */

// Q1
// author: REFERENCE (authorId) + extended reference (authorName, maybe avatar) on the post - authors write thousands of posts,
//         and an author profile is edited independently. comments: EMBED (bounded ~50, read with the post) - or subset
//         (latest N embedded + comments collection) if they could grow. tags: EMBED an array of strings (multikey index).

// Q2
// rooms, guests: own collections (shared, independently updated). bookings: own collection referencing roomId and guestId,
// with an EXTENDED REFERENCE copy of roomNumber/roomType and guestName (what every booking screen shows) and the price AT
// BOOKING TIME (must not change when the room price changes). Never embed bookings inside the room or the guest (unbounded).

// Q3
// 864 million documents per day -> index size, RAM, insert overhead, and range scans over billions of tiny docs.
// Solutions: (1) bucket pattern - one document per device per minute/hour with an array of readings + min/max/avg;
//            (2) a time series collection (server-managed buckets, columnar compression, TTL via expireAfterSeconds).

// Q4
// Attribute pattern: specs: [ { k: "ram", v: "16GB" }, { k: "colour", v: "black" } ] with a single index on { "specs.k": 1, "specs.v": 1 }
// (or a wildcard index on a specs sub-document if you must keep keys as field names).

// Q5
db.l13_ex_carts.drop(); db.l13_ex_cart_items.drop();
db.l13_ex_carts.insertOne({ _id: "cart-1", customerId: 1, recentItems: [] });
for (let i = 1; i <= 5; i++) {
    const item = { cartId: "cart-1", productId: i, qty: 1, addedAt: new Date(Date.now() + i * 1000) };
    db.l13_ex_cart_items.insertOne(item);
    db.l13_ex_carts.updateOne({ _id: "cart-1" }, { $push: { recentItems: { $each: [ { productId: i, addedAt: item.addedAt } ], $slice: -3 } } });
}
db.l13_ex_carts.findOne();                                 // recentItems: products 3, 4, 5
db.l13_ex_cart_items.countDocuments({ cartId: "cart-1" }); // 5

// Q6
db.l13_ex_customers.drop();
db.customers.aggregate([ { $project: { name: 1 } }, { $out: "l13_ex_customers" } ]);
db.orders.aggregate([
    { $group: { _id: "$customerId", orderCount: { $sum: 1 }, totalSpent: { $sum: "$totalAmount" } } },
    { $merge: { into: "l13_ex_customers", on: "_id", whenMatched: "merge", whenNotMatched: "discard" } }
]);
db.l13_ex_customers.updateOne({ _id: 8 }, { $inc: { orderCount: 1, totalSpent: 999 } });   // Hina's first order
db.l13_ex_customers.find({ _id: { $in: [1, 8] } });      // 1: 4 / 128000 ; 8: 1 / 999

// Q7
db.l13_ex_projects.drop();
db.l13_ex_projects.insertMany([
    { _id: "Migration", memberIds: [101, 108, 111] },
    { _id: "Audit",     memberIds: [106, 111] }
]);
db.l13_ex_projects.createIndex({ memberIds: 1 });
db.l13_ex_projects.find({ memberIds: 111 }, { _id: 1 });   // Migration, Audit
db.l13_ex_projects.aggregate([ { $match: { _id: "Audit" } }, { $lookup: { from: "employees", localField: "memberIds", foreignField: "_id", as: "m" } }, { $project: { members: "$m.name" } } ]);   // Sneha, Deepak

// Q8
db.l13_ex_products.drop();
db.createCollection("l13_ex_products", { validator: { $jsonSchema: {
    bsonType: "object", required: ["name", "price"],
    properties: {
        name: { bsonType: "string" },
        price: { bsonType: "number", minimum: 0 },
        category: { enum: ["Electronics", "Furniture", "Stationery"] },
        tags: { bsonType: "array", items: { bsonType: "string" }, uniqueItems: true, maxItems: 5 }
    } } } });
db.l13_ex_products.insertOne({ name: "Lamp", price: 1200, category: "Furniture", tags: ["office"] });
[ { name: "NoPrice" }, { name: "Neg", price: -1 }, { name: "BadCat", price: 1, category: "Toys" }, { name: "Tags", price: 1, tags: ["a", "a"] } ].forEach(d => {
    try { db.l13_ex_products.insertOne(d); } catch (e) { print("EXPECTED ERROR:", d.name, "->", e.errInfo.details.schemaRulesNotSatisfied[0].operatorName); }
});

// Q9
db.l13_ex_customers2.drop();
db.customers.aggregate([ { $out: "l13_ex_customers2" } ]);
db.runCommand({ collMod: "l13_ex_customers2", validator: { $jsonSchema: { required: ["email"], properties: { email: { bsonType: "string" } } } }, validationLevel: "moderate" });
db.l13_ex_customers2.updateOne({ _id: 6 }, { $set: { city: "Thane" } });   // Farhan (email null) is already invalid -> moderate lets the update through
try { db.l13_ex_customers2.insertOne({ _id: 9, name: "No Mail" }); } catch (e) { print("EXPECTED ERROR:", e.message); }

// Q10
db.l13_ex_customers2.find({ $nor: [ { $jsonSchema: { required: ["email"], properties: { email: { bsonType: "string" } } } } ] }, { name: 1, email: 1 });   // Farhan, Hina

// Q11
db.l13_ex_temps.drop();
db.createCollection("l13_ex_temps", { timeseries: { timeField: "ts", metaField: "room" } });
db.l13_ex_temps.insertMany([ { ts: new Date(), room: "A", temp: 21 }, { ts: new Date(), room: "A", temp: 23 }, { ts: new Date(), room: "B", temp: 19 } ]);
db.l13_ex_temps.aggregate([ { $group: { _id: "$room", avg: { $avg: "$temp" } } }, { $sort: { _id: 1 } } ]);   // A 22, B 19

// Q12
// When the order must show what was sold AS IT WAS (name, price at that time) and reads vastly outnumber writes: it removes a
// $lookup from the hottest page. Risk: staleness / inconsistency when the product is renamed. Managed by deciding that the copy
// is a historical snapshot (correct for orders), or by fanning out updates (updateMany / change stream) when it must follow the master.

["l13_ex_carts", "l13_ex_cart_items", "l13_ex_customers", "l13_ex_projects", "l13_ex_products", "l13_ex_customers2", "l13_ex_temps"].forEach(c => db[c].drop());
