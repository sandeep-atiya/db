/* ============================================================
   LEVEL 19 - NODE.JS  |  Exercises.js      (run: cd app && npm run exercises)
   ------------------------------------------------------------
   Write your solution in the YOUR ANSWER functions, then compare
   with the SOLUTIONS below. Uses l19x_* copies (dropped at the end).

   QUESTIONS
   Q1.  Using the driver, return the names of the 3 highest-paid active
        employees as a plain string array.
   Q2.  Insert an order with Decimal128 prices for its items and read back the
        total as a JS number (round to 2 decimals).
   Q3.  Implement transfer(fromId, toId, amount) between two l19x_accounts
        documents in a transaction; it must reject overdrafts. Test both paths.
   Q4.  Implement a keyset-paginated function pageAfter(lastId, size) over
        employees sorted by _id and use it to walk ALL employees in pages of 5.
   Q5.  Build a Mongoose Product model (name required, price >= 0, category enum,
        tags array) and prove that a bad category is rejected but a string price
        "12" is cast.
   Q6.  Write safeFilter(query) that turns an untrusted query object such as
        { city: "Delhi", salary: { "$gt": "" } } into a filter that only allows
        string equality on city and a numeric minSalary - and rejects the rest.
   Q7.  Consume exactly 3 change-stream events for inserts into l19x_events and
        return their _ids (insert them from the same script after opening the stream).
   Q8.  (Think) Your API opens a new MongoClient inside every request handler.
        What breaks first under load, and what do you change?
   ============================================================ */

import { MongoClient, Decimal128, ObjectId } from "mongodb";
import mongoose from "mongoose";

const client = new MongoClient("mongodb://localhost:27017/?appName=level19-exercises&serverSelectionTimeoutMS=5000");
await client.connect();
const db = client.db("companyDB");
await db.collection("employees").aggregate([{ $out: "l19x_employees" }]).toArray();
const employees = db.collection("l19x_employees");
const step = (t) => console.log("\n=== " + t + " ===");

// ---------------- YOUR ANSWERS ----------------
async function q1() { /* ... */ }
async function q2() { /* ... */ }
async function q3() { /* ... */ }
async function q4() { /* ... */ }
async function q5() { /* ... */ }
function q6(query) { /* ... */ }
async function q7() { /* ... */ }


// ---------------- SOLUTIONS ----------------
step("Q1");
console.log((await employees.find({ active: true }, { projection: { _id: 0, name: 1 } }).sort({ salary: -1, _id: 1 }).limit(3).toArray()).map(e => e.name));   // Sneha, Rahul, Priya

step("Q2");
const ordersX = db.collection("l19x_orders");
await ordersX.insertOne({ _id: 1, items: [{ qty: 2, unitPrice: Decimal128.fromString("19.99") }, { qty: 1, unitPrice: Decimal128.fromString("0.01") }] });
const [{ total }] = await ordersX.aggregate([{ $match: { _id: 1 } }, { $project: { total: { $sum: { $map: { input: "$items", as: "i", in: { $multiply: ["$$i.qty", "$$i.unitPrice"] } } } } } }]).toArray();
console.log(total.toString(), "->", Math.round(parseFloat(total.toString()) * 100) / 100);   // Decimal128 '39.99' -> 39.99

step("Q3");
const accounts = db.collection("l19x_accounts");
await accounts.insertMany([{ _id: "A", balance: 100 }, { _id: "B", balance: 0 }]);
async function transfer(fromId, toId, amount) {
    const session = client.startSession();
    try {
        await session.withTransaction(async () => {
            const r = await accounts.updateOne({ _id: fromId, balance: { $gte: amount } }, { $inc: { balance: -amount } }, { session });
            if (r.matchedCount === 0) throw new Error("insufficient funds");
            await accounts.updateOne({ _id: toId }, { $inc: { balance: amount } }, { session });
        });
        return "ok";
    } catch (e) { return "FAILED: " + e.message; } finally { await session.endSession(); }
}
console.log(await transfer("A", "B", 60), await transfer("A", "B", 60), await accounts.find().toArray());   // ok, FAILED, A 40 / B 60

step("Q4");
async function pageAfter(lastId, size) { return employees.find(lastId === null ? {} : { _id: { $gt: lastId } }, { projection: { _id: 1 } }).sort({ _id: 1 }).limit(size).toArray(); }
let last = null, pages = 0, seen = 0;
while (true) { const p = await pageAfter(last, 5); if (!p.length) break; pages++; seen += p.length; last = p[p.length - 1]._id; }
console.log({ pages, seen });                              // 3 pages, 12 employees

step("Q5");
await mongoose.connect("mongodb://localhost:27017/companyDB", { appName: "level19-exercises-mongoose" });
const Product = mongoose.model("XProduct", new mongoose.Schema({
    name: { type: String, required: true }, price: { type: Number, min: 0, required: true },
    category: { type: String, enum: ["Electronics", "Furniture", "Stationery"] }, tags: [String]
}, { collection: "l19x_products" }));
try { await Product.create({ name: "Toy", price: 1, category: "Toys" }); } catch (e) { console.log("EXPECTED:", e.errors.category.message); }
const p = await Product.create({ name: "Pen", price: "12", category: "Stationery", tags: ["writing"] });
console.log("price cast:", typeof p.price, p.price);

step("Q6");
function safeFilter(query) {
    const f = {};
    if (query.city !== undefined) { if (typeof query.city !== "string") throw new Error("city must be a string"); f["address.city"] = query.city; }
    if (query.minSalary !== undefined) { const n = Number(query.minSalary); if (!Number.isFinite(n)) throw new Error("minSalary must be a number"); f.salary = { $gte: n }; }
    for (const k of Object.keys(query)) if (!["city", "minSalary"].includes(k)) throw new Error("unknown parameter " + k);
    return f;
}
console.log(safeFilter({ city: "Delhi", minSalary: "60000" }));
try { safeFilter({ city: "Delhi", salary: { "$gt": "" } }); } catch (e) { console.log("EXPECTED:", e.message); }
try { safeFilter({ city: { "$ne": "" } }); } catch (e) { console.log("EXPECTED:", e.message); }

step("Q7");
const events = db.collection("l19x_events");
const stream = events.watch([{ $match: { operationType: "insert" } }]);
const ids = [];
const consumer = (async () => { for await (const ev of stream) { ids.push(ev.fullDocument._id); if (ids.length === 3) break; } })();
await events.insertMany([{ _id: 1 }, { _id: 2 }, { _id: 3 }]);
await consumer; await stream.close();
console.log("event ids:", ids);                            // [ 1, 2, 3 ]

step("Q8");
console.log("Each request creates a pool + handshake (tens of ms) and never closes it: connections pile up until the server's limit / RAM " +
            "(~1 MB each) is hit and new requests fail with server selection / connection errors. Fix: one MongoClient created at startup " +
            "(module singleton), reused by all handlers, sized with maxPoolSize, closed on shutdown.");

// cleanup
await Promise.all(["l19x_employees", "l19x_orders", "l19x_accounts", "l19x_products", "l19x_events"].map(c => db.collection(c).drop().catch(() => {})));
await mongoose.disconnect(); await client.close();
console.log("\ndone");
