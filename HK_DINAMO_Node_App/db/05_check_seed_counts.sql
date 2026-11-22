-- Проверка количества основных данных. Выполнять от HK_DINAMO, PDB ORCLPDB1.
-- Используется внешний SELECT, чтобы корректно сортировать UNION ALL в Oracle.
SET LINESIZE 180
SET PAGESIZE 100
SELECT table_name, row_count
  FROM (
        SELECT 'DIM_TIME' AS table_name, COUNT(*) AS row_count FROM dim_time
        UNION ALL SELECT 'DIM_STADIUM', COUNT(*) FROM dim_stadium
        UNION ALL SELECT 'DIM_SECTOR', COUNT(*) FROM dim_sector
        UNION ALL SELECT 'DIM_PLAYER', COUNT(*) FROM dim_player
        UNION ALL SELECT 'DIM_FAN', COUNT(*) FROM dim_fan
        UNION ALL SELECT 'DIM_MATCH', COUNT(*) FROM dim_match
        UNION ALL SELECT 'DIM_MERCH', COUNT(*) FROM dim_merch
        UNION ALL SELECT 'TICKETS', COUNT(*) FROM tickets
        UNION ALL SELECT 'FACT_MATCH_STATS', COUNT(*) FROM fact_match_stats
        UNION ALL SELECT 'APP_USERS', COUNT(*) FROM app_users
        UNION ALL SELECT 'FAN_PLAYER_FAVORITES', COUNT(*) FROM fan_player_favorites
        UNION ALL SELECT 'MERCH_ORDERS', COUNT(*) FROM merch_orders
       ) q
 ORDER BY table_name;

PROMPT === Unicode-содержимое демо-строк (ASCIISTR) ===
SELECT m.match_id,
       ASCIISTR(m.opponent_name) AS opponent_ascii,
       ASCIISTR(s.name) AS stadium_ascii,
       ASCIISTR(s.city) AS city_ascii
  FROM dim_match m
  JOIN dim_stadium s ON s.stadium_id = m.stadium_id
 WHERE m.match_id = 1;

PROMPT === Технический пользователь ===
SELECT username
  FROM all_users
 WHERE username = 'HK_WEB_APP';
