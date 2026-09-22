# Level 04 — Projection, Sort, Limit, Skip, Count & Distinct

**Goal:** shape the result of a `find()` exactly like a SQL `SELECT … ORDER BY … OFFSET/FETCH`: choose fields (including inside arrays and computed ones), sort correctly (ties, missing values, case), paginate the right way, and count / list distinct values.

**Time:** ~1.5 hr · **Files:** `01_Practice_Projection.js` → `02_Practice_Sort_Limit_Skip_Count.js` → `Exercises.js`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Projection** | 2nd argument of `find` / `findOne`: which fields to return. `{ name: 1, salary: 1 }` = **inclusion** (only these + `_id`). `{ salary: 0 }` = **exclusion** (everything else). You cannot mix the two — except `_id: 0` which is always allowed. |
| **Nested projection** | `{ "address.city": 1 }` or `{ address: { city: 1 } }` returns `address: { city: … }` only. |
| **Array projection** | `$slice` (first / last / range of elements), `$elemMatch` (first element matching a condition), `$` (first element matched by the *query*). |
| **Computed projection** | Since 4.4 a projection can contain aggregation expressions: `{ annual: { $multiply: ["$salary", 12] } }`, `$concat`, `$size`, `$cond` … (≈ `SELECT salary * 12 AS annual`). |
| **`sort({ f: 1 })`** | 1 ascending, -1 descending. Several keys: `{ departmentId: 1, salary: -1 }` — **key order matters** (JS object order is preserved). Missing fields sort as `null` (first in ascending order). Type order applies (numbers before strings). Strings compare **byte-wise**: `"Z" < "a"`. |
| **Collation** | `.collation({ locale: "en", strength: 2 })` = case-insensitive comparison / sort. `numericOrdering: true` sorts `"10"` after `"9"`. Can be set on an index or a collection too. |
| **Sort stability** | Ties are returned in **undefined** order and may change between runs → always add a unique tiebreaker (`_id`) when paginating. |
| **`limit(n)` / `skip(n)`** | ≈ `TOP n` / `OFFSET n`. Server applies **sort → skip → limit** regardless of the order you chain the methods. `skip` still reads and discards the skipped documents → slow for large offsets. |
| **Keyset (range) pagination** | Remember the last sort value / `_id` and query `{ _id: { $gt: last } }.limit(n)` — O(page) instead of O(offset). |
| **Counting** | `countDocuments(filter)` = accurate, runs the query. `estimatedDocumentCount()` = from collection metadata, instant, no filter (can be off after crashes / on sharded clusters). `cursor.count()` is deprecated. |
| **`distinct("field", filter)`** | Unique values of a field (≈ `SELECT DISTINCT`). Arrays are **flattened** (each element counted). Returns a JS array; limited to 16 MB → use `$group` for big results. |
| **Natural order** | Without `sort`, documents come back in storage order (usually insertion order, **not guaranteed**). Never rely on it. |

### SQL → MongoDB

| SQL | MongoDB |
|-----|---------|
| `SELECT name, salary FROM e` | `db.e.find({}, { _id: 0, name: 1, salary: 1 })` |
| `SELECT * EXCEPT salary` (conceptually) | `db.e.find({}, { salary: 0 })` |
| `SELECT salary * 12 AS annual` | `db.e.find({}, { annual: { $multiply: ["$salary", 12] } })` |
| `ORDER BY dept, salary DESC` | `.sort({ departmentId: 1, salary: -1 })` |
| `ORDER BY name COLLATE …_CI` | `.sort({ name: 1 }).collation({ locale: "en", strength: 2 })` |
| `SELECT TOP 5` | `.limit(5)` |
| `OFFSET 10 ROWS FETCH NEXT 5` | `.skip(10).limit(5)` (needs `.sort`) |
| `SELECT COUNT(*) WHERE …` | `db.e.countDocuments({ … })` |
| `SELECT COUNT(*)` (approx, fast) | `db.e.estimatedDocumentCount()` |
| `SELECT DISTINCT city` | `db.e.distinct("address.city")` |
| `SELECT TOP 1 … ORDER BY salary DESC` | `db.e.find().sort({ salary: -1 }).limit(1)` or `findOne({}, {}, { sort: { salary: -1 } })` |

## 2. Syntax cheat-sheet

