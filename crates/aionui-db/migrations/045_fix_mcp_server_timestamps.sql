-- Migration 045: normalize malformed legacy values in `mcp_servers`.
--
-- This is the mcp_servers counterpart of 005_fix_real_timestamps.sql, which
-- fixed the exact same class of failure for `conversations`:
--
--   "sqlx cannot decode REAL values into i64, causing the conversations list
--    API to fail."
--
-- `mcp_servers.created_at` / `updated_at` are declared INTEGER, but rows
-- written by the TypeScript era (or imported / hand-edited afterwards) can
-- still hold a TEXT date such as '2026-03-01 10:48:38' or an ISO-8601 string.
-- sqlx decodes the whole result set strictly, so a SINGLE such row makes
-- `GET /api/mcp/servers` fail to deserialize and return HTTP 500 — taking down
-- the whole MCP settings page and the agent tool catalog, not just one entry.
--
-- Because one bad row breaks the entire query, there is no graceful degradation
-- to fall back on: the repair has to happen before the first read.

-- Convert TEXT timestamps to INTEGER milliseconds.
-- strftime('%s') accepts both the "YYYY-MM-DD HH:MM:SS" form and ISO-8601, and
-- returns UTC seconds; multiplying by 1000 yields the epoch milliseconds the
-- rest of the schema uses. Rows whose value cannot be parsed yield NULL from
-- strftime and are therefore left untouched rather than silently zeroed.
UPDATE mcp_servers
SET created_at = CAST(strftime('%s', created_at) AS INTEGER) * 1000
WHERE typeof(created_at) = 'text'
  AND strftime('%s', created_at) IS NOT NULL;

UPDATE mcp_servers
SET updated_at = CAST(strftime('%s', updated_at) AS INTEGER) * 1000
WHERE typeof(updated_at) = 'text'
  AND strftime('%s', updated_at) IS NOT NULL;

-- Restore the `user_` prefix on owner ids that lost it, which breaks the
-- foreign key to users(id) and makes the row unresolvable for per-user queries.
-- Only repairs ids that actually exist under the prefixed form, so an id with
-- no matching user is left alone instead of being pointed at a wrong account.
UPDATE mcp_servers
SET user_id = 'user_' || user_id
WHERE user_id IS NOT NULL
  AND user_id NOT LIKE 'user!_%' ESCAPE '!'
  AND EXISTS (SELECT 1 FROM users u WHERE u.id = 'user_' || mcp_servers.user_id);
