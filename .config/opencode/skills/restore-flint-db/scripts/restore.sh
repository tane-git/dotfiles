#!/usr/bin/env bash
#
# Refresh a personal Flint DB copy from the latest FlameInstructionManager full backup.
#
# Usage:
#   restore.sh <target_db> [source_db] [bak_path]
#
#   target_db  Database to overwrite (e.g. FlameInstructionManager_Tane). REQUIRED.
#   source_db  Source whose backup we restore from. Default: FlameInstructionManager.
#   bak_path   Explicit .bak on the server. Default: newest file-based backup of source_db.
#
# Env (override the defaults for a different server/login):
#   FLINT_DB_SERVER  Default: 10.10.17.216,1433
#   FLINT_DB_UID     Default: flame
#   FLINT_DB_PWD     Required, no default - set it in ~/.zshrc.local
#
# Requires: isql (unixODBC) + "ODBC Driver 18 for SQL Server".
# The login must be dbcreator AND own target_db (RESTORE runs as its owner).

set -euo pipefail

TARGET_DB="${1:?target_db is required, e.g. FlameInstructionManager_Tane}"
SOURCE_DB="${2:-FlameInstructionManager}"
BAK_PATH="${3:-}"

SERVER="${FLINT_DB_SERVER:-10.10.17.216,1433}"
UID_="${FLINT_DB_UID:-flame}"
PWD_="${FLINT_DB_PWD:?FLINT_DB_PWD must be set - see ~/.zshrc.local}"

conn() { echo "DRIVER={ODBC Driver 18 for SQL Server};SERVER=${SERVER};UID=${UID_};PWD=${PWD_};TrustServerCertificate=yes;Encrypt=no;DATABASE=${1}"; }

# Run one SQL statement, fail on error (-b), print rows.
sql() { local db="$1"; shift; isql -k "$(conn "$db")" -b <<SQL
$*
SQL
}

# Run one SQL statement and return only the first data value (for scripting).
# isql -x (batch mode) prints just the row values, one per line, no headers/borders.
sql_scalar() { local db="$1"; shift; isql -k "$(conn "$db")" -b -x0x09 <<SQL 2>/dev/null | grep -v '^$' | head -1 | sed 's/[[:space:]]*$//'
$*
SQL
}

echo ">> Server: ${SERVER}  Login: ${UID_}"
echo ">> Target: ${TARGET_DB}   Source: ${SOURCE_DB}"

# 1. Sanity: target exists and we own it.
OWNER="$(sql_scalar master "SELECT SUSER_SNAME(owner_sid) FROM sys.databases WHERE name = '${TARGET_DB}'")"
if [ -z "${OWNER}" ]; then
  echo "!! Target DB '${TARGET_DB}' does not exist. Aborting." >&2; exit 1
fi
echo ">> Target owner: ${OWNER}"

# 2. Resolve the backup file if not supplied: newest FILE-based full backup (skip {GUID} appliance devices).
if [ -z "${BAK_PATH}" ]; then
  echo ">> Finding newest file-based full backup of ${SOURCE_DB}..."
  BAK_PATH="$(sql_scalar msdb "SELECT TOP 1 bmf.physical_device_name FROM msdb.dbo.backupset bs JOIN msdb.dbo.backupmediafamily bmf ON bs.media_set_id = bmf.media_set_id WHERE bs.database_name = '${SOURCE_DB}' AND bs.type = 'D' AND bmf.physical_device_name LIKE '%.bak' ORDER BY bs.backup_finish_date DESC")"
fi
if [ -z "${BAK_PATH}" ]; then
  echo "!! No file-based .bak found for ${SOURCE_DB}. Pass an explicit bak_path." >&2; exit 1
fi
echo ">> Backup file: ${BAK_PATH}"

# 3. Read the backup's logical file names (data + log) so the MOVE clause is correct.
echo ">> Reading backup header (RESTORE FILELISTONLY)..."
FILELIST="$(isql -k "$(conn master)" -b -x0x09 <<SQL
RESTORE FILELISTONLY FROM DISK = N'${BAK_PATH}'
SQL
)"
DATA_LOGICAL="$(echo "${FILELIST}" | awk -F'\t' '$3=="D"{print $1; exit}' | tr -d ' \r')"
LOG_LOGICAL="$(echo "${FILELIST}"  | awk -F'\t' '$3=="L"{print $1; exit}' | tr -d ' \r')"
if [ -z "${DATA_LOGICAL}" ] || [ -z "${LOG_LOGICAL}" ]; then
  echo "!! Could not parse logical file names from backup header." >&2
  echo "${FILELIST}" >&2; exit 1
fi
echo ">> Logical files: data='${DATA_LOGICAL}' log='${LOG_LOGICAL}'"

# 4. Discover the target's current physical file paths (restore in place, over them).
DATA_PHYS="$(sql_scalar master "SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID('${TARGET_DB}') AND type_desc = 'ROWS'")"
LOG_PHYS="$(sql_scalar master "SELECT physical_name FROM sys.master_files WHERE database_id = DB_ID('${TARGET_DB}') AND type_desc = 'LOG'")"
echo ">> Target files: data='${DATA_PHYS}' log='${LOG_PHYS}'"

# 5. Warn if anyone else is connected.
SESSIONS="$(sql_scalar master "SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE database_id = DB_ID('${TARGET_DB}') AND is_user_process = 1")"
echo ">> Active user sessions on target: ${SESSIONS:-0} (will be forced off)"

# 6. Restore: single-user -> restore with move+replace -> multi-user.
echo ">> [1/3] SET SINGLE_USER..."
sql master "ALTER DATABASE [${TARGET_DB}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE"

echo ">> [2/3] RESTORE (this can take a while for large DBs)..."
sql master "RESTORE DATABASE [${TARGET_DB}] FROM DISK = N'${BAK_PATH}' WITH MOVE N'${DATA_LOGICAL}' TO N'${DATA_PHYS}', MOVE N'${LOG_LOGICAL}' TO N'${LOG_PHYS}', REPLACE, RECOVERY"

echo ">> [3/3] SET MULTI_USER..."
sql master "ALTER DATABASE [${TARGET_DB}] SET MULTI_USER"

# 7. Verify.
echo ">> Verifying..."
sql master "SELECT name, state_desc, user_access_desc FROM sys.databases WHERE name = '${TARGET_DB}'"
echo ">> Done. ${TARGET_DB} restored from ${BAK_PATH}"
