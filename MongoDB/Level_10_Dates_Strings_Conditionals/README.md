# Level 10 — Dates, Strings, Conditionals & Conversions

**Goal:** master the **expression operators** you use inside `$project` / `$set` / `$group` / pipeline updates: date math and formatting (with time zones), string functions, `CASE`-style logic, null handling, and safe type conversion (`TRY_CAST`).

**Time:** ~2.5 hr · **Files:** `01_Practice_Dates.js` → `02_Practice_Strings_Conditionals_Conversions.js` → `Exercises.js`

---

## 1. Concepts in plain words

### Dates (stored as UTC milliseconds — every operator accepts an optional `timezone`)

| Operator | Meaning | SQL Server |
|----------|---------|------------|
| `$year $month $dayOfMonth $hour $minute $second $millisecond` | parts (`{ date, timezone }` form allowed) | `YEAR()`, `DATEPART` |
| `$dayOfWeek` (1 = Sun … 7 = Sat) · `$isoDayOfWeek` (1 = Mon … 7 = Sun) · `$dayOfYear` · `$week` · `$isoWeek` · `$isoWeekYear` | calendar parts | `DATEPART(weekday…)` |
| `$dateToString: { date, format, timezone, onNull }` | format: `%Y %m %d %H %M %S %L %j %u %U %V %G %z %Z` (no month **names** — map them yourself) | `FORMAT`, `CONVERT` |
| `$dateFromString: { dateString, format, timezone, onError, onNull }` | parse | `TRY_CONVERT(datetime, …)` |
| `$dateAdd / $dateSubtract: { startDate, unit, amount, timezone }` | units: `year quarter month week day hour minute second millisecond` | `DATEADD` |
| `$dateDiff: { startDate, endDate, unit, timezone, startOfWeek }` | **counts boundaries crossed** (like `DATEDIFF`), not full periods | `DATEDIFF` |
| `$dateTrunc: { date, unit, binSize, timezone, startOfWeek }` | start of the month / week / 15-minute bin | `DATETRUNC` |
| `$dateToParts` / `$dateFromParts` | ↔ `{ year, month, day, hour, … }` | `DATEFROMPARTS` |
| `$toDate` / `$convert … to: "date"` | from string / number (ms) / ObjectId | `CAST` |
| `$$NOW` | current Date inside a pipeline | `GETUTCDATE()` |
| `$add: [date, ms]` / `$subtract: [date1, date2]` | date + milliseconds / difference in ms | — |

### Strings (UTF-8; `CP` = code points, `Bytes` = bytes)

| Operator | Meaning | SQL Server |
|----------|---------|------------|
| `$concat` | join (any **null → whole result null**) | `+` / `CONCAT` |
| `$toUpper $toLower` | case | `UPPER LOWER` |
| `$trim $ltrim $rtrim: { input, chars }` | strip whitespace / chars | `TRIM` |
| `$substrCP: [s, start, len]` · `$strLenCP` | substring / length in characters | `SUBSTRING LEN` |
| `$split: [s, delim]` | → array | `STRING_SPLIT` |
| `$indexOfCP: [s, sub]` | position or -1 | `CHARINDEX` − 1 |
| `$replaceOne / $replaceAll: { input, find, replacement }` | replace | `REPLACE` |
| `$regexMatch: { input, regex, options }` → bool · `$regexFind` → `{ match, idx, captures }` · `$regexFindAll` | regex | `LIKE` / `PATINDEX` |
| `$strcasecmp` | case-insensitive compare (−1/0/1) | `COLLATE` |
| `$toString` | any → string | `CAST(… AS VARCHAR)` |

### Conditionals & null

| Operator | Meaning | SQL Server |
|----------|---------|------------|
| `$cond: { if, then, else }` (or `[if, then, else]`) | `IIF` | `IIF` / `CASE` |
| `$switch: { branches: [{ case, then }], default }` | multi-branch | `CASE WHEN` |
| `$ifNull: [a, b, …, fallback]` | first non-null (multi-arg since 5.0); missing counts as null | `COALESCE` / `ISNULL` |
| `$eq $ne $gt $gte $lt $lte $cmp $in` | comparisons returning booleans (a **missing** field is *not* `$eq` to null — it sorts *below* null) | |
| `$and $or $not` | logic (expression form) | |
| `$type $isNumber $isArray` | type checks | `SQL_VARIANT_PROPERTY` |
| `$let: { vars, in }` | local variables | — |

### Conversions & math

| Operator | Meaning |
|----------|---------|
| `$convert: { input, to, onError, onNull }` | safe cast = **`TRY_CAST`**; `to`: `int double decimal long string bool date objectId` (name or code) |
| `$toInt $toDouble $toDecimal $toLong $toString $toBool $toDate $toObjectId` | strict casts — **throw** on bad input |
| `$round: [x, places] $trunc $ceil $floor $abs $mod $pow $sqrt $exp $ln $log10` | math (`$round` uses "round half to even" on doubles) |
| `$add $subtract $multiply $divide` | arithmetic; `$divide` by 0 → error |
| `$bsonSize $binarySize` | sizes in bytes |

## 2. Syntax cheat-sheet

