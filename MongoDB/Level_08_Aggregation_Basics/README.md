# Level 08 — Aggregation Basics

**Goal:** think in **pipelines**: filter, reshape, group and sort documents with `$match`, `$project`/`$set`, `$group`, `$sort`, `$limit`, `$skip`, `$count`, `$sortByCount` — everything `GROUP BY / HAVING / ORDER BY / TOP` does in SQL, and more.

**Time:** ~2.5 hr · **Files:** `01_Practice_Match_Project_Group.js` → `02_Practice_Sort_Limit_Patterns.js` → `Exercises.js`

---

## 1. Concepts in plain words

| Term | Meaning |
|------|---------|
| **Pipeline** | `db.coll.aggregate([ stage1, stage2, … ])`. Documents flow through the stages **in the order written**; each stage receives the output of the previous one. Returns a cursor. |
| **Stage** | `{ $stageName: { … } }`. A stage can appear several times (`$match` early and late). |
| **Expression** | Anything computed inside a stage: `"$salary"` (field value), `"$address.city"`, `{ $multiply: ["$price", "$qty"] }`, literals, `"$$ROOT"` (the whole document), `"$$NOW"`. **A string starting with `$` is a field path**; to use a literal `$…` string use `{ $literal: "$x" }`. |
| **`$match`** | filter, same syntax as `find`. Put it **first** so it can use indexes and shrink the data. After `$group` it acts as `HAVING`. Use `$expr` for computed conditions. |
| **`$project`** | choose / rename / compute fields (`1`, `0`, expression). An inclusion project drops everything else. |
| **`$set` / `$addFields`** | add or overwrite fields, **keep** the rest (nicer than `$project` for "add one column"). `$unset` removes fields. |
| **`$group`** | `{ $group: { _id: <group key>, out1: { $acc: expr }, … } }`. `_id: null` = one group for everything. `_id: "$dept"` or `_id: { d: "$dept", c: "$city" }` for compound keys. Output has **only** `_id` and the accumulators. |
| **Accumulators** | `$sum` (`$sum: 1` = COUNT), `$avg`, `$min`, `$max`, `$count: {}`, `$first`, `$last` (need a `$sort` before), `$push` (array of values), `$addToSet` (distinct values), `$mergeObjects`, `$stdDevPop/Samp`, `$firstN`, `$lastN`, `$topN`, `$bottomN`, `$maxN`, `$minN` (5.2+). |
| **`$sort`** | `{ $sort: { total: -1, _id: 1 } }`. Memory limit 100 MB → `allowDiskUse: true` or an index. |
| **`$limit` / `$skip`** | order matters here: `$sort → $skip → $limit`. `$sort` + `$limit` next to each other are optimised (top-k, low memory). |
| **`$count`** | `{ $count: "n" }` → one document `{ n: 42 }`. |
| **`$sortByCount`** | `{ $sortByCount: "$status" }` = `$group` by value + `$sum: 1` + `$sort` desc. |
| **Blocking stages** | `$group`, `$sort` (without index), `$bucket`, `$facet` need all input before emitting — memory bound, `allowDiskUse` spills to disk. |

### SQL → aggregation

| SQL | Stage |
|-----|-------|
| `WHERE` | `$match` (before `$group`) |
| `SELECT a, b, a*b AS c` | `$project` / `$set` |
| `GROUP BY dept` | `$group: { _id: "$dept" }` |
| `COUNT(*)`, `SUM(x)`, `AVG(x)`, `MIN`, `MAX` | `$sum: 1`, `$sum: "$x"`, `$avg`, `$min`, `$max` |
| `COUNT(DISTINCT x)` | `$group` by x, then `$count` (or `$addToSet` + `$size`) |
| `HAVING SUM(x) > 100` | `$match` **after** `$group` |
| `ORDER BY` | `$sort` |
| `TOP n` / `OFFSET-FETCH` | `$limit` / `$skip` + `$limit` |
| `SELECT COUNT(*) FROM (...)` | `$count` |
| `CASE WHEN` inside `SUM` (conditional aggregation) | `$sum: { $cond: [cond, 1, 0] }` |
| `STRING_AGG(name, ',')` | `$push` then `$reduce`/`$concat` (or `$group` + `$push`) |
| `SELECT status, COUNT(*) ... ORDER BY 2 DESC` | `$sortByCount: "$status"` |
| `JOIN` | `$lookup` (Level 09) |
| window functions | `$setWindowFields` (Level 09) |

## 2. Syntax cheat-sheet

