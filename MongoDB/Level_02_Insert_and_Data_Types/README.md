# Level 02 — Insert & Data Types (BSON)

**Goal:** insert documents correctly (one, many, ordered / unordered, custom `_id`), and know every BSON type well enough to choose the right one — especially numbers, dates, null-vs-missing and embedded documents.

**Time:** ~1.5 hr · **Files:** `01_Practice_Insert.js` → `02_Practice_Data_Types.js` → `Exercises.js`

---

## 1. Concepts in plain words

### Insert

| Method | Returns | Notes |
|--------|---------|-------|
| `insertOne(doc)` | `{ acknowledged, insertedId }` | generates `_id` if missing |
| `insertMany([docs], { ordered })` | `{ acknowledged, insertedIds: {0: …, 1: …} }` | **ordered: true (default)** stops at the first error, documents *before* it are kept. **ordered: false** tries every document and reports all errors — faster (parallel) for bulk loads. |
| `bulkWrite([...])` | detailed result | mixed insert / update / delete in one round trip (Level 07) |
| `insert()` | legacy | deprecated — do not use |

- Inserts are **atomic per document**: one document is fully written or not at all. `insertMany` is **not** atomic as a whole (no rollback of the earlier documents) — use a transaction (Level 14) if you need all-or-nothing.
- A **write concern** decides when the server acknowledges: `w: 1` (primary wrote it, default), `w: "majority"` (replicated to most nodes), `j: true` (in the journal). Level 17.

### BSON types you must know

| Type (`$type` alias / code) | mongosh literal | Use for | Gotcha |
|---|---|---|---|
| **int** (16) | `85000`, `NumberInt(85000)` / `Int32(…)` | counters, ids, whole numbers | mongosh / Node.js store a **whole number that fits in 32 bits as int** automatically |
| **double** (1) | `3.14`, `1e10`, `Double(85000)` | fractions, big values | 64-bit float: `0.1 + 0.2 ≠ 0.3`; any JS number that is not a 32-bit whole number becomes double |
| **long** (18) | `NumberLong("9007199254740993")` / `Long(…)` | 64-bit ids, timestamps, > 2^31 | JS cannot hold > 2^53 exactly → pass a **string** |
| **decimal** (19) | `NumberDecimal("19.99")` / `Decimal128(…)` | **money** | exact base-10; arithmetic works in aggregation |
| **string** (2) | `"Rahul"` | text (UTF-8) | comparisons are **case-sensitive** and by code point |
| **bool** (8) | `true` | flags | `"true"` (string) is not `true` |
| **null** (10) | `null` | "known to be empty" | `{f: null}` also matches **missing** fields |
| **date** (9) | `new Date("2025-01-05")`, `ISODate("2025-01-05")` | dates/times | stored as **UTC ms since epoch**; a date stored as a *string* cannot be compared with a Date |
| **object** (3) | `{ city: "Delhi" }` | embedded document | equality match needs **all fields in the same order** — use dot notation |
| **array** (4) | `["Java", "SQL"]` | lists, sets, order matters | `{skills: "Java"}` matches if *any* element equals |
| **objectId** (7) | `ObjectId()` | default `_id` | 12 bytes, time-sortable |
| **binData** (5) | `BinData(0, "…")`, `UUID()` | files, hashes, UUIDs | keep large files in GridFS / object storage |
| **regex** (11) | `/^ra/i` | stored patterns | rarely stored; usually only used in queries |
| **timestamp** (17) | `Timestamp()` | internal (oplog) | not for application dates — use **date** |
| minKey / maxKey (-1/127) | `MinKey()` | compare below/above everything | |
| `number` | — | alias matching double + int + long + decimal | |

**Comparison / sort order of different types** (type bracketing):
`MinKey < null < numbers < string < object < array < binData < objectId < bool < date < timestamp < regex < MaxKey`
→ `{ price: { $gt: 100 } }` matches only *numbers*; a document whose price is the string `"500"` is ignored, and sorting a mixed field puts all numbers before all strings.

## 2. Syntax cheat-sheet

```js
db.c.insertOne({ name: "A" })
db.c.insertMany([{ _id: 1 }, { _id: 2 }])
db.c.insertMany([...], { ordered: false })
db.c.insertOne({ ... }, { writeConcern: { w: "majority" } })

// type literals
NumberInt(5)   NumberLong("5")   NumberDecimal("5.50")   new Date()   ISODate("2025-01-05T10:30:00Z")
ObjectId()     ObjectId("665f1c2e9b1d4e3a5c7d8e9f")   UUID()   /^ra/i   MinKey()   MaxKey()

// inspect types
db.c.find({ salary: { $type: "double" } })          // by alias
db.c.find({ salary: { $type: 16 } })                // by code (int)
db.c.find({ salary: { $type: ["int", "long"] } })   // any of
db.c.find({ salary: { $type: "number" } })          // all numeric types
db.c.aggregate([{ $project: { t: { $type: "$salary" } } }])   // type name as a value
typeof x   x instanceof Date   Object.bsonsize(doc)           // JS side
```

