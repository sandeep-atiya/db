/* ============================================================
   LEVEL 19  |  03_express_api/server.js  -  a small REST API on companyDB
   ------------------------------------------------------------
   Run:  cd app && npm run api          ->  http://localhost:3000
   Try:  requests.http (VS Code REST Client) or curl / Invoke-RestMethod
   Topics : MongoClient singleton, routes, validation & casting,
            operator-injection guard, projection, pagination
            (skip/limit + keyset), aggregation endpoint, error
            mapping (400/404/409/500), graceful shutdown
   Employees are written to a COPY (api_employees) so companyDB stays clean.
   ============================================================ */

import express from "express";
import { MongoClient, ObjectId } from "mongodb";

const PORT = process.env.PORT || 3000;
const client = new MongoClient(process.env.MONGODB_URI || "mongodb://localhost:27017/?appName=level19-api&maxPoolSize=20&w=majority");
await client.connect();
const db = client.db("companyDB");
await db.collection("employees").aggregate([{ $out: "api_employees" }]).toArray();   // working copy
const employees = db.collection("api_employees");
await employees.createIndex({ departmentId: 1, salary: -1 });

const app = express();
app.use(express.json({ limit: "100kb" }));

/* ---------- helpers ---------- */
class HttpError extends Error { constructor(status, message) { super(message); this.status = status; } }
const toInt = (v, def, min, max) => { const n = v === undefined ? def : Number(v); if (!Number.isInteger(n) || n < min || n > max) throw new HttpError(400, `invalid integer (${min}-${max})`); return n; };
const parseId = (raw) => { const n = Number(raw); if (Number.isInteger(n)) return n; if (ObjectId.isValid(raw)) return new ObjectId(raw); throw new HttpError(400, "invalid id"); };
const PUBLIC = { _id: 1, name: 1, email: 1, departmentId: 1, salary: 1, hireDate: 1, skills: 1, "address.city": 1, active: 1 };
// Operator-injection guard: only plain scalars may come from the client, never objects like { "$gt": "" }
const scalar = (v, type, field) => { if (v === undefined) return undefined; if (typeof v !== type) throw new HttpError(400, `${field} must be a ${type}`); return v; };
const noOperators = (obj) => { for (const k of Object.keys(obj)) { if (k.startsWith("$") || k.includes(".")) throw new HttpError(400, "invalid field " + k); if (obj[k] && typeof obj[k] === "object" && !Array.isArray(obj[k]) && !(obj[k] instanceof Date)) noOperators(obj[k]); } };

/* ---------- routes ---------- */
// GET /employees?departmentId=1&minSalary=60000&sort=-salary&page=1&limit=5
app.get("/employees", async (req, res) => {
    const page = toInt(req.query.page, 1, 1, 10000), limit = toInt(req.query.limit, 10, 1, 100);
    const filter = {};
    if (req.query.departmentId !== undefined) filter.departmentId = toInt(req.query.departmentId, 0, 0, 1000000);
    if (req.query.minSalary !== undefined) filter.salary = { $gte: toInt(req.query.minSalary, 0, 0, 1e9) };
    if (req.query.city !== undefined) filter["address.city"] = scalar(req.query.city, "string", "city");
    const sortField = (req.query.sort || "_id").toString(), dir = sortField.startsWith("-") ? -1 : 1, key = sortField.replace(/^-/, "");
    if (!["_id", "name", "salary", "hireDate"].includes(key)) throw new HttpError(400, "unsupported sort");
    const sort = { [key]: dir, _id: 1 };                    // deterministic order (tiebreaker) for paging
    const [items, total] = await Promise.all([
        employees.find(filter, { projection: PUBLIC }).sort(sort).skip((page - 1) * limit).limit(limit).toArray(),
        employees.countDocuments(filter)
    ]);
    res.json({ page, limit, total, pages: Math.ceil(total / limit), items });
});

// GET /employees/after/105?limit=3  -> keyset pagination (no skip)
app.get("/employees/after/:lastId", async (req, res) => {
    const limit = toInt(req.query.limit, 10, 1, 100);
    const items = await employees.find({ _id: { $gt: parseId(req.params.lastId) } }, { projection: PUBLIC }).sort({ _id: 1 }).limit(limit).toArray();
    res.json({ items, nextCursor: items.length ? items[items.length - 1]._id : null });
});

