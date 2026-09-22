# Level 06 — Arrays & Nested Documents

**Goal:** query and update arrays (of scalars and of embedded documents) with confidence: `$all`, `$size`, `$elemMatch`, `$push`/`$pull`/`$addToSet` with modifiers, and the three positional operators `$`, `$[]`, `$[id]` with `arrayFilters`. This is where MongoDB stops looking like SQL.

**Time:** ~2.5 hr · **Files:** `01_Practice_Query_Arrays_Nested.js` → `02_Practice_Update_Arrays.js` → `Exercises.js`

---

## 1. Concepts in plain words

### Querying arrays

| Filter | Meaning |
|--------|---------|
| `{ skills: "SQL" }` | array **contains** "SQL" (any element equals) |
| `{ skills: ["Sales", "Excel"] }` | array **is exactly** `["Sales", "Excel"]` (same order) |
| `{ skills: { $all: ["SQL", "Excel"] } }` | contains **all** of these, any order (SQL: no direct equivalent) |
| `{ skills: { $in: ["SQL", "Excel"] } }` | contains **any** of these |
| `{ skills: { $size: 2 } }` | exactly 2 elements (`$size` takes a literal, not `$gt`) |
| `{ "skills.2": { $exists: true } }` | at least 3 elements |
| `{ skills: [] }` / `{ skills: { $size: 0 } }` | empty array (a **missing** field matches neither) |
| `{ "skills.0": "Sales" }` | first element is "Sales" |
| `{ "items.productId": 2 }` | some element's `productId` is 2 |
| `{ "items.productId": 2, "items.qty": 2 }` | some element has productId 2 **and some (maybe other) element** has qty 2 ← the trap |
| `{ items: { $elemMatch: { productId: 2, qty: 2 } } }` | **one element** satisfies both |
| `{ ratings: { $elemMatch: { $gte: 4, $lt: 5 } } }` | one element between 4 and 5 (needed when 2 operators must hit the same scalar) |
| `{ ratings: { $gt: 4 } }` | any element > 4 |
| `{ skills: { $nin: ["SQL"] } }` | no element is "SQL" (also matches missing) |

### Updating arrays

| Operator | Meaning |
|----------|---------|
| `$push: { skills: "Go" }` | append (creates the array if missing) |
| `$push: { skills: { $each: [...], $position: 0, $slice: -5, $sort: 1 } }` | append many / insert at position / keep last 5 / sort after push |
| `$addToSet: { skills: "Go" }` | append only if not present (set semantics; `$each` for many) |
| `$pop: { skills: 1 }` / `-1` | remove last / first |
| `$pull: { skills: "Go" }` / `{ items: { qty: { $lt: 2 } } }` | remove **all** elements matching a value or condition |
| `$pullAll: { skills: ["Go", "C"] }` | remove all listed values |
| `$set: { "skills.1": "TS" }` | by index |
| `"items.$.qty"` | **positional `$`**: the *first* element matched by the query (the query must include the array field) |
| `"items.$[].qty"` | **all positional `$[]`**: every element |
| `"items.$[i].qty"` + `arrayFilters: [{ "i.productId": 2 }]` | **filtered positional**: every element matching the filter (can be nested `$[a].sub.$[b]`) |

### Embedded documents

- Read / filter / update with **dot notation** (`"address.city"`); quotes required.
- Equality on the whole sub-document is exact and order-sensitive (Level 02).
- `$set: { address: {...} }` replaces the whole sub-document; `$set: { "address.city": ... }` changes one field.
- `$rename` and `$unset` work with dot paths, but `$rename` cannot target array elements.

## 2. Syntax cheat-sheet

```js
// QUERY
db.employees.find({ skills: { $all: ["SQL", "Excel"] } })
db.employees.find({ skills: { $size: 3 } })
db.products.find({ ratings: { $elemMatch: { $gte: 4, $lt: 5 } } })
db.orders.find({ items: { $elemMatch: { productId: 2, qty: { $gte: 2 } } } })
db.orders.find({ "items.0.productId": 1 })                       // first line is a Laptop
db.orders.find({ items: { $not: { $elemMatch: { productId: 2 } } } })   // orders WITHOUT a mouse line

// UPDATE
db.e.updateOne({ _id: 101 }, { $push: { skills: "Go" } })
db.e.updateOne({ _id: 101 }, { $push: { skills: { $each: ["Go", "Rust"], $position: 0 } } })
db.e.updateOne({ _id: 101 }, { $push: { scores: { $each: [88, 92], $sort: -1, $slice: 3 } } })   // keep top 3
db.e.updateOne({ _id: 101 }, { $addToSet: { skills: { $each: ["Go", "Java"] } } })
db.e.updateOne({ _id: 101 }, { $pop: { skills: 1 } })
db.e.updateOne({ _id: 101 }, { $pull: { skills: "Java" } })
db.o.updateOne({ _id: 1002 }, { $pull: { items: { qty: { $lt: 2 } } } })
db.o.updateOne({ _id: 1002, "items.productId": 2 }, { $set: { "items.$.qty": 5 } })            // first matching element
db.o.updateOne({ _id: 1002 }, { $inc: { "items.$[].qty": 1 } })                                 // every element
db.o.updateOne({ _id: 1002 }, { $set: { "items.$[i].gift": true } }, { arrayFilters: [{ "i.qty": { $gte: 2 } }] })
db.o.updateMany({}, { $mul: { "items.$[i].unitPrice": 0.9 } }, { arrayFilters: [{ "i.productId": { $in: [7, 8] } }] })
```

