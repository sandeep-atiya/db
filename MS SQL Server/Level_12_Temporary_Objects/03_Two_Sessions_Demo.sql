/* ============================================================
   LEVEL 12 - TEMPORARY OBJECTS  |  03_Two_Sessions_Demo.sql
   ------------------------------------------------------------
   Topics : who can see a #local vs a ##global temp table, and
            exactly WHEN a ##global table disappears.
   HOW TO PRACTICE: this file is NOT run top-to-bottom. Open TWO
   query windows in SSMS (each window = one session = one SPID).
   Copy the SESSION A steps into window A and the SESSION B steps
   into window B, and run them in the numbered order.
   ============================================================ */

USE SQLPractice;
GO

/*
 ===============================================================
  STEP 1  (SESSION A)  - find out who you are
 ===============================================================
    SELECT @@SPID AS MySessionId;          -- e.g. 55  (write it down)

 ===============================================================
  STEP 2  (SESSION B)  - same thing, different number
 ===============================================================
    SELECT @@SPID AS MySessionId;          -- e.g. 58  -> two different sessions

 ===============================================================
  STEP 3  (SESSION A)  - create ONE local and ONE global temp table
 ===============================================================
    DROP TABLE IF EXISTS #L12_Private, ##L12_Shared;

    SELECT e.EmployeeID, e.EmployeeName
    INTO #L12_Private                      -- one #  : only session A
    FROM dbo.Employees e
    WHERE e.DepartmentID = 1;              -- 3 rows

    SELECT c.CustomerID, c.CustomerName, c.City
    INTO ##L12_Shared                      -- two ## : everybody
    FROM dbo.Customers c
    WHERE c.City = 'Delhi';                -- 3 rows: Aarav, Chirag, Hina

    SELECT * FROM #L12_Private;            -- works: 3 rows
    SELECT * FROM ##L12_Shared;            -- works: 3 rows

 ===============================================================
  STEP 4  (SESSION B)  - try to read both
 ===============================================================
    SELECT * FROM ##L12_Shared;            -- WORKS: 3 rows. Global = visible to all sessions.

    SELECT * FROM #L12_Private;            -- FAILS: Invalid object name '#L12_Private'.
                                           -- Session B does not have a #L12_Private of its own.

 ===============================================================
  STEP 5  (SESSION B)  - both tables are in tempdb, only one is padded
 ===============================================================
    SELECT name, LEN(name) AS NameLength, create_date
    FROM tempdb.sys.tables
    WHERE name LIKE '#L12[_]Private%' OR name = '##L12_Shared';
    -- 2 rows:
    --   #L12_Private_______..._____00000000xxxx   128   (session A's private copy, padded + numbered)
    --   ##L12_Shared                               12   (stored exactly, shareable)
    -- You can SEE the private table's metadata from another session, but not SELECT its rows.

 ===============================================================
  STEP 6  (SESSION B)  - a global temp table can be CHANGED by anyone
 ===============================================================
    INSERT INTO ##L12_Shared (CustomerID, CustomerName, City)
    VALUES (99, 'Added by session B', 'Delhi');

 ===============================================================
  STEP 7  (SESSION A)  - session A sees the change immediately
 ===============================================================
    SELECT * FROM ##L12_Shared;            -- 4 rows now, including customer 99
    -- Lesson: ## tables are shared STATE. Two users running the same script at the
    -- same time will trample each other's data. That is why they are rare in real code.

 ===============================================================
  STEP 8  (SESSION B)  - hold the global table "in use" for 20 seconds
 ===============================================================
    BEGIN TRAN;
        SELECT COUNT(*) AS Cnt FROM ##L12_Shared WITH (HOLDLOCK);   -- keeps a lock until COMMIT
        WAITFOR DELAY '00:00:20';
    COMMIT;
    -- (run this and IMMEDIATELY go to step 9 in window A - you have 20 seconds)

 ===============================================================
  STEP 9  (SESSION A)  - close the creating session while B is still using the table
 ===============================================================
    -- Option 1: close window A (right-click the tab -> Close, or Ctrl+F4).
    -- Option 2: keep the window but end the session with:   (needs a fresh connection afterwards)
    --    (menu Query -> Disconnect)
    -- Rule: a ## table is dropped when the CREATING session ends AND the last statement
    --       that references it has finished. B's 20-second batch keeps it alive for now.

 ===============================================================
  STEP 10 (SESSION B)  - after the 20 seconds have passed
 ===============================================================
    SELECT * FROM ##L12_Shared;            -- FAILS: Invalid object name '##L12_Shared'.
                                           -- Creator is gone + nobody references it -> dropped.

    SELECT name FROM tempdb.sys.tables
    WHERE name LIKE '#L12[_]Private%' OR name = '##L12_Shared';   -- 0 rows: both gone with session A

 ===============================================================
  WHAT YOU HAVE SEEN
 ===============================================================
    #Local  : one per session, padded name in tempdb, invisible to other sessions,
              dies with the session (or the proc that created it).
    ##Global: one for the whole server, exact name, everybody can read / write / drop,
              dies when the creator disconnects AND the last user finishes.

    Interview one-liner: "# is private to my connection, ## is shared by all connections
    until the creator disconnects and nobody is using it any more."

 ===============================================================
  IF YOU WANT TO SEE THE SAME WITH BLOCKING (preview of Level 16)
 ===============================================================
    Session A:  BEGIN TRAN; UPDATE ##L12_Shared SET City = 'Noida';   -- no COMMIT yet
    Session B:  SELECT * FROM ##L12_Shared;   -- waits (blocked) until A commits or rolls back
    Session A:  ROLLBACK;                     -- B's SELECT now returns
    Check who blocks whom:  EXEC sp_who2;  (column BlkBy)  or  sys.dm_exec_requests.blocking_session_id
*/
