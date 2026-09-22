# Level 19 — Node.js Driver, Mongoose & an Express API

**Goal:** use MongoDB from application code the way it is used at work: the official **Node.js driver** (connection, CRUD, cursors, aggregation, bulk, transactions, change streams, error handling), **Mongoose** (schemas, validation, middleware, populate, lean), and a small **Express REST API** with pagination, projection, safe input handling and an aggregation endpoint.

**Time:** ~4 hr · **Files:** `app/01_driver_basics.js` → `app/02_mongoose_models.js` → `app/03_express_api/server.js` (+ `requests.http`) → `Exercises.js`

```
cd app
npm install                      # mongodb, mongoose, express (once)
npm run driver                   # 01_driver_basics.js
npm run mongoose                 # 02_mongoose_models.js
npm run api                      # starts http://localhost:3000  (Ctrl+C to stop)
```

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Driver** | `mongodb` npm package: the official, low-level client. Same operation names as `mongosh` (`insertOne`, `find`, `aggregate`…), all **async** (Promises). Returns plain objects with BSON types (`ObjectId`, `Decimal128`, `Long`). |
| **`MongoClient`** | Owns the **connection pool**. Create **one per application** (module-level singleton), `await client.connect()` at startup, reuse everywhere, `close()` on shutdown. Never connect per request. |
| **Connection string options** | `maxPoolSize` (default 100), `minPoolSize`, `connectTimeoutMS`, `socketTimeoutMS`, `serverSelectionTimeoutMS` (30 s: how long to wait for a primary), `retryWrites=true`, `retryReads=true`, `w=majority`, `readPreference`, `readConcernLevel`, `appName` (shows in `currentOp` / logs), `replicaSet`, `directConnection`, `authSource`, `tls`. |
| **Cursor** | `find()` returns a `FindCursor`: `toArray()`, `for await (const doc of cursor)`, `next()`, `.project() .sort() .skip() .limit() .batchSize()` chainable before iteration. Aggregations return an `AggregationCursor`. |
| **Results** | `insertOne → { insertedId }`, `insertMany → { insertedCount, insertedIds }`, `updateOne → { matchedCount, modifiedCount, upsertedId }`, `deleteOne → { deletedCount }`, `findOneAndUpdate → the document (returnDocument: "after")` (driver 6: returns the doc directly; `includeResultMetadata: true` for the old `{ value, ok }` shape). |
| **Errors** | `MongoServerError` with `code` (11000 duplicate key, 121 document validation, 112 write conflict, 50 max time), `MongoBulkWriteError` (`writeErrors`, `result`), `MongoNetworkError`, `MongoServerSelectionError` (cannot find a server — wrong URI / down). Error labels: `TransientTransactionError`, `UnknownTransactionCommitResult`. |
| **BSON in Node** | `ObjectId` (`new ObjectId(str)`, `ObjectId.isValid`), `Decimal128.fromString`, `Long`, `Int32`, `Double`, `UUID`, `Binary`. JS `number` → int32 if integral & in range, else double. Dates: JS `Date`. `JSON.stringify` turns ObjectId into a hex string, Decimal128 into `{ $numberDecimal }` — shape your API responses. |
| **Transactions** | `const session = client.startSession(); await session.withTransaction(async () => { await coll.insertOne(doc, { session }); … })` — pass `{ session }` to **every** operation; the callback may run more than once (must be idempotent). |
| **Change streams** | `const stream = coll.watch(pipeline, { fullDocument: "updateLookup", resumeAfter })`; `for await (const event of stream)`; `stream.close()`. |
| **Mongoose** | ODM on top of the driver: `Schema` (types, `required`, `default`, `enum`, `min/max`, `match`, `validate`, `index`, `unique` → creates an index, `timestamps`, sub-schemas, arrays, `ref`), `Model` (`create`, `find().lean()`, `findById`, `findOneAndUpdate({ new: true, runValidators: true })`, `updateMany`, `deleteOne`, `aggregate`, `countDocuments`), `Document` (getters/setters, `save()`, `validate()`), **middleware** (`pre('save')`, `post('save')`, query hooks), **virtuals**, **statics/methods**, **populate** (client-side join by `ref`, N+1-ish: one extra query per populate call, not per document), `lean()` (plain objects, much faster), `strict` mode (unknown fields dropped), `versionKey __v`, `mongoose.connect()` buffering. |
| **Express patterns** | one router per resource; validate/cast every input (`req.params.id` → `ObjectId.isValid` / `Number`, `req.query.page` → int with bounds); **never** pass `req.body` / `req.query` objects straight into a filter (operator injection: `{ "$gt": "" }`); project only the fields the client needs; paginate with `limit` ≤ 100 (skip for small pages, keyset for deep); map driver errors to HTTP codes (11000 → 409, validation → 400, not found → 404, else 500); async error handler; graceful shutdown (`SIGINT` → `client.close()`). |