```js
db.employees.find({}, { name: 1, salary: 1 })                  // include (+ _id)
db.employees.find({}, { _id: 0, name: 1 })                     // include without _id
db.employees.find({}, { address: 0, skills: 0 })               // exclude
db.employees.find({}, { name: 1, "address.city": 1 })          // nested include
db.employees.find({}, { name: 1, skills: { $slice: 2 } })      // first 2 elements ($slice: -1 = last, [1, 2] = skip 1 take 2)
db.orders.find({ "items.qty": { $gte: 2 } }, { "items.$": 1 }) // only the first array element matched by the query
db.orders.find({}, { items: { $elemMatch: { productId: 2 } } })// first element matching this condition
db.employees.find({}, { name: 1, annual: { $multiply: ["$salary", 12] }, nSkills: { $size: { $ifNull: ["$skills", []] } } })

db.employees.find().sort({ salary: -1 })
db.employees.find().sort({ departmentId: 1, salary: -1, _id: 1 })
db.employees.find().sort({ name: 1 }).collation({ locale: "en", strength: 2 })
db.employees.find().sort({ salary: -1 }).limit(3)
db.employees.find().sort({ _id: 1 }).skip(5).limit(5)          // page 2 of 5
db.employees.find({ _id: { $gt: 105 } }).sort({ _id: 1 }).limit(5)   // keyset pagination
db.employees.findOne({}, { name: 1 }, { sort: { salary: -1 } })      // options object form

db.employees.countDocuments({ departmentId: 1 })
db.employees.countDocuments({}, { skip: 10, limit: 5 })
db.employees.estimatedDocumentCount()
db.employees.distinct("departmentId")
db.employees.distinct("skills", { departmentId: 1 })
db.employees.distinct("address.city")
```

## 3. Gotchas

- **Inclusion and exclusion cannot be mixed** (`{ name: 1, salary: 0 }` → error) — only `_id: 0` may join an inclusion list.
- **Projection is not a filter.** `{ "items.$": 1 }` needs the array condition in the *query*; `$elemMatch` in the projection returns the document even when no element matches (the field is just absent).
- **`skip` is O(n)**: page 1000 of 20 reads 20 000 documents. Use keyset pagination for deep pages / infinite scroll.
- **Chaining order does not matter**: `find().limit(2).sort({salary:-1})` still sorts *everything* first. (Aggregation stages, by contrast, run in the order written.)
- **Sort without an index on large data** happens in memory, limited to **100 MB** (error "Sort exceeded memory limit") — create an index on the sort key (Level 11) or `allowDiskUse` in aggregation.
- **Missing field sorts first ascending** (as null), last descending. Mixed types sort by type order.
- **`"Zebra" < "apple"`** in default binary sort; use a collation for human ordering.
- **`distinct` on an array field returns elements, not arrays**, and has a 16 MB result limit.
- **`estimatedDocumentCount` ignores filters** and can be stale/inaccurate; `countDocuments({})` is exact but scans (uses the `_id` index).
- **`limit(0)`** means no limit; a **negative** limit is a legacy "single batch" flag — do not use.

## 4. Interview questions

**Q: How do you select specific fields? Can you include and exclude at the same time?**
Projection document: `{ a: 1, b: 1 }` includes, `{ a: 0 }` excludes. They cannot be mixed except `_id: 0` with an inclusion list.

**Q: How do you paginate in MongoDB? What is wrong with `skip`?**
`sort().skip(pageSize*(page-1)).limit(pageSize)` works but skip scans and discards the skipped documents (cost grows with the page number). Prefer **keyset / range pagination**: sort on an indexed unique key and query `{ key: { $gt: lastSeen } }.limit(n)`.

**Q: `countDocuments` vs `estimatedDocumentCount` vs `count`?**
`countDocuments(filter)` runs an aggregation → accurate, accepts a filter. `estimatedDocumentCount()` reads collection metadata → instant, no filter, may be inexact after an unclean shutdown. `count()` (cursor / collection) is deprecated because it used metadata for `{}` and could be wrong on sharded clusters.

**Q: Does the order of `sort` / `limit` / `skip` calls matter?**
No — they are cursor *modifiers*; the server always applies sort, then skip, then limit. In the aggregation pipeline the order of `$sort` / `$skip` / `$limit` **does** matter.

**Q: How do you sort case-insensitively?**
With a collation: `.collation({ locale: "en", strength: 2 })` (strength 1–2 ignores case / diacritics). For performance, create the index with the same collation. Alternative: store a lowercased copy of the field.

**Q: How do you get only the matching elements of an array?**
In `find`: projection `$` (first element matched by the query) or `$elemMatch` / `$slice` (first n). For *all* matching elements use aggregation `$filter` (Level 09).

**Q: How do you get the top-N per group?**
Not with `find` — aggregation: `$sort` + `$group` with `$firstN` / `$topN`, or `$setWindowFields` with `$rank` (Level 09).

**Q: Why should you always add `_id` to a sort used for pagination?**
Because documents with equal sort values have no guaranteed order; pages could show duplicates or skip rows between requests. A unique tiebreaker makes the order deterministic.

## 5. Checklist

- [ ] I can include / exclude fields, drop `_id`, and project nested fields
- [ ] I can use `$slice`, `$elemMatch` and `$` in a projection and know their differences
- [ ] I can add a computed field in a projection
- [ ] I can sort on several keys, know how missing values and strings sort, and use a collation
- [ ] I can paginate with skip/limit and with keyset pagination, and explain why the second scales
- [ ] I know the three ways to count and when each is right
- [ ] I can list distinct values (also of an array or nested field)