```js
{ $set: { year: { $year: "$orderDate" }, dow: { $isoDayOfWeek: "$orderDate" },
          label: { $dateToString: { format: "%Y-%m-%d", date: "$orderDate", timezone: "Asia/Kolkata" } },
          month: { $dateTrunc: { date: "$orderDate", unit: "month" } },
          due: { $dateAdd: { startDate: "$orderDate", unit: "day", amount: 7 } },
          ageDays: { $dateDiff: { startDate: "$orderDate", endDate: "$$NOW", unit: "day" } } } }
{ $dateFromString: { dateString: "05/01/2025", format: "%d/%m/%Y", timezone: "Asia/Kolkata", onError: null } }
{ $dateFromParts: { year: 2025, month: 1, day: 5, hour: 9, timezone: "+05:30" } }

{ $concat: ["$name", " <", { $ifNull: ["$email", "no email"] }, ">"] }
{ $toUpper: { $substrCP: ["$name", 0, 1] } }
{ $first: { $split: ["$name", " "] } }
{ $regexFind: { input: "$email", regex: /@(.+)$/ } }          // captures[0] = domain
{ $replaceAll: { input: "$phone", find: "-", replacement: "" } }

{ $cond: [ { $gte: ["$salary", 70000] }, "HIGH", "NORMAL" ] }
{ $switch: { branches: [ { case: { $gte: ["$salary", 80000] }, then: "A" }, { case: { $gte: ["$salary", 60000] }, then: "B" } ], default: "C" } }
{ $ifNull: ["$email", "$altEmail", "(none)"] }
{ $convert: { input: "$price", to: "double", onError: null, onNull: 0 } }
{ $cond: [ { $eq: ["$stock", 0] }, null, { $divide: ["$price", "$stock"] } ] }   // divide-by-zero guard
{ $round: [ { $multiply: ["$price", 1.18] }, 2 ] }
```

## 3. Gotchas

- **`$dateDiff` counts boundary crossings**: 2024-12-31 → 2025-01-01 is 1 `year`. For "full years of tenure" compare month/day or use `$dateDiff` in days ÷ 365.25 and `$floor`.
- **Dates are UTC.** `$month` of `2025-01-31T20:00Z` in `Asia/Kolkata` is **2** (it is already 1 Feb there). Pass `timezone` when the business day matters.
- **`$dateToString` has no month names / weekday names** — use `$arrayElemAt: [["Jan", …], { $subtract: [{ $month: … }, 1] }]`.
- **`$concat` with a null (or missing) operand returns null** — wrap optional fields in `$ifNull`.
- **`$substr` (bytes, deprecated) vs `$substrCP`** — use CP versions for Unicode text.
- **Regex in expressions**: `$regexMatch` cannot use an index (unlike `$match: { f: /^x/ }`); filter first, compute later.
- **`$toInt("12.5")` throws; `$toInt(12.5)` truncates to 12; `$toBool("false")` is `true`** (any non-empty string). Use `$convert` with `onError`/`onNull` for dirty data; compare strings explicitly for booleans.
- **`$round` on doubles rounds half to even** (`$round: [2.5, 0]` → 2). Use `NumberDecimal` for money.
- **`$divide` by zero is an error**, not null — guard with `$cond`.
- **Missing ≠ null in expressions.** `{ $eq: ["$nope", null] }` is **false** for a missing field (`$cmp` gives -1: missing sorts below null); `{ $eq: ["$f", null] }` is true only for an explicit null. To treat both the same use `$ifNull`, `{ $lte: ["$f", null] }`, or `{ $in: [{ $type: "$f" }, ["null", "missing"]] }`. (In a *query* filter, `{ f: null }` matches both.)
- **Numeric strings sort as strings** (`"10" < "9"`) — convert (or store numbers) before sorting / comparing.
- **`$$NOW` is fixed for the whole pipeline** (same value in every document) — good for consistency.

## 4. Interview questions

**Q: How do you group orders by month?**
`$group: { _id: { $dateTrunc: { date: "$orderDate", unit: "month" } } }` (or `{ y: { $year }, m: { $month } }`), sorted by `_id`. Add `timezone` for local months.

**Q: How do you handle time zones in MongoDB?**
Store UTC `Date`s; convert on read with the `timezone` argument of `$dateToString` / `$dateToParts` / `$hour` etc. (`"Asia/Kolkata"` or `"+05:30"`), or in the application layer. Never store local-time strings.

**Q: `$dateDiff` vs subtracting dates?**
`$subtract: [d2, d1]` gives **milliseconds**. `$dateDiff` gives whole units by boundaries crossed (`unit: "day" | "month" | …`) and supports time zones and `startOfWeek`.

**Q: How do you write `CASE WHEN` in MongoDB?**
`$cond` (two branches) or `$switch` (many branches + default) — inside `$project`, `$set`, `$group` accumulators or pipeline updates.

**Q: What is the MongoDB equivalent of `COALESCE` / `ISNULL`?**
`$ifNull: [a, b, …, fallback]` — returns the first non-null, non-missing expression.

**Q: How do you safely convert strings to numbers (`TRY_CAST`)?**
`$convert: { input, to: "double", onError: null, onNull: 0 }`. The `$toX` shortcuts throw on invalid input.

**Q: How do you extract the domain from an email?**
`$regexFind: { input: "$email", regex: /@(.+)$/ }` → `captures[0]`, or `$arrayElemAt: [{ $split: ["$email", "@"] }, 1]`.

**Q: Why does my `$concat` return null?**
Any null / missing operand makes the whole result null — wrap optional fields in `$ifNull`.

**Q: How do you get the current time inside a pipeline / update?**
`$$NOW` (a Date, constant for the whole operation); in update operators `$currentDate`.

## 5. Checklist

- [ ] I can extract date parts, format dates (with a time zone), truncate to month/week, add / subtract and diff dates
- [ ] I can parse strings into dates safely with `$dateFromString` + `onError`
- [ ] I can concat, case, trim, split, substring, replace and regex-extract strings — and guard nulls
- [ ] I can write `$cond`, `$switch`, `$ifNull` and comparisons in projections, groups and updates
- [ ] I can convert types safely with `$convert`, and know the `$toInt` / `$toBool` traps
- [ ] I can round, guard divide-by-zero and fix dirty numeric strings with a pipeline update