### Driver vs Mongoose — when?

| | Driver | Mongoose |
|-|--------|----------|
| Control / performance | full, fastest | adds hydration cost (use `lean()`) |
| Schema & validation | none (use `$jsonSchema` + your own validation) | in code, expressive, but only in your app |
| Learning curve | shell knowledge transfers 1:1 | its own API and quirks (casting, strict, `__v`) |
| Relationships | `$lookup` or manual | `populate` (extra queries) or `$lookup` via `aggregate` |
| Typical use | services, scripts, high-throughput paths, TypeScript with generics | CRUD-heavy apps that want a model layer, teams coming from ORMs |

## 2. Syntax cheat-sheet

```js
import { MongoClient, ObjectId, Decimal128 } from "mongodb";
const client = new MongoClient("mongodb://localhost:27017/?appName=level19&maxPoolSize=20&retryWrites=true&w=majority");
await client.connect();
const db = client.db("companyDB"), employees = db.collection("employees");

const list = await employees.find({ departmentId: 1 }, { projection: { _id: 0, name: 1 } }).sort({ salary: -1 }).limit(5).toArray();
for await (const doc of employees.find({})) { /* streaming */ }
const one = await employees.findOne({ _id: 101 });
const { insertedId } = await employees.insertOne({ name: "New", salary: 50000 });
const r = await employees.updateOne({ _id: 101 }, { $inc: { salary: 1000 } });            // r.modifiedCount
const updated = await employees.findOneAndUpdate({ _id: 101 }, { $set: { active: true } }, { returnDocument: "after" });
const agg = await employees.aggregate([ { $group: { _id: "$departmentId", n: { $sum: 1 } } } ]).toArray();
try { await employees.insertOne({ _id: 101 }); } catch (e) { if (e.code === 11000) /* duplicate */ ; }
const session = client.startSession();
try { await session.withTransaction(async () => { await a.updateOne(f1, u1, { session }); await b.insertOne(d, { session }); }); } finally { await session.endSession(); }
await client.close();

// Mongoose
import mongoose from "mongoose";
await mongoose.connect("mongodb://localhost:27017/companyDB");
const employeeSchema = new mongoose.Schema({
    name: { type: String, required: true, trim: true, minlength: 2 },
    email: { type: String, unique: true, lowercase: true, match: /@/ },
    salary: { type: Number, min: 1, required: true },
    department: { type: mongoose.Schema.Types.ObjectId, ref: "Department" },
    skills: [String],
    address: { city: String, pincode: Number }
}, { timestamps: true, collection: "employees" });
employeeSchema.index({ salary: -1 });
const Employee = mongoose.model("Employee", employeeSchema);
const e = await Employee.create({ name: "Isha", email: "i@x.com", salary: 50000 });
const docs = await Employee.find({ salary: { $gte: 60000 } }).select("name salary").sort("-salary").limit(5).lean();
const withDept = await Employee.findById(id).populate("department", "name");
await Employee.findByIdAndUpdate(id, { $inc: { salary: 100 } }, { new: true, runValidators: true });
```

## 3. Gotchas

