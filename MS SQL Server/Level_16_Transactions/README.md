# Level 16 — Transactions, Isolation Levels, Locks

**Goal:** write correct transactions (BEGIN/COMMIT/ROLLBACK, TRY/CATCH, XACT_ABORT), understand what locks and isolation levels do, and be able to find and explain blocking and deadlocks.

**Time:** ~3 hr · **Files:** `01_Practice_Transactions.sql` → `02_Practice_Isolation_Locks.sql` → `03_Two_Sessions_Demo.sql` (two SSMS windows) → `Exercises.sql`

---

## 1. Concepts in plain words

### A transaction is "all or nothing"

A group of statements that succeed or fail as **one unit**. Bank transfer = debit + credit; half of it must never happen.

| ACID | Meaning | Example in the practice file |
|------|---------|------------------------------|
| **Atomicity** | all statements apply, or none | `ROLLBACK` undoes the debit *and* the credit |
| **Consistency** | the DB moves from one valid state to another | `CHECK (Balance >= 0)` refuses the overdraft, the whole transfer is rolled back |
| **Isolation** | other sessions do not see half-done work | Session B waits (or reads an old version) while A is in the middle of the transfer |
| **Durability** | after `COMMIT` returns, the change survives a crash | log records are written to the `.ldf` **before** `COMMIT` returns |

### Three transaction modes

| Mode | How it starts | How it ends | Notes |
|------|---------------|-------------|-------|
| **Autocommit** (default) | every statement | itself | `@@TRANCOUNT` stays 0 |
| **Explicit** | `BEGIN TRAN` | `COMMIT` / `ROLLBACK` | what you write in procedures |
| **Implicit** | `SET IMPLICIT_TRANSACTIONS ON` → first DML/DDL opens one | **you** must `COMMIT`/`ROLLBACK` | Oracle/ANSI style; forgotten commits = open locks |

### Key facts

- **`@@TRANCOUNT`** = number of open `BEGIN TRAN` in your session. Nested `BEGIN TRAN` only adds 1; an inner `COMMIT` only subtracts 1 (**commits nothing**); **any `ROLLBACK` undoes everything** and sets it to 0.
- **`SAVE TRANSACTION name`** + `ROLLBACK TRAN name` = partial rollback; the transaction stays open.
- **`XACT_STATE()`**: `1` active & committable, `0` none, `-1` active but **uncommittable** ("doomed": only `ROLLBACK` works; `COMMIT` → error 3930).
- **`SET XACT_ABORT ON`**: any run-time error aborts the batch and rolls back automatically; inside `TRY/CATCH` it makes the transaction uncommittable (-1) so you cannot half-commit by mistake. Put it in every writing procedure.
- **Temp table vs table variable on `ROLLBACK`**: `#temp` rows are undone; `@table` rows survive (not transactional) — good for saving error info before rolling back.
- **Transaction log**: every change is logged first (write-ahead). Long transactions hold locks, stop log truncation and take as long to roll back as to run. Load/delete big data in **batches** (commit every N rows).

### Locks

| Mode | Name | Taken by | Blocked by |
|------|------|----------|-----------|
| **S** | Shared | reads | X |
| **X** | Exclusive | INSERT / UPDATE / DELETE | everything |
| **U** | Update | "read now, write soon" (`UPDLOCK`, the read phase of UPDATE) | U, X — only one U per row → prevents the read-then-write deadlock |
| **IS / IX** | Intent | on page/table when a row lock is taken below | table-level X / Sch-M |
| **Sch-S / Sch-M** | Schema stability / modification | every query / DDL | Sch-M / everything |

Granularity: **KEY/RID** (row) < **PAGE** < **OBJECT** (table) < **DATABASE**. **Lock escalation**: ~5 000 locks on one table in one statement → SQL Server swaps them for one table lock. View your locks with `sys.dm_tran_locks WHERE request_session_id = @@SPID`.

### Isolation levels vs the three phenomena

| Level | Dirty read | Non-repeatable read | Phantom | Mechanism |
|-------|-----------|--------------------|---------|-----------|
| READ UNCOMMITTED (= `NOLOCK`) | yes | yes | yes | no S locks |
| **READ COMMITTED** (default) | no | yes | yes | S lock only while reading the row |
| REPEATABLE READ | no | no | yes | S locks held to end of transaction |
| SERIALIZABLE (= `HOLDLOCK`) | no | no | no | range locks (`RangeS-S`) held to end |
| SNAPSHOT | no | no | no | row versions in tempdb; transaction-level snapshot; update conflict error 3960 |
| READ COMMITTED SNAPSHOT (RCSI) | no | yes | yes | row versions, **statement**-level; replaces the default DB-wide |

*Dirty read* = reading uncommitted data. *Non-repeatable read* = same row, different value on second read. *Phantom* = same `WHERE`, extra/missing rows on second read.

### Blocking vs deadlock

