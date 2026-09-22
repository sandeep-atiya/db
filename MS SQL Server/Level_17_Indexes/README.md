# Level 17 — Indexes

**Goal:** know every index type and when to use it, read "logical reads" and a plan to tell seek / scan / lookup apart, write SARGable predicates, and know how to maintain, size and find missing or unused indexes.

**Time:** ~3 hr · **Files:** `01_Practice_Index_Types.sql` → `02_Practice_Seek_Scan_Lookup.sql` → `Exercises.sql`

---

## 1. Concepts in plain words

An index is a **B-tree**: one root page → a few intermediate pages → many leaf pages, all sorted by the key. Finding one key costs 3–4 page reads instead of reading the whole table. Tables of 19 rows never show this — the practice files build a 200 000-row `dbo.L17_Orders`.

### Index types

| Type | What it is | How many | `sys.indexes` | Use it for |
|------|-----------|----------|---------------|-----------|
| **Heap** | table with no clustered index; rows in no order, located by RID | — | `index_id = 0` | staging / bulk-load tables only |
| **Clustered** | the table itself sorted by the key; **leaf level = the data** | **1 per table** | `index_id = 1` | the PK (narrow, unique, ever-increasing: `INT IDENTITY`) |
| **Nonclustered** | separate B-tree: key + row locator (clustered key or RID) | up to 999 | `index_id ≥ 2` | columns in `WHERE` / `JOIN` / `ORDER BY` |
| **Unique** | nonclustered/clustered that rejects duplicates | — | `is_unique = 1` | natural keys (email, code); allows **one** NULL |
| **Composite** | several key columns `(A, B)` | — | — | filters on `A` or on `A AND B` (**leftmost prefix**), not `B` alone |
| **Covering / INCLUDE** | nonclustered with extra leaf-only columns | — | `INCLUDE (...)` | remove Key Lookups for a specific query |
| **Filtered** | index on a subset `WHERE Status = 'Pending'` | — | `has_filter`, `filter_definition` | small hot subsets, "unique except NULL" |
| **Computed-column** | index on `AS YEAR(OrderDate)` | — | — | an expression you filter on |
| Columnstore / XML / spatial / full-text | special structures | — | — | analytics, XML, geo, text search (not in this level) |

### Seek vs scan vs lookup

| Operator | Meaning | Reads |
|----------|---------|-------|
| **Table Scan** | read every page of a heap | all pages (~1 400 here) |
| **Clustered Index Scan** | read every page of the clustered index | all pages — a scan is a scan |
| **Index Scan** | read every page of a nonclustered index (narrower, so fewer pages) | all index pages |
| **Index Seek** | walk root → leaf to the matching range | 3 + the pages of the range |
| **Key Lookup** (RID Lookup on a heap) | for each row found in a nonclustered index, fetch the other columns from the clustered index | ~3 per row — 200 rows ≈ 600 reads |
| **Covering** | the index has all needed columns (key or INCLUDE) → no lookup | 3 |

**Tipping point:** with lookups costing ~3 reads per row, a full scan wins once more than roughly 0.1–1 % of the rows match — the optimizer switches from seek to scan on its own. A forced *Index Seek* returning 100 000 rows does 300 000 reads: "seek" is not automatically good.

**SARGable** (Search ARGument) predicate = the column stands alone: `Col = x`, `Col > x`, `Col BETWEEN`, `Col LIKE 'ab%'`, `Col IS NULL`. Not SARGable → scan: `YEAR(Col) = 2024`, `LIKE '%x'`, `ISNULL(Col,0) = 0`, `Col + 1 = 5`, `VarcharCol = 5` (implicit conversion of the column). Fix: move the function to the other side (`Col >= '20240101' AND Col < '20250101'`), match data types.

### Measuring

- `SET STATISTICS IO ON` → **logical reads** = 8 KB pages read from cache: stable, comparable, the number to tune.
- `SET SHOWPLAN_TEXT ON` (alone in its batch) → plan text, **query not executed**; `SET STATISTICS XML ON` → executes and returns the actual plan XML. SSMS: **Ctrl+M** actual plan, **Ctrl+L** estimated plan; read right-to-left.
- Missing indexes: `sys.dm_db_missing_index_details / _groups / _group_stats` (cleared on restart; treat as hints).
- Usage: `sys.dm_db_index_usage_stats` (`user_seeks/scans/lookups/updates`) → unused = 0 reads but > 0 updates.
- Size: `sys.dm_db_partition_stats` (`used_page_count * 8 / 1024` MB), `sp_helpindex`, `sp_spaceused`.
- Fragmentation: `sys.dm_db_index_physical_stats(... 'LIMITED')` → `avg_fragmentation_in_percent`, `page_count`.