## 3. Gotchas

- **Dot-notation conditions on an array of documents are matched independently** — different elements can satisfy different conditions. Use `$elemMatch` for "same element".
- **`$` positional needs the array in the query** and updates only the **first** match. For all matches use `$[]` or `$[id]` + `arrayFilters`.
- **`$` in a projection ≠ `$` in an update** — both mean "first matched element", but projection `$` works only with `find`.
- **`$push` on a non-array field fails** (`The field 'x' must be an array`); on a missing field it creates the array.
- **`$pull` removes *all* matching elements**, `$pop` removes one from an end. There is no "remove by index" — use `$unset "arr.2"` (leaves `null`) then `$pull: { arr: null }`.
- **`$addToSet` compares whole values** — embedded documents must match exactly (field order too).
- **`$size` takes only a number.** "More than 2" = `{ "arr.2": { $exists: true } }` or `$expr: { $gt: [{ $size: "$arr" }, 2] }`.
- **`$size` in `$expr` fails on a missing field** → wrap with `$ifNull: ["$arr", []]`.
- **Sorting on an array field** uses the smallest (asc) / largest (desc) element.
- **Indexes on arrays are multikey** (one entry per element) and a compound index may contain only **one** array field (Level 11).
- **Unbounded arrays** (`$push` forever) hit the 16 MB limit and slow every rewrite — bucket / reference instead (Level 13).
- **`arrayFilters` identifiers** must be lowercase alphanumeric starting with a letter, and every identifier used in the update must appear in `arrayFilters` (and vice versa).

## 4. Interview questions

**Q: How do you query "array contains X" vs "array equals [X, Y]" vs "contains all of X and Y"?**
`{ a: "X" }` (any element), `{ a: ["X", "Y"] }` (exact, ordered), `{ a: { $all: ["X", "Y"] } }` (all, any order).

**Q: When do you need `$elemMatch`?**
When two or more conditions must be true for the **same** array element (`{ items: { $elemMatch: { productId: 2, qty: { $gte: 2 } } } }`) or for the same scalar element with two operators (`{ ratings: { $elemMatch: { $gte: 4, $lt: 5 } } }`). Without it, conditions may match different elements.

**Q: `$push` vs `$addToSet`?**
`$push` always appends (duplicates allowed, supports `$position`, `$slice`, `$sort`). `$addToSet` appends only if the value is not already present (set semantics), no ordering guarantees.

**Q: Explain `$`, `$[]` and `$[<id>]`.**
`$` = the first array element matched by the query (query must filter on the array). `$[]` = all elements. `$[id]` = the elements matching the corresponding `arrayFilters` entry; can be nested for arrays inside arrays.

**Q: How do you update one specific element of an array of documents?**
`updateOne({ _id: X, "items.productId": 2 }, { $set: { "items.$.qty": 5 } })`, or with `arrayFilters` when the element may occur several times or the condition is complex.

**Q: How do you remove an element by index?**
There is no direct operator: `$unset: { "arr.2": 1 }` sets it to `null`, then `$pull: { arr: null }`. Or rewrite the array with a pipeline update using `$slice` / `$concatArrays` / `$filter`.

**Q: How do you keep an array capped at N elements (e.g. last 10 events)?**
`$push: { events: { $each: [e], $slice: -10 } }` — push then keep the last 10 atomically.

**Q: How would you find documents whose array has more than 3 elements?**
`{ "arr.3": { $exists: true } }` (cheap) or `{ $expr: { $gt: [{ $size: "$arr" }, 3] } }`. `$size` itself only does equality.

## 5. Checklist

- [ ] I can write contains / exact / `$all` / `$in` / `$size` / `$elemMatch` queries and know the different-element trap
- [ ] I can query arrays of embedded documents by field and by position
- [ ] I can `$push` with `$each`, `$position`, `$slice`, `$sort`, and know `$addToSet`, `$pop`, `$pull`, `$pullAll`
- [ ] I can update one / all / filtered elements with `$`, `$[]`, `$[id]` + `arrayFilters`
- [ ] I can update nested document fields with dot notation without overwriting the sub-document
- [ ] I know how to cap an array, remove by index, and why unbounded arrays are dangerous