- **Blocking**: my request waits for a lock someone holds (`LCK_M_*` wait). Normal for milliseconds, a problem for seconds. Find it: `sys.dm_exec_requests.blocking_session_id`, `sp_who2` (BlkBy), `sys.dm_os_waiting_tasks`. Limit the wait with `SET LOCK_TIMEOUT ms` (error 1222). Kill the blocker with `KILL spid`.
- **Deadlock**: A waits for B and B waits for A. The deadlock monitor (every ~5 s) rolls back a **victim** (lower `DEADLOCK_PRIORITY`, else cheapest to roll back) with **error 1205**; the other continues. Graphs: `system_health` Extended Events session. Prevent: same object order everywhere, short transactions, good indexes, `UPDLOCK` for read-then-update, snapshot isolation, retry loop.

## 2. Syntax cheat-sheet

```sql
BEGIN TRAN [name];  ...  COMMIT [TRAN name];  |  ROLLBACK [TRAN name];
SELECT @@TRANCOUNT, XACT_STATE();
SAVE TRANSACTION sp1;   ROLLBACK TRANSACTION sp1;          -- partial rollback
SET IMPLICIT_TRANSACTIONS ON | OFF;    SELECT @@OPTIONS & 2;  -- 2 = implicit on
SET XACT_ABORT ON;

-- THE PROCEDURE TEMPLATE
CREATE PROCEDURE dbo.usp_Transfer @From INT, @To INT, @Amount DECIMAL(12,2) AS
BEGIN
    SET NOCOUNT ON;  SET XACT_ABORT ON;
    BEGIN TRY
        IF @Amount <= 0 THROW 50001, 'Amount must be positive.', 1;
        BEGIN TRAN;
            UPDATE dbo.Accounts SET Balance -= @Amount WHERE AccountID = @From;
            IF @@ROWCOUNT = 0 THROW 50002, 'From-account not found.', 1;
            UPDATE dbo.Accounts SET Balance += @Amount WHERE AccountID = @To;
        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;     -- or: IF XACT_STATE() <> 0 ROLLBACK;
        THROW;                           -- re-raise the original error
    END CATCH
END

-- ISOLATION
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED | READ COMMITTED | REPEATABLE READ | SERIALIZABLE | SNAPSHOT;
DBCC USEROPTIONS;                                                          -- last row = isolation level
SELECT transaction_isolation_level FROM sys.dm_exec_sessions WHERE session_id = @@SPID;  -- 1..5
ALTER DATABASE SQLPractice SET ALLOW_SNAPSHOT_ISOLATION ON;                -- needed for SNAPSHOT
ALTER DATABASE SQLPractice SET READ_COMMITTED_SNAPSHOT ON WITH ROLLBACK IMMEDIATE;  -- RCSI (needs exclusive DB)
SELECT snapshot_isolation_state_desc, is_read_committed_snapshot_on FROM sys.databases WHERE name = DB_NAME();

-- HINTS (per table)
SELECT ... FROM dbo.T WITH (NOLOCK | READPAST | UPDLOCK | HOLDLOCK | ROWLOCK | PAGLOCK | TABLOCK | TABLOCKX | XLOCK)

-- LOCKS / BLOCKING / DEADLOCKS
SELECT resource_type, request_mode, request_status FROM sys.dm_tran_locks WHERE request_session_id = @@SPID;
SELECT session_id, blocking_session_id, wait_type, wait_time FROM sys.dm_exec_requests WHERE blocking_session_id <> 0;
EXEC sp_who2 'active';   SELECT * FROM sys.dm_os_waiting_tasks WHERE blocking_session_id IS NOT NULL;
SET LOCK_TIMEOUT 3000;   SELECT @@LOCK_TIMEOUT;   KILL 57;
SET DEADLOCK_PRIORITY LOW | NORMAL | HIGH | -10..10;
-- retry:  IF ERROR_NUMBER() = 1205 BEGIN ROLLBACK; WAITFOR DELAY '00:00:00.2'; /* loop again */ END
-- deadlock graphs: system_health ring_buffer, event xml_deadlock_report (query in file 02, section 7c)
```

## 3. Gotchas

