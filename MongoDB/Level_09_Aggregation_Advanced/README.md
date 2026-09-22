# Level 09 — Aggregation Advanced

**Goal:** do everything SQL joins, window functions, subqueries, PIVOT, UNION and materialised views do — the MongoDB way: `$unwind`, `$lookup` (incl. correlated pipelines), `$graphLookup`, `$setWindowFields`, `$facet`, `$bucket`, array expressions (`$map`, `$filter`, `$reduce`, `$arrayToObject`), `$unionWith`, `$out` / `$merge` and views.

**Time:** ~4 hr · **Files:** `01_Practice_Unwind_Lookup.js` → `02_Practice_Window_Facet_Bucket.js` → `03_Practice_Array_Expressions_Out_Merge_Views.js` → `Exercises.js`

---

## 1. Concepts in plain words

| Stage / operator | Meaning | SQL equivalent |
|------------------|---------|----------------|
| **`$unwind: "$items"`** | one output document **per array element** (the element replaces the array). Documents with a missing / empty array are **dropped** unless `preserveNullAndEmptyArrays: true`. `includeArrayIndex: "i"` adds the position. | `CROSS APPLY` / `OPENJSON` on a JSON column |
| **`$lookup`** (equality) | `{ from, localField, foreignField, as }` → adds an **array** of matching documents from another collection (same database). Empty array = no match (LEFT JOIN behaviour). | `LEFT OUTER JOIN` |
| **`$lookup`** (pipeline) | `{ from, let: { v: "$field" }, pipeline: [ { $match: { $expr: … "$$v" … } }, … ], as }` → join on any condition, filter / project / limit the joined side. Since 5.0 `localField`/`foreignField` and `pipeline` can be combined. | correlated subquery / `JOIN … ON complex` / `APPLY` |
| **`$graphLookup`** | recursive traversal: `startWith`, `connectFromField`, `connectToField`, `as`, `maxDepth`, `depthField` | recursive CTE |
| **`$setWindowFields`** | `{ partitionBy, sortBy, output: { f: { $op: …, window: { documents: [a, b] } } } }` — `$rank`, `$denseRank`, `$documentNumber`, `$sum`/`$avg` (running / moving), `$shift` (LAG/LEAD), `$first`, `$last`, `$push`, `$expMovingAvg`, `$derivative`, `$locf` | window functions `OVER (PARTITION BY … ORDER BY … ROWS …)` |
| **`$facet`** | several sub-pipelines on the same input, one output document with one array per facet | several queries / `GROUPING SETS` |
| **`$bucket` / `$bucketAuto`** | histogram by boundaries / automatic N buckets | `CASE` ranges + `GROUP BY` / `NTILE` |
| **`$replaceRoot` / `$replaceWith`** | promote an embedded document (or a `$mergeObjects`) to be the whole document | — |
| **`$unionWith`** | append documents of another collection / pipeline | `UNION ALL` |
| **`$out`** | write the result to a collection, **replacing** it | `SELECT INTO` |
| **`$merge`** | write / upsert results into a collection (`whenMatched: replace \| merge \| keepExisting \| fail \| pipeline`, `whenNotMatched: insert \| discard \| fail`) | `MERGE` / incremental materialised view |
| **View** | `db.createView(name, source, pipeline)` — a saved, read-only aggregation | `CREATE VIEW` |
| **Array expressions** | `$size $arrayElemAt $first $last $slice $filter $map $reduce $concatArrays $setUnion $setIntersection $setDifference $setIsSubset $in $indexOfArray $range $zip $reverseArray $sortArray $objectToArray $arrayToObject $mergeObjects` | `STRING_AGG`, `PIVOT`, relational division, … |

## 2. Syntax cheat-sheet

```js
{ $unwind: "$items" }
{ $unwind: { path: "$skills", preserveNullAndEmptyArrays: true, includeArrayIndex: "pos" } }

{ $lookup: { from: "customers", localField: "customerId", foreignField: "_id", as: "customer" } }
{ $unwind: "$customer" }                         // or $set: { customer: { $first: "$customer" } }
{ $lookup: { from: "orders", let: { cid: "$_id" },
             pipeline: [ { $match: { $expr: { $and: [ { $eq: ["$customerId", "$$cid"] }, { $eq: ["$status", "Completed"] } ] } } },
                         { $project: { _id: 1, totalAmount: 1 } } ],
             as: "completedOrders" } }
{ $match: { orders: { $size: 0 } } }             // anti-join after $lookup
{ $graphLookup: { from: "employees", startWith: "$_id", connectFromField: "_id", connectToField: "managerId", as: "reports", depthField: "level" } }

{ $setWindowFields: { partitionBy: "$departmentId", sortBy: { salary: -1 },
                      output: { rank: { $rank: {} }, dense: { $denseRank: {} }, rowNum: { $documentNumber: {} } } } }
{ $setWindowFields: { sortBy: { orderDate: 1 },
                      output: { running: { $sum: "$totalAmount", window: { documents: ["unbounded", "current"] } },
                                prev:    { $shift: { output: "$totalAmount", by: -1, default: null } },
                                mov3:    { $avg: "$totalAmount", window: { documents: [-2, 0] } } } } }

{ $facet: { byStatus: [ { $sortByCount: "$status" } ], top3: [ { $sort: { totalAmount: -1 } }, { $limit: 3 } ], count: [ { $count: "n" } ] } }
{ $bucket: { groupBy: "$salary", boundaries: [40000, 60000, 80000, 100000], default: "other", output: { n: { $sum: 1 }, names: { $push: "$name" } } } }
{ $bucketAuto: { groupBy: "$totalAmount", buckets: 4 } }
{ $replaceRoot: { newRoot: { $mergeObjects: [ "$customer", "$$ROOT" ] } } }
{ $unionWith: { coll: "customers", pipeline: [ { $project: { name: 1 } } ] } }
{ $out: "report_orders" }
{ $merge: { into: "report_customers", on: "_id", whenMatched: "merge", whenNotMatched: "insert" } }
db.createView("vw_orders_full", "orders", [ { $lookup: … }, { $unwind: … } ])

// array expressions
{ $filter: { input: "$items", as: "i", cond: { $gte: ["$$i.qty", 2] } } }
{ $map:    { input: "$items", as: "i", in: { $multiply: ["$$i.qty", "$$i.unitPrice"] } } }
{ $reduce: { input: "$names", initialValue: "", in: { $concat: ["$$value", { $cond: [{ $eq: ["$$value", ""] }, "", ", "] }, "$$this"] } } }
{ $arrayToObject: [ [ { k: "Completed", v: 3 }, { k: "Pending", v: 1 } ] ] }      // -> { Completed: 3, Pending: 1 }
```