// GET /employees/101
app.get("/employees/:id", async (req, res) => {
    const doc = await employees.findOne({ _id: parseId(req.params.id) }, { projection: PUBLIC });
    if (!doc) throw new HttpError(404, "employee not found");
    res.json(doc);
});

// POST /employees   { _id, name, salary, departmentId?, email?, skills? }
app.post("/employees", async (req, res) => {
    const b = req.body ?? {};
    noOperators(b);
    const doc = {
        _id: Number.isInteger(b._id) ? b._id : undefined,
        name: scalar(b.name, "string", "name"), salary: scalar(b.salary, "number", "salary"),
        departmentId: b.departmentId === undefined ? null : scalar(b.departmentId, "number", "departmentId"),
        email: scalar(b.email, "string", "email"), skills: Array.isArray(b.skills) ? b.skills.filter(s => typeof s === "string") : [],
        hireDate: new Date(), active: true
    };
    if (!doc.name || doc.name.length < 2 || !(doc.salary > 0)) throw new HttpError(400, "name (>= 2 chars) and salary (> 0) are required");
    if (doc._id === undefined) doc._id = new ObjectId();
    if (doc.email === undefined) delete doc.email;
    try {
        await employees.insertOne(doc);
    } catch (e) {
        if (e.code === 11000) throw new HttpError(409, "employee with this _id/email already exists");
        throw e;
    }
    res.status(201).location(`/employees/${doc._id}`).json(doc);
});

// PATCH /employees/101   { salary?, active?, city?, addSkill? }
app.patch("/employees/:id", async (req, res) => {
    const b = req.body ?? {}; noOperators(b);
    const update = { $set: {}, $currentDate: { updatedAt: true } };
    if (b.salary !== undefined) { if (!(scalar(b.salary, "number", "salary") > 0)) throw new HttpError(400, "salary must be > 0"); update.$set.salary = b.salary; }
    if (b.active !== undefined) update.$set.active = scalar(b.active, "boolean", "active");
    if (b.city !== undefined) update.$set["address.city"] = scalar(b.city, "string", "city");
    if (b.addSkill !== undefined) update.$addToSet = { skills: scalar(b.addSkill, "string", "addSkill") };
    if (Object.keys(update.$set).length === 0) delete update.$set;
    const doc = await employees.findOneAndUpdate({ _id: parseId(req.params.id) }, update, { returnDocument: "after", projection: PUBLIC });
    if (!doc) throw new HttpError(404, "employee not found");
    res.json(doc);
});

// DELETE /employees/101
app.delete("/employees/:id", async (req, res) => {
    const r = await employees.deleteOne({ _id: parseId(req.params.id) });
    if (r.deletedCount === 0) throw new HttpError(404, "employee not found");
    res.status(204).end();
});

// GET /stats/departments  -> aggregation
app.get("/stats/departments", async (_req, res) => {
    const rows = await employees.aggregate([
        { $match: { active: true } },
        { $group: { _id: "$departmentId", headcount: { $sum: 1 }, avgSalary: { $avg: "$salary" }, payroll: { $sum: "$salary" } } },
        { $lookup: { from: "departments", localField: "_id", foreignField: "_id", as: "d" } },
        { $project: { _id: 0, departmentId: "$_id", department: { $ifNull: [{ $first: "$d.name" }, "(none)"] }, headcount: 1, payroll: 1, avgSalary: { $round: ["$avgSalary", 0] } } },
        { $sort: { payroll: -1 } }
    ], { maxTimeMS: 2000 }).toArray();
    res.json(rows);
});

app.get("/health", async (_req, res) => { await db.command({ ping: 1 }); res.json({ ok: true, pool: client.options.maxPoolSize }); });

/* ---------- errors ---------- */
app.use((_req, _res, next) => next(new HttpError(404, "route not found")));
app.use((err, _req, res, _next) => {                        // Express 5 forwards rejected promises here automatically
    const status = err.status || (err.code === 11000 ? 409 : err.code === 121 ? 400 : 500);
    if (status === 500) console.error(err);
    res.status(status).json({ error: status === 500 ? "internal error" : err.message });
});

const server = app.listen(PORT, () => console.log(`API on http://localhost:${PORT}  (Ctrl+C to stop; try GET /employees?limit=3)`));
const shutdown = async () => { console.log("\nshutting down"); server.close(); await employees.drop().catch(() => {}); await client.close(); process.exit(0); };
process.on("SIGINT", shutdown); process.on("SIGTERM", shutdown);
