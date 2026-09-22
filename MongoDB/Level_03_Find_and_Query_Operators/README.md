# Level 03 — Find & Query Operators

**Goal:** write any `WHERE` clause you could write in SQL as a MongoDB filter document: comparison, logical, element, regex, `$expr`, nested fields and simple array conditions — and understand the cursor `find()` returns.

**Time:** ~2 hr · **Files:** `01_Practice_Filtering.js` → `02_Practice_Regex_Expr_Nested.js` → `Exercises.js`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **`find(filter, projection)`** | Returns a **cursor** over every document matching `filter` (`{}` = all). The shell prints the first 20 documents; type `it` for more. `projection` chooses fields (Level 04). |
| **`findOne(filter)`** | Returns the **first** matching document (or `null`) — a document, not a cursor. Same filter syntax. |
| **Filter document** | `{ field: value }` = equality. `{ field: { $op: value } }` = operator. Several fields in one document = **AND**. |
| **Comparison** | `$eq $ne $gt $gte $lt $lte $in $nin` — compare only within the same type bracket (numbers with numbers…). `$ne` / `$nin` **also match documents where the field is missing**. |
| **Logical** | `$and: [ … ]`, `$or: [ … ]`, `$nor: [ … ]`, `$not: { op }` (field-level). You need explicit `$and` only when the same field / operator appears twice. |
| **Element** | `$exists: true/false` (is the key present), `$type: "string"` (Level 02). |
| **Evaluation** | `$regex` (pattern match ≈ `LIKE`), `$expr` (use aggregation expressions — compare two fields of the same document), `$mod`, `$jsonSchema`, `$where` (JS — slow, avoid), `$text` (needs a text index, Level 11). |
| **Dot notation** | `"address.city"`, `"items.productId"`, `"skills.0"` — reach into embedded documents and arrays. **Quotes are mandatory** because of the dot. |
| **Array matching** | `{ skills: "MongoDB" }` matches if **any element** equals. `{ skills: ["Java", "MongoDB", "NodeJS"] }` matches the **exact array** (same elements, same order). `$all`, `$size`, `$elemMatch` — Level 06. |
| **Cursor** | Lazy, batched (first batch 101 docs / 16 MB). Methods: `toArray() forEach() map() hasNext() next() count() limit() skip() sort()` (Level 04) `explain()` (Level 12). A cursor is exhausted after iteration and times out after 10 min idle. |

### SQL → MongoDB filter

| SQL | MongoDB |
|-----|---------|
| `WHERE a = 1` | `{ a: 1 }` |
| `WHERE a <> 1` | `{ a: { $ne: 1 } }` (also matches missing `a`!) |
| `WHERE a > 1 AND a <= 5` | `{ a: { $gt: 1, $lte: 5 } }` |
| `WHERE a BETWEEN 1 AND 5` | `{ a: { $gte: 1, $lte: 5 } }` |
| `WHERE a IN (1,2,3)` | `{ a: { $in: [1, 2, 3] } }` |
| `WHERE a NOT IN (1,2)` | `{ a: { $nin: [1, 2] } }` |
| `WHERE a = 1 AND b = 2` | `{ a: 1, b: 2 }` |
| `WHERE a = 1 OR b = 2` | `{ $or: [ { a: 1 }, { b: 2 } ] }` |
| `WHERE NOT (a > 5)` | `{ a: { $not: { $gt: 5 } } }` (matches missing too) |
| `WHERE a IS NULL` | `{ a: null }` (null **or** missing) · `{ a: { $type: "null" } }` (null only) |
| `WHERE a IS NOT NULL` | `{ a: { $ne: null } }` |
| `WHERE name LIKE 'Ra%'` | `{ name: /^Ra/ }` or `{ name: { $regex: "^Ra" } }` |
| `WHERE name LIKE '%an%'` | `{ name: /an/ }` |
| `WHERE LOWER(name) = 'rahul'` | `{ name: /^rahul$/i }` or a case-insensitive collation |
| `WHERE colA > colB` | `{ $expr: { $gt: ["$colA", "$colB"] } }` |
| `WHERE id % 2 = 0` | `{ _id: { $mod: [2, 0] } }` |
| `WHERE date >= '2025-03-01' AND date < '2025-04-01'` | `{ orderDate: { $gte: ISODate("2025-03-01"), $lt: ISODate("2025-04-01") } }` |
| `WHERE address.city = 'Delhi'` (JSON column) | `{ "address.city": "Delhi" }` |

## 2. Syntax cheat-sheet

```js
db.employees.find()                                     // everything (cursor)
db.employees.find({})                                   // same
db.employees.findOne({ _id: 101 })                      // one document or null
db.employees.find({ departmentId: 1, salary: { $gte: 60000 } })      // implicit AND
db.employees.find({ salary: { $gt: 60000, $lt: 80000 } })            // range on one field
db.employees.find({ departmentId: { $in: [1, 2] } })
db.employees.find({ $or: [ { departmentId: 1 }, { salary: { $gt: 80000 } } ] })
db.employees.find({ $and: [ { $or: [{ a: 1 }, { b: 1 }] }, { $or: [{ c: 1 }, { d: 1 }] } ] })   // (a OR b) AND (c OR d)
db.employees.find({ salary: { $not: { $gt: 60000 } } })              // <= 60000 OR missing
db.employees.find({ email: { $exists: false } })
db.employees.find({ name: /^ra/i })                                  // regex literal
db.employees.find({ name: { $regex: "^ra", $options: "i" } })        // regex operator form
db.products.find({ $expr: { $gt: [ { $multiply: ["$price", "$stock"] }, 500000 ] } })
db.orders.find({ "payment.paid": false })                            // nested field
db.orders.find({ "items.productId": 1 })                             // any array element's field
db.employees.find({ skills: "MongoDB" })                             // any element equals
db.orders.find({ _id: { $mod: [2, 0] } })                            // even ids

// cursor handling
const cur = db.employees.find({ departmentId: 2 });
cur.hasNext(); cur.next();                        // manual iteration
db.employees.find().toArray()                     // JS array (loads everything into memory)
db.employees.find().forEach(d => print(d.name))
db.employees.find().map(d => d.salary)
db.employees.find({ departmentId: 2 }).count()    // count of matches (cursor.count is deprecated -> countDocuments)
db.employees.countDocuments({ departmentId: 2 })
```

