# Level 13 — Schema Design & Validation

**Goal:** design documents the MongoDB way — decide between **embedding** and **referencing** for 1:1, 1:many and many:many relationships, know the named design patterns and anti-patterns, and enforce the rules you care about with **`$jsonSchema` validation**.

**Time:** ~3 hr · **Files:** `01_Practice_Embedding_vs_Referencing.js` → `02_Practice_Schema_Validation.js` → `Exercises.js`

---

## 1. Concepts in plain words

### The one rule: model for the queries, not for the entities

In SQL you normalise first and join later. In MongoDB you ask **"what does the application read and write together?"** and store that together. Data accessed together should live together (embed); data shared, unbounded or updated independently is referenced.

| Relationship | Default choice | Example in `companyDB` |
|--------------|----------------|------------------------|
| **1 : 1** | embed | `employee.address` |
| **1 : few** (bounded, read with the parent) | embed an array | `order.items`, `employee.skills` |
| **1 : many** (large / growing) | reference from the child (`order.customerId`) | customer → orders |
| **1 : squillions** (logs, events) | reference from the child, never an array on the parent | user → clicks |
| **many : many** | array of references on one or both sides | employees ↔ projects |
| **many : many with data on the link** | separate collection (like a link table) | enrollments with a grade |

**Embed when**: read together, updated together, bounded size (< hundreds), child has no meaning alone, you need atomic updates of parent + child.
**Reference when**: the child is shared, unbounded, updated on its own, large, or queried by itself; or when embedding would exceed 16 MB / duplicate a lot.
**Duplicate (denormalise) when**: a read is hot and the copied value rarely changes (`order.items[].unitPrice` at sale time, customer name on an invoice) — accept eventual staleness or update it in the app / with a change stream.

### Named patterns (know these by name)

| Pattern | Idea | When |
|---------|------|------|
| **Attribute** | move variable key/value pairs into an array `[{ k, v }]` so one index covers all | products with different specs |
| **Bucket** | group time-series points into documents of N measurements | IoT, metrics (or use **time series collections**) |
| **Computed** | store a pre-calculated value (total, count, average) at write time | dashboards, hot aggregates |
| **Extended reference** | copy a few frequently-read fields of the referenced doc | `order.customer: { _id, name, city }` |
| **Subset** | keep the most recent / relevant N children embedded, the rest in another collection | last 10 reviews on the product |
| **Outlier** | handle the rare huge document specially (flag + overflow collection) | a celebrity's followers |
| **Polymorphic** | documents of different shapes in one collection with a `type` field | events, products |
| **Schema versioning** | `schemaVersion` field; app migrates lazily on read/write | evolving schemas without downtime |
| **Tree** | parent reference · child references · array of ancestors · materialised path | categories, org charts (`$graphLookup`) |
| **Approximation** | update counters every N events instead of every event | page views |
| **Pre-allocation** | create the document with its final shape (rarely needed with WiredTiger) | fixed-size day/hour buckets |

### Anti-patterns (Atlas Performance Advisor flags these)

- **Unbounded arrays** (`$push` forever) → 16 MB limit, slow rewrites, multikey index bloat.
- **Massive number of collections** (per tenant / per day) → metadata overhead; use a field instead.
- **Bloated documents**: storing everything in one document when most reads need 5 %.
- **Unnecessary indexes** (write cost, RAM) and **case-insensitive queries without a collation index**.
- **Separating data that is accessed together** (SQL habit: one collection per entity → `$lookup` everywhere).
- **Storing large binary files** in documents (use GridFS / object storage).

### Schema validation

`validator` on a collection: `$jsonSchema` (types, required, enums, ranges, patterns, nested objects, arrays) and/or query operators (`$expr`, `$and`…). `validationLevel`: `strict` (all inserts + updates, default) / `moderate` (only documents that already pass) / `off`. `validationAction`: `error` (reject, default) / `warn` (log only). Change with `collMod`; bypass with `bypassDocumentValidation` (privileged). Errors include a `details` document explaining which rule failed (5.0+).

### Time series collections (5.0+)

`createCollection("metrics", { timeseries: { timeField: "ts", metaField: "sensor", granularity: "minutes" }, expireAfterSeconds })` — buckets are managed for you; optimised storage and queries for measurements.

## 2. Syntax cheat-sheet