## 2. Syntax cheat-sheet

```sql
CREATE [UNIQUE] [CLUSTERED | NONCLUSTERED] INDEX IX_Orders_Cust_Date
    ON dbo.Orders (CustomerID, OrderDate DESC)          -- key columns (sorted), max 32 / 1700 bytes
    INCLUDE (Amount, Status)                             -- leaf-only copies -> covering
    WHERE Status = 'Pending'                             -- filtered (needs QUOTED_IDENTIFIER ON)
    WITH (FILLFACTOR = 90, ONLINE = ON, SORT_IN_TEMPDB = ON, DATA_COMPRESSION = PAGE);

ALTER TABLE dbo.Orders ADD CONSTRAINT PK_Orders PRIMARY KEY [CLUSTERED | NONCLUSTERED] (OrderID);
ALTER TABLE dbo.T ADD OrderYear AS YEAR(OrderDate);  CREATE INDEX IX_T_Year ON dbo.T (OrderYear);

DROP INDEX [IF EXISTS] IX_Name ON dbo.Orders;
ALTER INDEX IX_Name ON dbo.Orders REBUILD [WITH (FILLFACTOR = 80, ONLINE = ON)];   -- > 30 %  (new copy, stats updated)
ALTER INDEX IX_Name ON dbo.Orders REORGANIZE;                                       -- 5-30 %  (in place, always online)
ALTER INDEX IX_Name ON dbo.Orders DISABLE;         -- REBUILD to enable; never disable the clustered index
ALTER INDEX ALL ON dbo.Orders REBUILD;

-- MEASURE
SET STATISTICS IO ON;      SET STATISTICS TIME ON;
SET SHOWPLAN_TEXT ON;  GO  <query>  GO  SET SHOWPLAN_TEXT OFF;  GO
SET STATISTICS XML ON;
SELECT ... FROM dbo.Orders WITH (INDEX(IX_Name)) ...   -- force an index (for demos, not production)

-- METADATA
SELECT index_id, name, type_desc, is_unique, has_filter, filter_definition, fill_factor, is_disabled
FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Orders');
SELECT * FROM sys.index_columns WHERE object_id = OBJECT_ID('dbo.Orders');      -- key_ordinal 0 = INCLUDE column
SELECT * FROM sys.dm_db_index_physical_stats(DB_ID(), OBJECT_ID('dbo.Orders'), NULL, NULL, 'LIMITED');
SELECT * FROM sys.dm_db_index_usage_stats WHERE database_id = DB_ID();
SELECT * FROM sys.dm_db_partition_stats WHERE object_id = OBJECT_ID('dbo.Orders');
SELECT * FROM sys.dm_db_missing_index_details WHERE database_id = DB_ID();
EXEC sp_helpindex 'dbo.Orders';   EXEC sp_spaceused 'dbo.Orders';
```

## 3. Gotchas

- **A clustered index does not speed up a filter on another column** — it only decides the physical order. The PK is clustered *by default*, not always.
- **Leftmost prefix rule:** index `(A, B)` cannot seek on `B` alone. Put equality columns first, range columns last; `(A, B)` makes `(A)` redundant.
- **Key Lookups are the hidden cost.** 200 rows × 3 reads. `INCLUDE` the extra columns — but do not include everything.
- **Filtered index + parameter:** `WHERE Status = @p` cannot use `WHERE Status = 'Pending'` index (needs a literal or `OPTION (RECOMPILE)`).
- **`sqlcmd` runs with `QUOTED_IDENTIFIER OFF`** → filtered indexes and computed-column indexes fail. `SET QUOTED_IDENTIFIER ON;` first (SSMS does).
- **Implicit conversion on the column** (`VarcharCol = 5`, `NVARCHAR` parameter vs `VARCHAR` column) → scan. Converting the *literal* (`IntCol = '5'`) is harmless.
- **`UNIQUE` allows exactly one NULL.** Need many NULLs? Filtered unique index `WHERE Col IS NOT NULL`.
- **`DROP INDEX` fails for a constraint's index** (PK/UNIQUE) — use `ALTER TABLE ... DROP CONSTRAINT`.
- **Disabling the clustered index makes the table unreadable**; disabling a nonclustered index drops its data (REBUILD recreates it).
- **`FOREIGN KEY` creates no index.** Create one on every FK column yourself (joins, cascading deletes, parent-delete checks).
- **Fragmentation numbers are meaningless below ~1 000 pages**; a freshly rebuilt index with fill factor < 100 shows 0 % because free space absorbs inserts.
- **Every index costs writes:** an UPDATE of a column must touch every index containing it (20 000 rows: 240 ms with 8 indexes vs 36 ms with 1).