## 3. Gotchas

- **`$ne`, `$nin`, `$not` match documents where the field is missing.** `{ email: { $ne: "x" } }` returns Anjali, who has no email. Add `email: { $exists: true }` if that is not what you want.
- **`{ a: 1, a: 2 }` is not "a=1 AND a=2"** — a JS object keeps only the last key. Use `$and` when the same field appears twice: `{ $and: [{ a: { $gt: 1 } }, { a: { $lt: 5 } }] }` (or better: `{ a: { $gt: 1, $lt: 5 } }`).
- **Same field twice in `$or` branches is fine**; a plain `{ $or: [...] }` at the top level needs no `$and` unless combined with another `$or`.
- **Equality on an array field matches any element** — `{ skills: "SQL" }` is "contains", not "equals". To match the whole array exactly, pass an array.
- **Embedded document equality is exact and order-sensitive** — use dot notation (Level 02).
- **Regex without `^` cannot use an index efficiently** (`/an/` scans every string). `/^ra/` can use the index on `name`. `/^ra/i` (case-insensitive) cannot use a normal index — use a collation index or store a lowercase copy.
- **`$expr` compares fields of the *same* document** (`"$price"` syntax). It runs after index scans in most cases → slower on big collections; prefer plain operators when possible.
- **`$where` runs JavaScript on the server** — slow, no index, security risk. Avoid; use `$expr`.
- **Type bracketing:** `{ stock: { $lt: 10 } }` ignores a stock stored as `"7"` (string). Fix the data, not the query.
- **`find()` returns a cursor, not data.** `const x = db.c.find(); x.count(); x.toArray()` — after `toArray()` the cursor is used up. **`cursor.map()` returns another cursor** (it only *prints* like an array) — add `.toArray()` when you need a real array (`$in`, `.length`).
- **`findOne` with no match returns `null`** (not an error). `find` with no match returns an empty cursor (prints nothing).
- **Dates:** `{ orderDate: ISODate("2025-01-05") }` matches only exactly midnight UTC. Use ranges `$gte … $lt next day`.

## 4. Interview questions

**Q: How do you write `WHERE a = 1 AND (b = 2 OR c = 3)`?**
`{ a: 1, $or: [ { b: 2 }, { c: 3 } ] }` — top-level fields are ANDed; `$or` takes an array of sub-filters.

**Q: `$in` vs `$or`?**
`$in` = one field, list of values (uses an index efficiently, one index scan with multiple bounds). `$or` = different conditions, possibly different fields; each branch can use its own index. Prefer `$in` for the same field.

**Q: What does `$ne` do with documents that lack the field?**
It matches them (missing ≠ value). Same for `$nin` and `$not`. Combine with `$exists: true` when needed.

**Q: How do you query a field inside an embedded document / an array of embedded documents?**
Dot notation in quotes: `{ "address.city": "Delhi" }`, `{ "items.productId": 1 }` (matches if any element has that productId). For several conditions on the *same* element use `$elemMatch` (Level 06).

**Q: How is `LIKE` done? Can it use an index?**
`$regex` / regex literal. `/^abc/` (anchored prefix, case-sensitive) can use a B-tree index like `LIKE 'abc%'`; `/abc/` or `/^abc/i` cannot (full index scan). For full-text search use a text index or Atlas Search.

**Q: What is `$expr` for?**
Using aggregation expressions inside a query — mainly to compare two fields of the same document (`{ $expr: { $gt: ["$spent", "$budget"] } }`) or compute (`$multiply`, `$size`). Plain operators cannot reference another field.

**Q: What is a cursor? How does batching work?**
`find()` returns a cursor: the server sends the first batch (101 docs or 16 MB) and the client fetches more with `getMore` as you iterate. Cursors time out after 10 minutes idle (`noCursorTimeout` exists but is dangerous). `toArray()` pulls everything into memory — fine for small results, bad for millions.

**Q: How do you query for null / missing / existing values?**
`{ f: null }` → null or missing. `{ f: { $exists: false } }` → missing. `{ f: { $type: "null" } }` → explicitly null. `{ f: { $ne: null } }` → has a value.

**Q: Why is `{ a: { $gt: 5 } }` not matching my document with `a: "10"`?**
Type bracketing: comparison operators only match values of the same BSON type family (numbers with numbers). `"10"` is a string. Store numbers as numbers.

## 5. Checklist

- [ ] I can translate every `WHERE` in the SQL→MongoDB table from memory
- [ ] I know when `$and` is needed and when implicit AND is enough
- [ ] I know that `$ne` / `$nin` / `$not` match missing fields
- [ ] I can query nested fields and array elements with dot notation
- [ ] I can write `LIKE` patterns as regexes and know which ones use an index
- [ ] I can compare two fields with `$expr`
- [ ] I know what a cursor is and can iterate it with `forEach` / `toArray` / `next`
