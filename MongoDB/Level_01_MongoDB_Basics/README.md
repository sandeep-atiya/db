# Level 01 — MongoDB Basics

**Goal:** understand what MongoDB is (and is not), speak its vocabulary, move around with `mongosh`, and create / inspect / drop databases and collections.

**Time:** ~45 min · **Files:** `01_Practice.js` → `Exercises.js`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **MongoDB** | A **document database**: data is stored as JSON-like documents (BSON), not as rows in fixed tables. "NoSQL" = *not only SQL*: no fixed schema, no SQL joins by default, built to scale out (replica sets, sharding). |
| **mongod** | The **server** process (like `sqlservr.exe`). Default port **27017**. A group of `mongod`s = a **replica set**. `mongos` = the router in a sharded cluster. |
| **mongosh** | The **shell** (like SSMS query window + sqlcmd). It is a JavaScript REPL: every command is JavaScript. `mongosh` connects to `localhost:27017` by default. |
| **Compass** | The GUI (like SSMS Object Explorer): browse documents, run queries and aggregations visually, explain plans, embedded shell. |
| **Drivers** | Libraries for Node.js, Python, Java, C#, … Same commands, same JSON syntax (Level 19). |
| **Database** | A container of collections. Created **lazily**: `use x` does nothing until the first document is stored. System databases: `admin` (users, roles, cluster commands), `local` (oplog, replica-set data – never replicated), `config` (sharding metadata). |
| **Collection** | A group of documents (≈ table) — but documents in one collection **can have different fields**. Created implicitly on first insert or explicitly with `db.createCollection()` (needed for options: validator, capped, collation). |
| **Document** | One record (≈ row), a BSON object: `{ _id: 101, name: "Rahul", skills: ["Java"], address: { city: "Delhi" } }`. Max size **16 MB**. Field order is preserved. |
| **Field** | Key/value pair (≈ column). Values can be scalars, **arrays** or **embedded documents** (nesting) — this is what makes the model different from SQL. |
| **`_id`** | Every document has a unique `_id` (≈ primary key). If you do not supply one, MongoDB generates an **ObjectId**. It is immutable and automatically indexed. |
| **ObjectId** | 12 bytes: 4-byte Unix timestamp + 5-byte random (per process) + 3-byte counter → globally unique, roughly sortable by creation time (`ObjectId().getTimestamp()`). |
| **BSON** | *Binary JSON* — how MongoDB stores and transmits documents. Adds types JSON lacks: Date, ObjectId, Int32/Int64, Decimal128, Binary, Regex. `mongosh` shows BSON as JavaScript-ish output. |
| **Flexible schema** | The database does not enforce a structure (unless you add validation, Level 13). Your **application** owns the schema. "Schema-less" ≠ "no design". |
| **Namespace** | `database.collection` (`companyDB.employees`). Names are case-sensitive; collection names cannot contain `$` or start with `system.`; db names cannot contain `/\. "$*<>:|?` and are limited to 63 bytes. |

### SQL Server → MongoDB vocabulary

| SQL Server | MongoDB | Notes |
|-----------|---------|-------|
| Instance / server | `mongod` / replica set | |
| Database | Database | same idea |
| Table | **Collection** | |
| Row | **Document** | |
| Column | **Field** | can be nested / array |
| Primary key | `_id` | always present, always indexed |
| Foreign key + JOIN | **Embed** the data, or store a reference and use `$lookup` | Levels 09 & 13 |
| Index | Index | same B-tree idea (Level 11) |
| `SELECT … WHERE` | `find(filter, projection)` | Levels 03–04 |
| `GROUP BY`, `HAVING`, window functions | Aggregation pipeline `$group`, `$match`, `$setWindowFields` | Levels 08–09 |
| `INSERT / UPDATE / DELETE` | `insertOne/Many`, `updateOne/Many`, `deleteOne/Many` | Levels 02, 05, 07 |
| Transaction | Multi-document transaction (needs replica set) | Level 14 |
| Schema (`dbo`) | *(none)* — one flat namespace per database | |
| `CHECK` / `NOT NULL` constraints | `$jsonSchema` validator (optional) | Level 13 |
| Stored procedure / function | *(none)* — logic lives in the application | |
| View | View (`db.createView`) = saved aggregation | |
| `GO` / batch | *(none)* — mongosh runs JavaScript line by line | |

## 2. Syntax cheat-sheet