## 4. Interview questions

**Q: Clustered vs nonclustered index?**
Clustered = the table itself stored sorted by the key; leaf level is the data; one per table (created by the PK by default). Nonclustered = a separate B-tree holding the key columns plus a row locator (the clustered key, or RID on a heap); up to 999 per table; needs a Key Lookup for columns it does not contain.

**Q: How many clustered indexes can a table have, and does a PRIMARY KEY always create one?**
One. A PK creates a *unique* index that is clustered *by default*; `PRIMARY KEY NONCLUSTERED` keeps the table a heap or leaves the clustered slot for another column.

**Q: Seek vs scan vs lookup?**
Seek: navigate the B-tree straight to the matching range (few reads). Scan: read every page of the table/index. Key Lookup: after a nonclustered seek, fetch the missing columns row-by-row from the clustered index (RID Lookup on a heap).

**Q: What is a covering index?**
An index that contains every column a query needs (in the key or in `INCLUDE`), so the query is answered from the index alone with no lookups.

**Q: What is a filtered index and when do you use it?**
A nonclustered index with a `WHERE` clause that indexes only matching rows (`WHERE Status = 'Pending'`, `WHERE Email IS NOT NULL`). Smaller, cheaper to maintain, better statistics; ideal for small hot subsets and "unique except NULL".

**Q: What is index fragmentation? REBUILD vs REORGANIZE?**
Leaf pages out of logical order / half-empty after page splits. `REORGANIZE` defragments the leaf level in place (online, light, 5–30 %). `REBUILD` creates a fresh copy (offline unless `ONLINE = ON`, updates statistics, > 30 %). Only matters for indexes with > ~1 000 pages.

**Q: What is fill factor?**
The percentage of each leaf page filled when the index is (re)built; the rest is free space for future inserts, reducing page splits at the cost of more pages to read. Use < 100 only for indexes with random inserts (GUIDs, names).

**Q: What is a SARGable predicate?**
One that lets the optimizer seek: the column stands alone on one side (`Col >= '20240101'`). Functions on the column (`YEAR(Col)`), leading wildcards, `ISNULL(Col,0)` and implicit conversions of the column force scans.

**Q: How do you find missing and unused indexes?**
Missing: `sys.dm_db_missing_index_details/_groups/_group_stats` (or the green hint in the SSMS plan). Unused: `sys.dm_db_index_usage_stats` where seeks + scans + lookups = 0 and `user_updates` > 0 — after enough uptime, both reset on restart.

**Q: What is your index maintenance strategy?**
Weekly job: for every index > 1 000 pages, REORGANIZE at 5–30 % fragmentation, REBUILD above 30 % (online where possible); update statistics; review usage stats monthly to drop unused indexes and missing-index DMVs to add well-chosen ones; keep the clustered key narrow and ever-increasing; index every FK column.

**Q: Does an index on a `BIT` / `Status` column help?**
Usually not on its own: with 2–3 values the optimizer prefers a scan (low selectivity). It helps as the first column of a composite / filtered index for the rare value (`WHERE Status = 'Pending'` = 5 %).

## 5. Checklist

- [ ] I can explain heap, clustered and nonclustered index and their `index_id`
- [ ] I can write CREATE INDEX with composite keys, INCLUDE, a filter and options
- [ ] I can measure a query with `SET STATISTICS IO ON` and see the plan with `SHOWPLAN_TEXT` / Ctrl+M
- [ ] I can tell Table Scan, Index Scan, Index Seek and Key Lookup apart and fix a lookup with INCLUDE
- [ ] I can rewrite a non-SARGable predicate (YEAR, LIKE '%x', ISNULL, implicit conversion)
- [ ] I know the leftmost prefix rule and why column order matters
- [ ] I can check fragmentation, usage, size and missing indexes with the DMVs
- [ ] I can say when NOT to create an index and what an index costs on writes