## 3. Gotchas

- **`$lookup` returns an array**, always. Unwind it or take `$first`. Unwinding an empty array **drops the document** — use `preserveNullAndEmptyArrays` for LEFT JOIN semantics.
- **`$lookup` needs an index on `foreignField`** — otherwise it is a collection scan per input document (nested loops). Put `$match` before the `$lookup` to shrink the outer side.
- **Inside a `$lookup` pipeline, outer fields are only visible through `let` variables** (`"$$cid"`), and must be compared with `$expr`.
- **`$lookup` cannot cross databases** (except in Atlas with `$lookup` to another db is not supported; use application code).
- **`$unwind` multiplies documents** — `$group` after it must not double-count parent fields (`$first` for them, or unwind after grouping what you need).
- **`$setWindowFields` needs `sortBy` for rank / shift / running windows**; `documents` windows are by position, `range` windows by value (`unit` for dates). Memory: 100 MB → `allowDiskUse`.
- **`$rank` vs `$denseRank` vs `$documentNumber`** = RANK / DENSE_RANK / ROW_NUMBER — the tie (Amit & Pooja) shows the difference.
- **`$facet` output arrays are limited to 16 MB** and `$facet` cannot use indexes inside sub-pipelines (the input is already materialised) — filter with `$match` *before* `$facet`.
- **`$out` replaces the whole target collection (and drops its indexes)**; `$merge` can update in place and must be the **last** stage. Neither can target the source collection with `$out`; `$merge` can, carefully.
- **`$graphLookup` results are unordered** (use `depthField` and sort) and are capped at 100 MB.
- **Views**: read-only, no indexes of their own (they use the source's), cannot be `$out` targets, `find()` on a view runs the pipeline every time.
- **`$$ROOT` after `$group` is gone** — keep it with `$push: "$$ROOT"` or `$first: "$$ROOT"` before you need it.

## 4. Interview questions

**Q: How do you join collections?**
`$lookup` (equality on `localField`/`foreignField`, or a pipeline with `let` for complex conditions). It behaves like a LEFT OUTER JOIN producing an array; `$unwind` or `$first` flattens it. Design first: if data is always read together, **embed** instead of joining.

**Q: LEFT JOIN vs INNER JOIN vs anti-join in MongoDB?**
`$lookup` alone = LEFT (empty array on no match). `$unwind` without `preserveNullAndEmptyArrays` = INNER. `$match: { arr: { $size: 0 } }` after `$lookup` = anti-join (NOT EXISTS).

**Q: What does `$unwind` do and when do you need it?**
Turns each array element into its own document. Needed before grouping / counting by array elements (skills per employee, order lines → revenue per product).

**Q: How do you do RANK / DENSE_RANK / ROW_NUMBER / running totals / LAG?**
`$setWindowFields` with `$rank`, `$denseRank`, `$documentNumber`, `$sum` over `documents: ["unbounded", "current"]`, `$shift: { by: -1 }`.

**Q: Recursive queries (org chart, categories tree)?**
`$graphLookup` from a starting document following `connectFromField → connectToField` up to `maxDepth`, with `depthField` for the level.

**Q: How do you compute several summaries in one pass?**
`$facet` — each key is an independent sub-pipeline over the same input; output is one document with arrays.

**Q: `$out` vs `$merge`?**
`$out` overwrites a whole collection (fast full rebuild). `$merge` upserts results into an existing collection and can keep other fields (`whenMatched: "merge"`) — incremental materialised views, same-collection updates, sharded targets.

**Q: What is a view? Materialised view?**
A view is a stored pipeline evaluated on every read (no storage, always fresh). A "materialised view" is a real collection filled by `$out`/`$merge` on a schedule (fast reads, stale data).

**Q: How do you pivot rows into columns?**
`$group` with `$push: { k: "$status", v: "$count" }` then `$arrayToObject`; or fixed columns with conditional `$sum`.

**Q: How would you write "customers who bought from every category"?**
Collect the distinct categories per customer (`$unwind` items → `$lookup` products → `$addToSet` category) and compare with all categories using `$setEquals` / `$setDifference` + `$size` (relational division).

## 5. Checklist

- [ ] I can `$unwind` with and without preserving empty arrays and know when documents disappear
- [ ] I can write equality and pipeline `$lookup`s, flatten the array, and do LEFT / INNER / anti joins
- [ ] I can traverse a hierarchy with `$graphLookup`
- [ ] I can rank, number, run totals, lag / lead and moving averages with `$setWindowFields`
- [ ] I can use `$facet`, `$bucket`, `$bucketAuto`, `$replaceRoot`, `$unionWith`
- [ ] I can use `$filter`, `$map`, `$reduce`, `$arrayToObject` and set operators for pivots and relational division
- [ ] I can materialise results with `$out` / `$merge` and create / query a view
