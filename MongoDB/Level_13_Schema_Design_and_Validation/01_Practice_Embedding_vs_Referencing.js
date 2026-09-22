/* ============================================================
   LEVEL 13 - SCHEMA DESIGN  |  01_Practice_Embedding_vs_Referencing.js
   ------------------------------------------------------------
   Topics : embedded vs referenced models side by side, 1:1, 1:few,
            1:many, 1:squillions, many:many, extended reference,
            computed, subset, bucket, attribute, polymorphic,
            schema versioning, tree patterns, time series collections

   HOW TO PRACTICE: block by block, predict first.
   Creates l13_* collections (dropped in CLEANUP).
   ============================================================ */

use("companyDB");


/* ============================================================
   1. THE SAME ORDER, TWO MODELS
   ============================================================ */

// REFERENCED (what companyDB.orders is): ids only -> a $lookup per read
db.orders.findOne({ _id: 1008 });

// EMBEDDED / DENORMALISED: build it once from the base collections ($lookup + $out) - what an order-history page would want
db.orders.aggregate([
    { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "c" } },
    { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "p" } },
    { $set: { "items.name": { $first: "$p.name" }, "items.category": { $first: "$p.category" } } },
    { $group: { _id: "$_id", doc: { $first: "$$ROOT" }, items: { $push: "$items" } } },
    { $replaceWith: { $mergeObjects: [ "$doc", { items: "$items" } ] } },
    { $set: { customer: { _id: { $first: "$c._id" }, name: { $first: "$c.name" }, city: { $first: "$c.city" } } } },
    { $unset: ["p", "c", "customerId", "items.p"] },
    { $out: "l13_orders_embedded" }
]);
db.l13_orders_embedded.findOne({ _id: 1008 });
// One read renders the whole order. Price: the customer name / city and product names are COPIES (extended reference) that can go stale.

// Reading "orders of customer 6 with product names": embedded = one query; referenced = pipeline with 2 lookups
db.l13_orders_embedded.find({ "customer._id": 6 }, { _id: 1, "items.name": 1, totalAmount: 1 });
db.orders.aggregate([ { $match: { customerId: 6 } }, { $unwind: "$items" },
    { $lookup: { from: "products", localField: "items.productId", foreignField: "_id", as: "p" } },
    { $group: { _id: "$_id", totalAmount: { $first: "$totalAmount" }, items: { $push: { $first: "$p.name" } } } } ]);


/* ============================================================
   2. 1:1 and 1:FEW -> EMBED   |   1:MANY -> REFERENCE FROM THE CHILD
   ============================================================ */

// 1:1 address, 1:few skills - already embedded in employees: atomic updates, one read
db.employees.updateOne({ _id: 101 }, { $set: { "address.city": "Delhi" }, $addToSet: { skills: "Docker" } });   // one atomic write
db.employees.updateOne({ _id: 101 }, { $pull: { skills: "Docker" } });                                        // (undo)

// 1:many customer -> orders: the CHILD holds the reference + an index on it (never an ever-growing array on the customer)
db.orders.find({ customerId: 1 }, { _id: 1 });                                                                 // index on customerId makes this cheap (Level 11)


/* ============================================================
   3. THE UNBOUNDED ARRAY ANTI-PATTERN  (1:squillions)
   ============================================================ */

