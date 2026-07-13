-- Run this first to see what's actually in your system_settings table
-- right now (columns + types, and whether it already has any rows).

SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'system_settings'
ORDER BY ordinal_position;

SELECT * FROM system_settings;