```js
// embedded
{ _id: 1001, customer: { _id: 1, name: "Aarav", city: "Delhi" }, items: [ { productId: 1, qty: 1, unitPrice: 75000 } ] }
// referenced (+ extended reference)
{ _id: 1001, customerId: 1, customerName: "Aarav" }          // and a $lookup when you need the rest
// many-to-many
{ _id: 101, name: "Rahul", projectIds: [1, 2] }   { _id: 1, name: "Migration", memberIds: [101, 108] }
// bucket
{ sensor: "s1", day: ISODate("2025-01-05"), count: 3, readings: [ { t: …, v: 20.5 }, … ] }   // $push with $inc count; new bucket at 200
// attribute pattern
{ name: "Laptop", specs: [ { k: "ram", v: "16GB" }, { k: "cpu", v: "i7" } ] }   // index { "specs.k": 1, "specs.v": 1 }

// validation
db.createCollection("employees_v", { validator: { $jsonSchema: {
    bsonType: "object", required: ["name", "salary", "departmentId"],
    properties: {
        name:  { bsonType: "string", minLength: 2, description: "required string" },
        email: { bsonType: "string", pattern: "^[^@]+@[^@]+\\.[a-z]{2,}$" },
        salary: { bsonType: ["int", "double", "long", "decimal"], minimum: 1 },
        departmentId: { bsonType: ["int", "null"] },
        status: { enum: ["active", "inactive"] },
        skills: { bsonType: "array", items: { bsonType: "string" }, uniqueItems: true, maxItems: 20 },
        address: { bsonType: "object", required: ["city"], properties: { city: { bsonType: "string" }, pincode: { bsonType: "int" } } }
    },
    additionalProperties: false } },
    validationLevel: "strict", validationAction: "error" })
db.runCommand({ collMod: "employees_v", validator: { … }, validationLevel: "moderate", validationAction: "warn" })
db.getCollectionInfos({ name: "employees_v" })[0].options.validator
db.employees_v.insertOne(doc, { bypassDocumentValidation: true })
```

## 3. Gotchas

- **`bsonType: "int"` rejects `85000.5` and also a `double` 85000** — list all numeric types or use `"number"`.
- **`required` only checks presence**; `null` passes unless the type excludes it (`bsonType: "string"` rejects null).
- **`additionalProperties: false` blocks future fields** — including ones you forgot to list (`_id` must be listed or allowed!).
- **Validation runs on updates too**: an `updateOne` that removes a required field fails under `strict`; existing invalid documents are only checked when touched (and never under `moderate`).
- **Validation does not enforce uniqueness or references** — unique indexes and application logic do.
- **Extended references go stale**: decide who updates the copies (app on write, change stream, nightly job).
- **`$lookup` is not a design**: if every read needs it, embed.
- **Do not embed both ways** (customer has orders array and order has customer) unless one side is a small subset.
- **ObjectId vs natural key for `_id`**: natural keys (email) are convenient but immutable — a changed email means delete + insert.
- **Field names cost bytes**: `{ transactionTimestamp }` × 1 billion documents matters; keep names short in huge collections (not in `companyDB`).
- **Time series collections** have restrictions (no updates of individual measurements before 5.1, limited index types) — read the docs before choosing.

## 4. Interview questions

**Q: Embedding vs referencing — how do you decide?**
Access pattern first: read/written together, bounded, owned by the parent → embed (atomic, one read). Shared, unbounded, independently updated or queried, large → reference. Duplicate small hot fields (extended reference) to avoid joins and accept controlled staleness.

**Q: How do you model one-to-many?**
Few & bounded: embed an array in the parent. Many: put the parent id in the child (`orders.customerId`) and index it. Huge: same, never an array on the parent. Choose by cardinality and growth, not by "type" of relationship.

**Q: How do you model many-to-many?**
Arrays of ids on one side (the side that is queried) or both, indexed (multikey). If the relationship has attributes (grade, role, date), a separate collection like a link table.

**Q: What is the 16 MB limit and how do you design around it?**
Max BSON document size. Avoid unbounded arrays: bucket pattern (fixed-size chunks), subset pattern (recent N embedded, rest referenced), or a child collection.

**Q: What is the bucket pattern?**
Grouping many small measurements into one document per (source, time window) with an array and pre-computed stats — far fewer documents and index entries. Time series collections implement it automatically.

**Q: What is the extended reference / computed pattern?**
Extended reference: copy a few fields of the referenced document into the referencing one to avoid `$lookup`. Computed: store derived values (totals, counts) on write so reads are cheap. Both trade write complexity for read speed.

**Q: How do you evolve a schema without downtime?**
Schema versioning: add `schemaVersion`, write new documents in the new shape, make the app handle both, migrate old documents lazily (on read/update) or in a background job, then remove old-version code.

**Q: How do you enforce data rules in a schemaless database?**
Collection validation with `$jsonSchema` (types, required, enums, ranges, patterns, nested rules), unique/partial indexes for uniqueness, application/ODM validation (Mongoose) for business rules, transactions for multi-document invariants.

**Q: `validationLevel` moderate vs strict? `validationAction` warn vs error?**
strict validates every insert and update; moderate skips updates of documents that already violate the rules (useful when adding rules to existing data). error rejects; warn only logs — use warn to test a new validator in production before enforcing it.

**Q: Why is "one collection per SQL table + `$lookup` everywhere" an anti-pattern?**
It reproduces joins MongoDB is not optimised for (no join planner, index needed on the foreign side, `$lookup` per document) and loses the document model's benefits: atomic single-document writes and one-read access.

## 5. Checklist

- [ ] I can decide embed vs reference for 1:1, 1:few, 1:many, 1:squillions and many:many with reasons
- [ ] I can describe attribute, bucket, computed, extended reference, subset, polymorphic, schema-versioning and tree patterns
- [ ] I can name the common anti-patterns and the 16 MB consequences
- [ ] I can write a `$jsonSchema` validator with types, required, enum, ranges, patterns, arrays and nested objects
- [ ] I know `validationLevel` / `validationAction`, `collMod` and how to read a validation error
- [ ] I can explain when a time series collection is the right choice