```js
// CONNECT
mongosh                                   // localhost:27017
mongosh "mongodb://localhost:27017/companyDB"
mongosh --host localhost --port 27017 -u user -p --authenticationDatabase admin

// LOOK AROUND (shell commands - as functions they also work in scripts / playgrounds)
show dbs            show("dbs")           // databases WITH data (empty ones are invisible)
use companyDB       use("companyDB")      // switch (creates lazily)
db                  db.getName()          // current database
show collections    show("collections")   // or db.getCollectionNames()
db.version()        db.hello()            // server version, replica-set role
db.stats()          db.employees.stats()  // sizes, counts, indexes
db.runCommand({ ping: 1 })                // any database command
db.adminCommand({ listDatabases: 1 })     // commands that run on "admin"
db.getSiblingDB("admin")                  // another db without switching

// CREATE / DROP
db.createCollection("logs")                                   // explicit
db.createCollection("events", { capped: true, size: 1048576, max: 1000 })   // fixed-size ring buffer
db.logs.insertOne({ msg: "hi" })                               // implicit: db + collection appear now
db.logs.renameCollection("app_logs")
db.app_logs.drop()                                             // collection + its indexes
db.dropDatabase()                                              // current database (no "must leave first" rule)

// HELP
help                db.help()             db.employees.help()
db.employees.find().help()                // cursor methods
```

## 3. Gotchas (things that bite beginners)

- **`use newdb` creates nothing.** The database (and collection) appear only after the first insert. `show dbs` will not list it until then.
- **Case matters everywhere:** `db.Employees` and `db.employees` are two different collections. Field names too: `{ Name: 1 }` ≠ `{ name: 1 }`.
- **No error for a typo in a collection name.** `db.employes.find()` simply returns nothing — there is no "invalid object name". Check `show collections`.
- **`_id` cannot be changed** after insert (delete + insert instead) and must be unique — a duplicate gives `E11000 duplicate key error`.
- **Everything is JavaScript.** Missing quotes around a key are fine (`{name: "x"}`), but strings need quotes, `=` is assignment, `==` is comparison, and `db.employees.find` **without `()`** prints the function instead of running it.
- **In scripts / playgrounds** use `use("db")` and `show("collections")` — the bare `use db` form is only for typing in the interactive shell.
- **A bare `find()` in a `--file` script prints nothing.** Wrap in `printjson()` / `print()` or run block by block.
- **Number types are decided for you.** In `mongosh` / Node.js a whole number that fits in 32 bits (`85000`) is stored as **int**, anything else (`3.5`, `1e10`) as **double**. Use `NumberLong` / `NumberDecimal` when you need 64-bit integers or exact money values (Level 02).
- **`show dbs` hides empty databases** and needs the `listDatabases` privilege — with auth on, a plain user may see only its own db.

## 4. Interview questions

**Q: What is MongoDB? How is it different from a relational database?**
A document-oriented NoSQL database. Data is stored as BSON documents in collections instead of rows in tables; documents can nest arrays and sub-documents and need not share a schema. Relationships are modelled by embedding or by references (`$lookup`), not by foreign keys and JOINs. It scales horizontally with replica sets (HA) and sharding (capacity).

**Q: Database vs collection vs document?**
Database = container of collections. Collection = group of documents (≈ table, no fixed columns). Document = one BSON record (≈ row) with fields, arrays and embedded documents, max 16 MB, always with a unique `_id`.

**Q: What is BSON? Why not plain JSON?**
Binary JSON: a binary encoding that is fast to traverse and adds types JSON does not have (Date, ObjectId, Int32/Int64, Decimal128, Binary, Regex). Documents are stored, indexed and sent over the wire as BSON.

**Q: What is `_id`? What is an ObjectId?**
`_id` is the mandatory, unique, immutable primary-key field of every document, automatically indexed. If you do not set it, the driver generates a 12-byte ObjectId (timestamp + random + counter), which is globally unique without a central sequence and sortable by creation time.

**Q: What does "schema-less" really mean?**
The server does not enforce field names or types (unless you add `$jsonSchema` validation). Documents in one collection can differ. The schema is designed and enforced by the application (or Mongoose). It gives flexibility for evolving data — it does **not** mean you skip data modelling.

**Q: When would you choose MongoDB over SQL Server (and vice versa)?**
MongoDB: hierarchical / variable data (catalogs, profiles, events, IoT, content), rapid schema evolution, horizontal scale, JSON-native apps. SQL Server: highly relational data with many-to-many relationships, complex multi-table transactions and reporting, strict integrity constraints, existing SQL tooling.

**Q: What are the system databases?**
`admin` (users, roles, server-wide commands), `local` (oplog and replica-set metadata, never replicated), `config` (sharded-cluster metadata). Never store application data in them.

**Q: What is a capped collection?**
A fixed-size collection that keeps insertion order and overwrites the oldest documents when full (ring buffer). Used for logs / the oplog. Cannot delete individual documents or shard it.

## 5. Checklist

- [ ] I can explain database / collection / document / field / `_id` / BSON in one sentence each
- [ ] I can map every SQL Server term to its MongoDB equivalent
- [ ] I can connect with `mongosh`, list databases and collections, and switch databases
- [ ] I know that databases and collections are created lazily and are case-sensitive
- [ ] I can create a collection explicitly (incl. capped), rename it and drop it
- [ ] I can inspect an ObjectId and explain its 12 bytes
- [ ] I know which shell commands become functions in scripts (`use()`, `show()`)