```js
db.employees.aggregate([
    { $match: { active: true } },
    { $group: { _id: "$departmentId", n: { $sum: 1 }, avgSalary: { $avg: "$salary" }, maxSalary: { $max: "$salary" },
                names: { $push: "$name" }, cities: { $addToSet: "$address.city" } } },
    { $match: { n: { $gte: 2 } } },                       // HAVING
    { $sort: { avgSalary: -1 } },
    { $limit: 3 },
    { $project: { _id: 0, departmentId: "$_id", n: 1, avgSalary: { $round: ["$avgSalary", 0] } } }
])

{ $group: { _id: null, total: { $sum: "$salary" } } }                          // grand total
{ $group: { _id: { dept: "$departmentId", city: "$address.city" }, n: { $sum: 1 } } }   // compound key
{ $group: { _id: { $year: "$hireDate" }, n: { $sum: 1 } } }                    // key = expression
{ $group: { _id: "$departmentId", top: { $first: "$name" } } }                  // after { $sort: { salary: -1 } }
{ $group: { _id: "$departmentId", top2: { $topN: { n: 2, sortBy: { salary: -1 }, output: "$name" } } } }
{ $group: { _id: "$customerId", completed: { $sum: { $cond: [{ $eq: ["$status", "Completed"] }, 1, 0] } } } }
{ $count: "totalOrders" }
{ $sortByCount: "$status" }
{ $set: { annual: { $multiply: ["$salary", 12] } } }      // keeps all other fields
{ $unset: ["address", "skills"] }
{ $project: { name: 1, city: "$address.city", _id: 0 } } // rename by projection
db.orders.aggregate(pipeline, { allowDiskUse: true })
db.orders.aggregate(pipeline).explain("executionStats")
```

## 3. Gotchas

- **Order matters.** `[$limit, $sort]` ≠ `[$sort, $limit]`. `$match` before `$group` filters rows; after `$group` filters groups.
- **`$group` throws away every field** that is not `_id` or an accumulator. Want the whole document? `$push: "$$ROOT"` or `$first: "$$ROOT"`.
- **`$first` / `$last` are meaningless without `$sort`** right before the `$group` (they take the first document *in pipeline order*).
- **`$sum` of a non-numeric or missing field counts as 0**, `$avg` ignores missing/non-numeric values (so `$avg` of nothing → `null`).
- **`"$name"` vs `"name"`**: in expressions, `"name"` is the literal string `"name"`. A missing `$` is the number-one aggregation bug.
- **`_id` in `$group` output is the key** — rename it in a later `$project` (`dept: "$_id"`) for readable output.
- **Grouping by a nested / array field**: an array key groups by the *whole array*, not per element — `$unwind` first (Level 09).
- **100 MB per stage** in memory; pass `{ allowDiskUse: true }` for big `$group`/`$sort`, or add an index so `$sort` is not needed.
- **`$project` with only exclusions cannot compute** — use `$set` + `$unset` when you want to add a field and drop another.
- **Type mismatches in `$match` after `$group`** — the accumulator's output type (e.g. Decimal128 vs double) is what you compare against.
- **The pipeline result is a cursor**; in scripts call `.toArray()` / `.forEach()`.

## 4. Interview questions

**Q: What is the aggregation pipeline?**
A sequence of stages that transform documents step by step (filter, reshape, group, sort, join…), like a Unix pipe. It is MongoDB's `GROUP BY` / reporting engine and runs server-side, using indexes for early `$match`/`$sort`.

**Q: `$match` vs `find`? Where should `$match` go?**
Same filter syntax; `$match` is a stage in a pipeline. Put it as early as possible so it uses indexes and reduces the documents flowing into expensive stages. A `$match` after `$group` is `HAVING`.

**Q: `$project` vs `$addFields`/`$set`?**
`$project` builds a new shape (inclusion drops unlisted fields). `$set`/`$addFields` add or overwrite fields and keep everything else. `$unset` removes fields.

**Q: How do you count documents per group and overall?**
Per group: `$group: { _id: "$f", n: { $sum: 1 } }` (or `$count: {}`). Overall: `$group: { _id: null, n: { $sum: 1 } }` or the `$count` stage.

**Q: How do you do `COUNT(DISTINCT)`?**
`$group` by the field, then `$count`; or `$group: { _id: null, s: { $addToSet: "$f" } }` then `{ $project: { n: { $size: "$s" } } }`.

**Q: How is `HAVING` written?**
A `$match` stage after `$group` on the accumulator fields.

**Q: What is a blocking stage and what is the memory limit?**
A stage that must see all input before producing output: `$group`, `$sort` (no index), `$bucket`, `$facet`. Each stage may use 100 MB of RAM; with `allowDiskUse: true` it spills to disk. Prefer indexes for `$sort` and early `$match` to keep data small.

**Q: How do you get the highest-paid employee per department?**
`$sort: { salary: -1 }` then `$group: { _id: "$departmentId", top: { $first: "$$ROOT" } }`; or `$topN` / `$firstN` accumulators; or `$setWindowFields` with `$rank` (Level 09).

**Q: Conditional aggregation (pivot-like counts)?**
`$sum: { $cond: [ { $eq: ["$status", "Completed"] }, 1, 0 ] }` inside `$group` — one accumulator per bucket.

## 5. Checklist

- [ ] I can explain a pipeline and why stage order matters
- [ ] I can write `$match`, `$project`, `$set`, `$unset` with expressions and field paths
- [ ] I can `$group` by null / field / compound key / expression with every common accumulator
- [ ] I can write `HAVING`, `COUNT(DISTINCT)`, conditional aggregation and top-N per group
- [ ] I know `$first/$last` need `$sort`, `$group` drops fields, and `$$ROOT` keeps the document
- [ ] I know the 100 MB limit and `allowDiskUse`