- **Inner `COMMIT` commits nothing.** Only the outermost `COMMIT` (`@@TRANCOUNT` 1 → 0) writes anything. Any `ROLLBACK` at any level undoes it all.
- **A CHECK/PK error does NOT doom the transaction** (`XACT_STATE() = 1`). Without a `ROLLBACK` in `CATCH` you can accidentally commit half the work. Use `SET XACT_ABORT ON`.
- **Conversion errors and some others doom it even without XACT_ABORT** (`-1`) — always check `XACT_STATE()` / `@@TRANCOUNT` before `COMMIT` in `CATCH`.
- **`ROLLBACK TRAN InnerName` fails (6401)** — only the outermost name or a savepoint name is valid. `OUTER` / `INNER` are reserved words, do not use them as names.
- **The isolation level is a session setting**: it stays until you change it or reconnect. Reset to `READ COMMITTED` at the end of scripts.
- **`NOLOCK` on the target of `UPDATE/DELETE` → error 1065.** And `NOLOCK` can return a row twice / skip it during page splits, not just dirty values.
- **`SNAPSHOT` without `ALLOW_SNAPSHOT_ISOLATION ON` → error 3952** at the first read. RCSI switch needs the database to itself (`WITH ROLLBACK IMMEDIATE`).
- **DDL is transactional**: `ALTER TABLE` inside `BEGIN TRAN` takes Sch-M and can be rolled back — and blocks everyone until you commit.
- **Sleeping session with `open_transaction_count = 1`** = the usual blocker (someone forgot `COMMIT` or uses implicit transactions).
- **`sqlcmd -b` stops at the first error** — an error under `XACT_ABORT ON` outside `TRY/CATCH` ends the script (which is exactly what it should do in production).

## 4. Interview questions

**Q: What is the difference between COMMIT and ROLLBACK?**
`COMMIT` makes all changes of the transaction permanent (log flushed, locks released). `ROLLBACK` undoes all of them using the log and releases the locks. Both end the transaction; with nesting, only the outermost `COMMIT` really commits, while any `ROLLBACK` undoes every level.

**Q: What is a deadlock and how do you avoid it?**
Two sessions each hold a lock the other needs, forever. SQL Server detects it (~every 5 s), rolls back the cheaper/lower-priority victim with error 1205 and lets the other continue. Avoid: access tables in the same order, keep transactions short, index properly so fewer rows are locked, use `UPDLOCK` for read-then-update, consider SNAPSHOT/RCSI, add a retry loop for 1205.

**Q: NOLOCK — pros and cons?**
Pros: no S locks → no waiting, no blocking of writers, fast for rough reports. Cons: dirty reads (uncommitted data that may be rolled back), rows read twice or missed during page splits, error 601, not allowed on modified tables. Never for financial or "does it exist" logic; prefer RCSI/SNAPSHOT.

**Q: Optimistic vs pessimistic concurrency?**
Pessimistic = lock first (S/U/X, READ COMMITTED … SERIALIZABLE): conflicts are prevented by waiting. Optimistic = do not lock readers, use row versions (SNAPSHOT, RCSI) and detect conflicts at write time (error 3960 / rowversion check). Optimistic scales better for read-heavy loads; pessimistic is simpler when conflicts are frequent.

**Q: What is `@@TRANCOUNT`?**
The number of open `BEGIN TRAN` statements in the current session. 0 = autocommit mode. `BEGIN TRAN` +1, `COMMIT` −1, `ROLLBACK` → 0. Used in procedures to decide whether a `ROLLBACK` is needed.

**Q: What does `SET XACT_ABORT ON` do?**
When a run-time error occurs, the whole batch is aborted and the open transaction is rolled back automatically (with `TRY/CATCH`, it is marked uncommittable, `XACT_STATE() = -1`). Without it, the error aborts only the statement and the transaction stays open. Also mandatory for distributed transactions.

**Q: What is the default isolation level and what problems can it still have?**
READ COMMITTED. No dirty reads, but non-repeatable reads and phantoms are possible because S locks are released right after each row is read.

**Q: Difference between SNAPSHOT and READ COMMITTED SNAPSHOT?**
Both use row versioning in tempdb. SNAPSHOT is per session (`SET TRANSACTION ISOLATION LEVEL SNAPSHOT`) and gives one consistent view for the whole transaction, with update-conflict errors. RCSI is a database option that changes the meaning of READ COMMITTED to a per-statement snapshot; no code change, no update conflicts.

**Q: What is lock escalation?**
When one statement holds about 5 000 row/page locks on a table, SQL Server replaces them with one table lock to save memory — at the cost of blocking everybody else on that table. Control with `ALTER TABLE … SET (LOCK_ESCALATION = …)` or by batching.

**Q: What is the difference between blocking and a deadlock?**
Blocking is a normal wait that ends when the holder commits/rolls back. A deadlock is a circular wait that can never end by itself; SQL Server must kill one side.

**Q: What happens to a table variable and a temp table on ROLLBACK?**
Temp table rows are rolled back; table variable rows are kept (they are not part of the transaction).

## 5. Checklist

- [ ] I can explain ACID with one example each
- [ ] I can write BEGIN TRAN / COMMIT / ROLLBACK with TRY/CATCH and know what `XACT_STATE()` and `XACT_ABORT` do
- [ ] I know what nested `BEGIN TRAN`, inner `COMMIT` and `SAVE TRANSACTION` really do
- [ ] I can write the standard procedure template from memory
- [ ] I can list the lock modes and view my own locks in `sys.dm_tran_locks`
- [ ] I can fill in the isolation level vs phenomena matrix and read my current level
- [ ] I can find a blocker (DMV / sp_who2) and kill it
- [ ] I can explain deadlock detection (1205), prevention, and the retry pattern
