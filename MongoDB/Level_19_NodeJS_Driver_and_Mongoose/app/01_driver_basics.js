/* ============================================================
   LEVEL 19  |  01_driver_basics.js  -  the official Node.js driver
   ------------------------------------------------------------
   Run:  cd app && npm install && npm run driver
   Topics : MongoClient + pool, CRUD, cursors, aggregation, bulk,
            error handling, BSON types, transactions, change streams,
            connection events, graceful close
   Works on l19_* copies of the companyDB collections.
   ============================================================ */

import { MongoClient, ObjectId, Decimal128, Long } from "mongodb";

const URI = process.env.MONGODB_URI || "mongodb://localhost:27017/?appName=level19-driver&maxPoolSize=10&retryWrites=true&w=majority&serverSelectionTimeoutMS=5000";
const client = new MongoClient(URI);                       // ONE client per application; it owns the connection pool
const step = (t) => console.log("\n=== " + t + " ===");

try {
    await client.connect();
    const db = client.db("companyDB");
    await db.command({ ping: 1 });
    console.log("connected to", (await db.admin().command({ hello: 1 })).setName, "| driver pool max:", client.options.maxPoolSize);

    // fresh copies to play with
    await db.collection("employees").aggregate([{ $out: "l19_employees" }]).toArray();
    await db.collection("products").aggregate([{ $out: "l19_products" }]).toArray();
    await db.collection("orders").aggregate([{ $out: "l19_orders" }]).toArray();
    const employees = db.collection("l19_employees"), products = db.collection("l19_products"), orders = db.collection("l19_orders");


    step("1. find -> cursor -> toArray / for await / next");
    const top3 = await employees.find({ salary: { $gte: 70000 } }, { projection: { _id: 0, name: 1, salary: 1 } }).sort({ salary: -1 }).limit(3).toArray();
    console.log(top3);                                     // [ Sneha 90000, Rahul 85000, Priya 75000 ]

    let names = [];
    for await (const doc of employees.find({ departmentId: 1 }).project({ name: 1 })) names.push(doc.name);   // streaming, batch by batch
    console.log("IT:", names);                             // Rahul, Amit, Pooja

    const cursor = employees.find({}).sort({ _id: 1 }).batchSize(5);
    console.log("first:", (await cursor.next())?.name, "| hasNext:", await cursor.hasNext());
    await cursor.close();

    console.log("findOne:", await employees.findOne({ _id: 106 }, { projection: { name: 1, "address.city": 1 } }));
    console.log("findOne miss:", await employees.findOne({ _id: 999 }));   // null
    console.log("count:", await employees.countDocuments({ active: true }), "| distinct:", await employees.distinct("address.city"));


    step("2. insert / update / delete results");
    const ins = await employees.insertOne({ _id: 201, name: "Isha", departmentId: 3, salary: 52000, hireDate: new Date("2025-01-15"), skills: [], active: true });
    console.log("insertedId:", ins.insertedId);
    const many = await employees.insertMany([{ _id: 202, name: "Omar", salary: 50000 }, { _id: 203, name: "Zara", salary: 51000 }]);
    console.log("insertedCount:", many.insertedCount, "ids:", many.insertedIds);

    const upd = await employees.updateOne({ _id: 201 }, { $inc: { salary: 3000 }, $push: { skills: "Recruiting" } });
    console.log("update:", { matched: upd.matchedCount, modified: upd.modifiedCount });
    const ups = await employees.updateOne({ _id: 204 }, { $set: { name: "Upserted" }, $setOnInsert: { createdAt: new Date() } }, { upsert: true });
    console.log("upsert:", { matched: ups.matchedCount, upsertedId: ups.upsertedId });
    const after = await employees.findOneAndUpdate({ _id: 201 }, { $set: { active: false } }, { returnDocument: "after", projection: { name: 1, active: 1 } });
    console.log("findOneAndUpdate ->", after);            // the document itself (driver 6)
    console.log("findOneAndUpdate miss ->", await employees.findOneAndUpdate({ _id: 999 }, { $set: { x: 1 } }));   // null
    const del = await employees.deleteMany({ _id: { $in: [202, 203, 204] } });
    console.log("deletedCount:", del.deletedCount);


    step("3. aggregation");
    const byDept = await employees.aggregate([
        { $match: { active: true } },
        { $group: { _id: "$departmentId", n: { $sum: 1 }, avg: { $avg: "$salary" } } },
        { $sort: { avg: -1 } },
        { $limit: 3 }
    ]).toArray();
    console.log(byDept);
    const withCustomer = await orders.aggregate([
        { $match: { _id: 1001 } },
        { $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "c" } },
        { $project: { _id: 1, totalAmount: 1, customer: { $first: "$c.name" } } }
    ]).next();
    console.log(withCustomer);


    step("4. bulkWrite and error handling");
    const bulk = await products.bulkWrite([
        { insertOne: { document: { _id: 12, name: "Dock", category: "Electronics", price: 6500, stock: 8 } } },
        { updateOne: { filter: { _id: 9 }, update: { $set: { stock: 15 } } } },
        { deleteOne: { filter: { _id: 8 } } }
    ]);
    console.log({ inserted: bulk.insertedCount, modified: bulk.modifiedCount, deleted: bulk.deletedCount });

    try {
        await products.insertOne({ _id: 12, name: "duplicate" });
    } catch (e) {
        console.log("EXPECTED ERROR:", e.constructor.name, "code", e.code, "->", e.code === 11000 ? "duplicate key (HTTP 409)" : e.message);
    }
    try {
        await products.bulkWrite([{ insertOne: { document: { _id: 1 } } }, { insertOne: { document: { _id: 99 } } }], { ordered: false });
    } catch (e) {
        console.log("EXPECTED ERROR:", e.constructor.name, "| inserted anyway:", e.result.insertedCount, "| writeErrors:", e.writeErrors.length);
    }
    try {
        await products.updateOne({ _id: 1 }, { price: 1 });   // no operator
    } catch (e) {
        console.log("EXPECTED ERROR (client-side check):", e.constructor.name, "-", e.message.substring(0, 60));
    }


    step("5. BSON types in Node");
    const oid = new ObjectId();
    await products.insertOne({ _id: oid, name: "Typed", price: Decimal128.fromString("19.99"), bigId: Long.fromString("9007199254740993"), qty: 5, ratio: 0.5, at: new Date() });
    const typed = await products.findOne({ _id: oid });
    console.log({ idIsObjectId: typed._id instanceof ObjectId, hex: typed._id.toHexString(), price: typed.price.toString(), priceType: typed.price.constructor.name,
                  bigId: typed.bigId.toString(), qtyType: typeof typed.qty, json: JSON.stringify({ _id: typed._id, price: typed.price, at: typed.at }) });
    console.log("ObjectId.isValid('abc'):", ObjectId.isValid("abc"), "| isValid(hex):", ObjectId.isValid(oid.toHexString()));
    const types = await products.aggregate([{ $match: { _id: oid } }, { $project: { _id: 0, qty: { $type: "$qty" }, ratio: { $type: "$ratio" }, price: { $type: "$price" }, bigId: { $type: "$bigId" } } }]).next();
    console.log("server-side types:", types);             // qty int, ratio double, price decimal, bigId long


    step("6. transaction with session.withTransaction");
    async function placeOrder(orderId, productId, qty) {
        const session = client.startSession();
        try {
            await session.withTransaction(async () => {
                const p = await products.findOne({ _id: productId }, { session });
                const r = await products.updateOne({ _id: productId, stock: { $gte: qty } }, { $inc: { stock: -qty } }, { session });
                if (r.matchedCount === 0) throw new Error("insufficient stock for " + p?.name);
                await orders.insertOne({ _id: orderId, customerId: 1, items: [{ productId, qty, unitPrice: p.price }], totalAmount: qty * p.price, status: "Pending" }, { session });
            }, { readConcern: { level: "snapshot" }, writeConcern: { w: "majority" } });
            return "placed";
        } catch (e) {
            return "FAILED: " + e.message;
        } finally {
            await session.endSession();
        }
    }
    console.log("order 3001:", await placeOrder(3001, 3, 2));       // placed (Keyboard 50 -> 48)
    console.log("order 3002:", await placeOrder(3002, 5, 99));      // FAILED: insufficient stock for Desk
    console.log("stock:", await products.find({ _id: { $in: [3, 5] } }).project({ _id: 1, stock: 1 }).toArray(), "| orders 3001/3002:", await orders.countDocuments({ _id: { $in: [3001, 3002] } }));


    step("7. change stream (consume 2 events, then close)");
    const stream = orders.watch([{ $match: { operationType: "insert" } }], { fullDocument: "updateLookup" });
    const events = [];
    const consumer = (async () => { for await (const ev of stream) { events.push(ev.operationType + " " + ev.fullDocument._id); if (events.length === 2) break; } })();
    await orders.insertOne({ _id: 3003, status: "Pending", totalAmount: 1 });
    await orders.insertOne({ _id: 3004, status: "Pending", totalAmount: 2 });
    await consumer;
    await stream.close();
    console.log("events:", events);                        // [ 'insert 3003', 'insert 3004' ]  (resume token = ev._id, persist it in real consumers)


    step("8. pool / connection events (for monitoring)");
    client.on("connectionPoolCleared", (e) => console.log("pool cleared", e.address));   // fires on failover / errors
    console.log("serverStatus connections:", (await db.admin().serverStatus()).connections.current);
    console.log("appName visible in currentOp:", (await db.admin().command({ currentOp: 1, $all: true })).inprog.some(o => o.appName === "level19-driver"));


    step("cleanup");
    await Promise.all(["l19_employees", "l19_products", "l19_orders"].map(c => db.collection(c).drop()));
    console.log("dropped l19_* collections");
} catch (e) {
    console.error("FATAL:", e.constructor.name, e.message);      // e.g. MongoServerSelectionError: is the container running?
    process.exitCode = 1;
} finally {
    await client.close();                                   // always close the client on shutdown (releases the pool)
    console.log("client closed");
}
