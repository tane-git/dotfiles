---
name: restore-flint-db
description: Restore/refresh a personal Flint database copy (e.g. FlameInstructionManager_Tane, _Henry, _<name>) on the shared infor-test-db SQL Server from the latest FlameInstructionManager full backup, using native RESTORE over ODBC. Use whenever the user wants to reset, refresh, re-copy, wipe, restore, or "get a clean copy of" their Flint / FlameInstructionManager dev database, or when their _Tane copy has bad/test data, failed migrations, or a schema that breaks the app and they want it back to clean staging data.
---

# Restore a personal Flint DB from FlameInstructionManager

Flint developers each work against a private copy of the staging database
(`FlameInstructionManager_<name>`) on the shared server `infor-test-db`
(`10.10.17.216`). These copies drift: test entities get created, migrations from
other feature branches get applied, and the schema/data ends up in a state that
breaks the app on your current branch. The fix is to overwrite the personal copy
with a fresh restore of the nightly `FlameInstructionManager` backup.

This is a **native SQL `RESTORE DATABASE ... WITH MOVE, REPLACE`** run over the
`isql` ODBC client — no `.bacpac`, no SSMS, no sysadmin required.

## Prerequisites (why they matter)

- **`isql`** (unixODBC) with **ODBC Driver 18 for SQL Server**. All access to the
  remote server goes through this; there is no `sqlcmd` on this box.
- The login (`flame`) is **dbcreator** and **owns the target DB**. That combination
  is exactly what SQL Server requires to `RESTORE` over an existing database while
  not being sysadmin. If the login does not own the target, the restore is denied.
- The target must be a **file-based `.bak`** the login can read. Nightly backups go
  to `B:\SQL Server\...\FULL\*.bak`; some entries in backup history are `{GUID}`
  appliance devices which are NOT restorable this way — the script skips them.

## Fast path: run the script

The whole sequence is deterministic, so use the bundled script rather than typing
SQL by hand. It auto-discovers the newest restorable backup, reads the backup's
logical file names, maps them onto the target's existing physical files, and does
the single-user → restore → multi-user dance with verification.

```bash
scripts/restore.sh <target_db> [source_db] [bak_path]
```

Example (the common case — refresh Tane's copy from staging):

```bash
scripts/restore.sh FlameInstructionManager_Tane
```

Defaults: `source_db=FlameInstructionManager`, newest file-based `.bak`, server
`10.10.17.216,1433`, login `flame`. Override the server/credentials with the
`FLINT_DB_SERVER` / `FLINT_DB_UID` / `FLINT_DB_PWD` environment variables (the
current password lives in the app's `appsettings.Development.json`).

**Before running, confirm two things with the user**, because a restore is
destructive and irreversible for the target:

1. They understand the target DB's current contents will be **wiped** and replaced
   with staging data (any local work in that copy is lost).
2. Which target DB — never guess. `_Tane` is Tane's; other people own `_Henry`, etc.

## What the script does (and the manual equivalent)

If you need to run it by hand or adapt it, this is the exact sequence. Run each
statement as its own `isql` invocation — multi-statement batches through `isql`
are fragile with the `$type`/`CAST`/`GO` handling.

1. **Find the backup** (newest file-based full backup of the source):
   ```sql
   SELECT TOP 1 bmf.physical_device_name
   FROM msdb.dbo.backupset bs
   JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id
   WHERE bs.database_name = 'FlameInstructionManager'
     AND bs.type = 'D' AND bmf.physical_device_name LIKE '%.bak'
   ORDER BY bs.backup_finish_date DESC;
   ```
2. **Read its logical file names** (needed for the MOVE clause):
   ```sql
   RESTORE FILELISTONLY FROM DISK = N'<bak_path>';
   ```
   Take the `LogicalName` where `Type='D'` (data) and `Type='L'` (log).
3. **Find the target's physical file paths** so you restore in place, over them:
   ```sql
   SELECT physical_name, type_desc FROM sys.master_files
   WHERE database_id = DB_ID('<target_db>');
   ```
4. **Restore**, forcing others off first and putting the DB back afterwards:
   ```sql
   ALTER DATABASE [<target_db>] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

   RESTORE DATABASE [<target_db>] FROM DISK = N'<bak_path>'
   WITH MOVE N'<data_logical>' TO N'<target_data_path>',
        MOVE N'<log_logical>'  TO N'<target_log_path>',
        REPLACE, RECOVERY;

   ALTER DATABASE [<target_db>] SET MULTI_USER;
   ```

`REPLACE` allows overwriting an existing DB; `MOVE` remaps the backup's logical
files onto the target's own physical files so you don't clobber the source DB's
files or collide with another copy.

## After the restore

- The restored DB is staging as of the backup time (nightly). It will **not**
  contain any in-flight migrations from your branch — the app applies them on next
  startup. That clean slate is usually the point of restoring.
- Verify quickly: check `SELECT MAX(Version) FROM VersionInfo` matches staging's
  level, and `SELECT COUNT(*) FROM FolderItems` is the expected ~49k.
- The DB comes back `ONLINE`, `MULTI_USER`, `SIMPLE` recovery — ready for the app.

## Verifying a suspected-bad copy first (optional)

If the user isn't sure the copy is actually dirty, look at the most recently
created folder items before wiping. `FolderItems` has no timestamp column; use the
audit table `FolderItemRevisions` (its `CreatedDate` + earliest `Version` per `Id`):

```sql
SELECT TOP 10 f.Id, f.Name, f.CreatedDate, f.UserName
FROM (SELECT Id, Name, CreatedDate, UserName,
             ROW_NUMBER() OVER (PARTITION BY Id ORDER BY Version ASC, CreatedDate ASC) AS rn
      FROM dbo.FolderItemRevisions) f
WHERE f.rn = 1
ORDER BY f.CreatedDate DESC;
```

Locally-authored test rows (a burst created seconds apart by one user, or names
like `NEW001`) are the usual culprits.