- **One `MongoClient` per process.** Connecting per request exhausts the pool and the server's connections (each connection ≈ 1 MB RAM on the server).
- **Forgetting `await`** → unhandled promise, code continues before the write happened. **Forgetting `toArray()`** → you have a cursor, not data.
- **`_id` in URLs is a string**; convert with `new ObjectId(id)` (and check `ObjectId.isValid` first) or your numeric ids with `Number()`. A string `"101"` never matches the number `101`.
- **`req.body` straight into a query is operator injection** — whitelist fields and check `typeof`.
- **`findOneAndUpdate` returns `null` when nothing matched** (driver 6 returns the document or null; older versions `{ value }`).
- **Driver serialises `number`s as int32 or double** — for money use `Decimal128`, for 64-bit ids `Long`. `JSON.stringify(Decimal128)` gives `{ "$numberDecimal": "…" }`, `ObjectId` gives its hex string; `Date` gives an ISO string.
- **Transactions: pass `{ session }` to every call**, keep callbacks idempotent (they may be retried), never do I/O with side effects inside.
- **`serverSelectionTimeoutMS` (30 s) is why a wrong URI "hangs"** before failing with `MongoServerSelectionError`; lower it in dev.
- **Mongoose `unique` is an index, not a validator** — the duplicate arrives as an `E11000` error, not a `ValidationError`; and the index is built asynchronously at startup (`autoIndex`), so early inserts may slip through. Use `syncIndexes()` in migrations, `autoIndex: false` in production.
- **Mongoose `findOneAndUpdate` skips validators and `pre('save')` hooks** unless `runValidators: true`; `save()` runs them. `update` operators bypass defaults.
- **`populate` = extra queries** (one per populated path, not per document) and no filtering on joined fields — use `aggregate` + `$lookup` for reporting.
- **`lean()`** returns plain objects (fast, no getters/virtuals/save). Use it for read-only endpoints.
- **Mongoose casts silently**: `"123"` → 123, `"abc"` for a Number → `CastError`; unknown fields are dropped in strict mode (default) — or throw with `strict: "throw"`.
- **Express 5** handles rejected promises in async handlers automatically; Express 4 needs a wrapper / `express-async-errors`.

## 4. Interview questions

**Q: How do you manage MongoDB connections in a Node.js app?**
One `MongoClient` (or `mongoose.connect`) at startup, shared as a module singleton; the driver keeps a pool (`maxPoolSize`, default 100) and reconnects automatically; close on shutdown. Never open a client per request.

**Q: Driver vs Mongoose?**
The driver is the official low-level API (fast, no schema, shell-like). Mongoose adds schemas, validation, middleware, virtuals and populate at the cost of hydration overhead and its own semantics. Choose the driver for services/perf/TypeScript, Mongoose when you want a model layer.

**Q: How do you avoid injection in MongoDB queries from user input?**
Validate and cast every input (types, whitelists), never spread `req.query`/`req.body` into filters, reject keys starting with `$` (or use `mongo-sanitize` / `express-mongo-sanitize`), never use `$where`, and parameterise search with `$regex` escaping.

**Q: How do you paginate an API on MongoDB?**
`skip/limit` with a bounded `limit` and a deterministic sort (incl. `_id`) for shallow pages; keyset pagination (`{ _id: { $gt: lastId } }`) or `$setWindowFields` for deep/infinite scroll; return `nextCursor`. `countDocuments` for totals (or `$facet` in one round trip).

**Q: How do transactions look in the driver?**
`client.startSession()` → `session.withTransaction(async () => { … every op with { session } … })` → `endSession()`. The callback retries on transient errors, so keep it idempotent and short.

**Q: What is `populate` and how does it compare to `$lookup`?**
Mongoose fetches referenced documents with additional queries after the main query (by `ref`), then stitches them in. `$lookup` does it server-side in one aggregation and allows filtering/sorting on joined data. Populate is convenient for a few references; `$lookup` for reporting.

**Q: What does `lean()` do?**
Returns plain JavaScript objects instead of Mongoose documents — no change tracking, virtuals, getters or `save()` — several times faster and less memory for read-only queries.

**Q: How do you handle ObjectId in a REST API?**
Validate `ObjectId.isValid(id)` (24 hex chars) → 400 otherwise; convert with `new ObjectId(id)`; serialise back as a string (`_id.toString()` / `toHexString()`).

**Q: What HTTP status codes do you map MongoDB errors to?**
11000 duplicate → 409 Conflict; 121 document validation / `ValidationError` / `CastError` → 400; no document → 404; write conflict / transient → retry then 503; anything else → 500 (logged, not leaked).

**Q: How do you keep connection pool and server healthy under load?**
Size `maxPoolSize` to what the server can take (connections × app instances), use `maxIdleTimeMS`, timeouts (`socketTimeoutMS`, `maxTimeMS` per query), retryable writes, read from secondaries where staleness is OK, and monitor `serverStatus().connections` and queue lengths.

## 5. Checklist

- [ ] I can connect with a `MongoClient` singleton and explain the pool / URI options
- [ ] I can do CRUD, cursors, aggregation, bulk writes and error handling with the driver
- [ ] I can write a transaction with `withTransaction` and a change-stream consumer in Node
- [ ] I can define a Mongoose schema with validation, indexes, middleware, virtuals and populate, and know when to use `lean()`
- [ ] I can build a safe Express endpoint: validated input, projection, pagination, proper status codes