// Wrong: every login event pushed into the employee document
db.l13_emp_bad.drop();
db.l13_emp_bad.insertOne({ _id: 101, name: "Rahul", logins: [] });
for (let i = 0; i < 2000; i++) db.l13_emp_bad.updateOne({ _id: 101 }, { $push: { logins: { at: new Date(), ip: "10.0.0." + (i % 255), ua: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome" } } });
bsonsize(db.l13_emp_bad.findOne({ _id: 101 }));            // ~200 KB after 2000 logins -> 16 MB after ~160k; every $push rewrites the whole document
// Right: one document per event, referencing the employee, indexed by (employeeId, at) - and a TTL index if events expire
db.l13_logins.drop();
db.l13_logins.createIndex({ employeeId: 1, at: -1 });
const logins = db.l13_logins.insertMany(Array.from({ length: 2000 }, (_, i) => ({ employeeId: 101, at: new Date(Date.now() - i * 60000), ip: "10.0.0." + (i % 255) })));
Object.keys(logins.insertedIds).length;                                                                       // 2000 small documents
db.l13_logins.find({ employeeId: 101 }).sort({ at: -1 }).limit(3);                                            // last 3 logins: index seek, no giant document


/* ============================================================
   4. MANY-TO-MANY: arrays of references
   ============================================================ */

db.l13_projects.drop(); db.l13_emp_proj.drop();
db.l13_projects.insertMany([
    { _id: 1, name: "Data Migration", memberIds: [101, 108, 111] },
    { _id: 2, name: "Website Revamp", memberIds: [102, 107] },
    { _id: 3, name: "Audit 2025",     memberIds: [106, 111] }
]);
db.employees.aggregate([ { $project: { name: 1 } }, { $out: "l13_emp_proj" } ]);
db.l13_emp_proj.updateMany({ _id: { $in: [101, 108, 111] } }, { $addToSet: { projectIds: 1 } });
db.l13_emp_proj.updateMany({ _id: { $in: [102, 107] } }, { $addToSet: { projectIds: 2 } });
db.l13_emp_proj.updateMany({ _id: { $in: [106, 111] } }, { $addToSet: { projectIds: 3 } });

db.l13_projects.find({ memberIds: 111 }, { name: 1 });                           // projects of Deepak (multikey index on memberIds in real life)
db.l13_emp_proj.find({ projectIds: 1 }, { name: 1 });                            // members of project 1 - either side answers, pick the side you query most
db.l13_projects.aggregate([ { $match: { _id: 1 } }, { $lookup: { from: "l13_emp_proj", localField: "memberIds", foreignField: "_id", as: "members" } }, { $project: { name: 1, "members.name": 1 } } ]);
// Keeping BOTH sides in sync = two writes -> wrap in a transaction (Level 14), or store the array on one side only.
// Link data (role, joinedAt)? -> a separate l13_memberships collection { employeeId, projectId, role } like a SQL link table.


/* ============================================================
   5. EXTENDED REFERENCE and keeping copies fresh
   ============================================================ */

db.l13_orders_embedded.findOne({ _id: 1001 }, { customer: 1 });                  // { _id: 1, name: 'Aarav Sharma', city: 'Delhi' }
// The customer moves. The master record changes ...
db.customers.updateOne({ _id: 1 }, { $set: { city: "Gurgaon" } });
db.l13_orders_embedded.findOne({ _id: 1001 }, { "customer.city": 1 });          // ... the copy is now STALE: still Delhi
// Options: (a) accept it (city AT THE TIME of the order is often what you want!),
//          (b) fan out the update:
db.l13_orders_embedded.updateMany({ "customer._id": 1 }, { $set: { "customer.city": "Gurgaon" } });   // 4 orders
//          (c) a change stream on customers that does (b) asynchronously (Level 17).
db.customers.updateOne({ _id: 1 }, { $set: { city: "Delhi" } });                 // restore master
db.l13_orders_embedded.updateMany({ "customer._id": 1 }, { $set: { "customer.city": "Delhi" } });


/* ============================================================
   6. COMPUTED PATTERN  (pre-aggregate on write)
   ============================================================ */

db.customers.aggregate([ { $project: { name: 1 } }, { $out: "l13_customer_stats" } ]);
// Initial load from history
db.orders.aggregate([
    { $group: { _id: "$customerId", orders: { $sum: 1 }, revenue: { $sum: "$totalAmount" }, lastOrderAt: { $max: "$orderDate" } } },
    { $merge: { into: "l13_customer_stats", on: "_id", whenMatched: "merge", whenNotMatched: "discard" } }
]);
// From now on, every new order does ONE extra atomic update instead of re-aggregating 19 (or 19 million) orders:
db.l13_customer_stats.updateOne({ _id: 8 }, { $inc: { orders: 1, revenue: 4200 }, $max: { lastOrderAt: ISODate("2025-10-01") } });
db.l13_customer_stats.find({ _id: { $in: [1, 8] } });
// Dashboard reads are O(1); the trade: two writes per order (transaction if they must be consistent) and a periodic re-sync job.


/* ============================================================
   7. SUBSET PATTERN  (recent N embedded, the rest elsewhere)
   ============================================================ */

db.l13_products.drop(); db.l13_reviews.drop();
db.l13_products.insertOne({ _id: 1, name: "Laptop", recentReviews: [] });
for (let i = 1; i <= 5; i++) {
    const r = { productId: 1, user: "u" + i, stars: 3 + (i % 3), text: "review " + i, at: new Date(Date.now() + i * 1000) };
    db.l13_reviews.insertOne(r);                                                  // full history
    db.l13_products.updateOne({ _id: 1 }, { $push: { recentReviews: { $each: [ { user: r.user, stars: r.stars, at: r.at } ], $slice: -3 } } });   // keep last 3
}
db.l13_products.findOne({ _id: 1 });                                              // 3 reviews travel with the product (product page = 1 read)
db.l13_reviews.countDocuments({ productId: 1 });                                  // 5 in the archive ("see all reviews" = another query)


/* ============================================================
   8. BUCKET PATTERN  (time series by hand)
   ============================================================ */

db.l13_readings.drop();
db.l13_readings.createIndex({ sensor: 1, day: 1, count: 1 });
function addReading(sensor, ts, value) {
    const day = new Date(Date.UTC(ts.getUTCFullYear(), ts.getUTCMonth(), ts.getUTCDate()));
    db.l13_readings.updateOne(
        { sensor: sensor, day: day, count: { $lt: 100 } },                        // an open bucket for that sensor + day
        { $push: { readings: { t: ts, v: value } }, $inc: { count: 1, sum: value }, $min: { min: value }, $max: { max: value } },
        { upsert: true }                                                           // no open bucket -> create one
    );
}
for (let m = 0; m < 250; m++) addReading("s1", new Date(Date.UTC(2025, 0, 5, 0, m)), 20 + (m % 7));
db.l13_readings.countDocuments();                                                 // 3 buckets (100 + 100 + 50) instead of 250 documents
db.l13_readings.find({ sensor: "s1" }, { _id: 0, day: 1, count: 1, min: 1, max: 1, avg: { $divide: ["$sum", "$count"] } });
// Fewer documents & index entries, pre-computed stats per bucket. "Readings between 00:30 and 00:45" = $unwind + $match on the bucket.


/* ============================================================
   9. ATTRIBUTE PATTERN  (variable specs)
   ============================================================ */

db.l13_specs.drop();
db.l13_specs.insertMany([
    { name: "Laptop",  specs: [ { k: "ram", v: "16GB" }, { k: "cpu", v: "i7" }, { k: "screen", v: 14 } ] },
    { name: "Monitor", specs: [ { k: "screen", v: 27 }, { k: "panel", v: "IPS" } ] },
    { name: "Chair",   specs: [ { k: "material", v: "mesh" }, { k: "color", v: "black" } ] }
]);
db.l13_specs.createIndex({ "specs.k": 1, "specs.v": 1 });                        // ONE index serves every attribute
db.l13_specs.find({ specs: { $elemMatch: { k: "screen", v: { $gte: 20 } } } }, { name: 1 });   // Monitor
db.l13_specs.find({ specs: { $elemMatch: { k: "color", v: "black" } } }, { name: 1 });         // Chair
// versus { ram: "16GB", cpu: "i7", screen: 14, panel: ..., material: ... } which would need an index per field (or a wildcard index).


/* ============================================================
   10. POLYMORPHIC DOCUMENTS and SCHEMA VERSIONING
   ============================================================ */

db.l13_events.drop();
db.l13_events.insertMany([
    { type: "login",    employeeId: 101, at: new Date(), ip: "10.0.0.1" },
    { type: "order",    orderId: 1001, amount: 75000, at: new Date() },
    { type: "shipment", orderId: 1001, carrier: "BlueDart", trackingNo: "BD123", at: new Date() }
]);
db.l13_events.find({ type: "shipment" });                                         // one collection, a "type" discriminator, shape per type
db.l13_events.aggregate([ { $group: { _id: "$type", n: { $sum: 1 } } } ]);

// Schema versioning: v1 stored the address as a string, v2 as an object. Both live together; readers handle both.
db.l13_people.drop();
db.l13_people.insertMany([
    { _id: 1, name: "Old Doc", address: "12 MG Road, Bangalore 560001", schemaVersion: 1 },
    { _id: 2, name: "New Doc", address: { street: "5 Park St", city: "Kolkata", pincode: 700016 }, schemaVersion: 2 }
]);
// Read both with a normalising projection ...
db.l13_people.aggregate([ { $project: { name: 1, city: { $cond: [ { $eq: ["$schemaVersion", 2] }, "$address.city", { $last: { $split: ["$address", ", "] } } ] } } } ]);
// ... and migrate lazily (whenever a v1 document is touched) or in a background batch:
db.l13_people.updateMany({ schemaVersion: 1 }, [ { $set: {
    address: { street: { $first: { $split: ["$address", ", "] } }, city: { $first: { $split: [ { $last: { $split: ["$address", ", "] } }, " " ] } } },
    schemaVersion: 2 } } ]);
db.l13_people.find({}, { _id: 0, address: 1, schemaVersion: 1 });


/* ============================================================
   11. TREES: parent reference / ancestors array / materialised path
   ============================================================ */

db.l13_categories.drop();
db.l13_categories.insertMany([
    { _id: "Electronics", parent: null,          ancestors: [],                          path: ",Electronics," },
    { _id: "Computers",   parent: "Electronics", ancestors: ["Electronics"],             path: ",Electronics,Computers," },
    { _id: "Laptops",     parent: "Computers",   ancestors: ["Electronics", "Computers"], path: ",Electronics,Computers,Laptops," },
    { _id: "Audio",       parent: "Electronics", ancestors: ["Electronics"],             path: ",Electronics,Audio," },
    { _id: "Furniture",   parent: null,          ancestors: [],                          path: ",Furniture," }
]);
// parent reference: children of a node (cheap), whole subtree needs $graphLookup
db.l13_categories.find({ parent: "Electronics" }, { _id: 1 });
db.l13_categories.aggregate([ { $match: { _id: "Electronics" } }, { $graphLookup: { from: "l13_categories", startWith: "$_id", connectFromField: "_id", connectToField: "parent", as: "subtree" } }, { $project: { subtree: "$subtree._id" } } ]);
// ancestors array: subtree in ONE query (multikey index on ancestors), and breadcrumbs for free
db.l13_categories.find({ ancestors: "Electronics" }, { _id: 1 });
db.l13_categories.findOne({ _id: "Laptops" }).ancestors;                          // breadcrumb
// materialised path: subtree with an anchored regex (index-friendly), ordered listing
db.l13_categories.find({ path: /^,Electronics,Computers,/ }, { _id: 1 }).sort({ path: 1 });


/* ============================================================
   12. TIME SERIES COLLECTIONS  (buckets managed by the server, 5.0+)
   ============================================================ */

db.l13_ts.drop();
db.createCollection("l13_ts", { timeseries: { timeField: "ts", metaField: "sensor", granularity: "minutes" }, expireAfterSeconds: 86400 * 30 });
const tsIns = db.l13_ts.insertMany(Array.from({ length: 300 }, (_, i) => ({ ts: new Date(Date.now() - i * 60000), sensor: { id: "s1", site: "Delhi" }, temp: 20 + (i % 9) })));
Object.keys(tsIns.insertedIds).length;                                           // 300
db.l13_ts.countDocuments();                                                       // 300 measurements ...
db.getCollectionInfos({ name: "l13_ts" })[0].type;                                // 'timeseries'
db.l13_ts.aggregate([ { $group: { _id: { $dateTrunc: { date: "$ts", unit: "hour" } }, avgTemp: { $avg: "$temp" }, n: { $sum: 1 } } }, { $sort: { _id: -1 } }, { $limit: 3 } ]);
// ... stored internally as a handful of bucket documents, columnar-compressed; expireAfterSeconds = built-in TTL.


/* ============================================================
   CLEANUP
   ============================================================ */
["l13_orders_embedded", "l13_emp_bad", "l13_logins", "l13_projects", "l13_emp_proj", "l13_customer_stats", "l13_products", "l13_reviews",
 "l13_readings", "l13_specs", "l13_events", "l13_people", "l13_categories", "l13_ts"].forEach(c => db[c].drop());

/* ------------------------------------------------------------
   DONE. Next: 02_Practice_Schema_Validation.js
   ------------------------------------------------------------ */