## 3. Gotchas

- **The shell picks the numeric type for you.** `insertOne({ qty: 5 })` stores an **int**; `{ price: 5.5 }` or `{ n: 3000000000 }` store a **double**; the Node.js driver behaves the same. (The old `mongo` shell stored everything as double — an interview classic.) Use `NumberLong` / `NumberDecimal` / `Double()` when the type matters (64-bit ids, money, interop with typed drivers such as Java / C#).
- **Money → `NumberDecimal`, never double.** `0.1 + 0.2 = 0.30000000000000004` in double.
- **`NumberLong(9007199254740993)` loses precision** because the JS literal is already a double — pass the value as a **string**.
- **Dates are UTC.** `ISODate("2025-01-05")` = `2025-01-05T00:00:00Z`. Time zones are the application's (or `$dateToString`'s) job. Store dates as **Date**, never as strings.
- **`null` ≠ missing, but `{ f: null }` matches both.** Use `$exists` / `$type: "null"` to tell them apart.
- **Embedded document equality is exact and ordered.** `{ address: { city: "Delhi" } }` does **not** match `{ address: { city: "Delhi", state: "Delhi" } }`. Use `"address.city": "Delhi"`.
- **Field names**: cannot start with `$` at the top level in most contexts, cannot contain `.`; avoid `null` characters. Keys are case-sensitive.
- **`insertMany` ordered stop:** with `ordered: true`, everything after the failing document is skipped silently — check `insertedIds` / the error's `writeErrors`.
- **16 MB limit per document.** Growing arrays (e.g. every event of a user) will hit it; see the bucket pattern in Level 13.
- **`_id` can be any type except an array** (and not a regex). A custom string `_id` like `"EMP-101"` is fine and common.

## 4. Interview questions

**Q: insertOne vs insertMany — what happens on an error in the middle?**
`insertMany` is ordered by default: it stops at the first error; documents before it are already inserted and stay (no rollback). With `ordered: false` the server attempts all documents and returns every error. For all-or-nothing use a multi-document transaction.

**Q: What BSON numeric types exist and which one do you get by default?**
int (32-bit), long (64-bit), double (64-bit float), decimal (Decimal128). `mongosh` and the Node.js driver store a JS number as **int when it is a whole number that fits in 32 bits, otherwise as double** (the legacy `mongo` shell always used double). Use `NumberInt` / `NumberLong` / `NumberDecimal` / `Double` (or `Int32` / `Long` / `Decimal128` in Node) to choose explicitly.

**Q: How should you store money?**
`NumberDecimal` (Decimal128): exact base-10 arithmetic, 34 significant digits. Doubles accumulate rounding errors; integers-in-cents is a workable alternative.

**Q: How are dates stored? Time zones?**
As a 64-bit signed integer of **milliseconds since the Unix epoch, in UTC**. No time zone is stored; convert on output (`$dateToString` with `timezone`, or in the app). Never store dates as strings — they cannot be compared to Date values or used in date arithmetic.

**Q: What is the difference between `null` and a missing field? How do you query each?**
Missing = the key is not in the document; `null` = the key exists with value null. `{ f: null }` matches both. `{ f: { $exists: false } }` = missing only; `{ f: { $type: "null" } }` = explicit null only; `{ f: { $exists: true, $ne: null } }` = has a real value.

**Q: How does MongoDB compare values of different types?**
By a fixed type order (null < numbers < strings < objects < arrays < … < dates …). Comparison operators like `$gt` only match values in the *same* type bracket, so `{ age: { $gt: 18 } }` never matches the string `"20"`.

**Q: What is the maximum document size? What if you need more?**
16 MB. Redesign (split into a child collection, bucket pattern) or use GridFS for binary files (chunks of 255 KB).

**Q: Can you use your own `_id`? Any restrictions?**
Yes — any BSON type except array (and regex/undefined). Must be unique; cannot be updated. Natural keys (`"EMP-101"`, email) are fine if they never change.

**Q: What is the difference between `Date` and `Timestamp` in MongoDB?**
`Date` is the application date/time type (UTC ms). `Timestamp` is an internal 64-bit type (seconds + ordinal) used by the oplog and replication; do not use it in your schema.

## 5. Checklist

- [ ] I can insert one / many documents and read `insertedId(s)` from the result
- [ ] I know what `ordered: false` changes and that `insertMany` is not atomic
- [ ] I can name the 4 numeric BSON types and know which one a plain JS number becomes
- [ ] I store money as `NumberDecimal` and dates as `Date` (UTC), never as strings
- [ ] I can query by type with `$type`, and tell `null` from missing with `$exists`
- [ ] I know the type comparison order and why `$gt` ignores other types
- [ ] I know why `{ address: { city: "Delhi" } }` fails and use dot notation instead
