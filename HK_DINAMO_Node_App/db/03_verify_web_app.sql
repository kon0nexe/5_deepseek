-- Проверка расширения веб-приложения. Выполнять от HK_DINAMO в той же PDB.
SET LINESIZE 180
SET PAGESIZE 100
PROMPT === Статус объектов PKG_WEB_API ===
SELECT object_name, object_type, status
  FROM user_objects
 WHERE object_name = 'PKG_WEB_API'
 ORDER BY object_type;
PROMPT === Ошибки компиляции PKG_WEB_API ===
SELECT line, position, text
  FROM user_errors
 WHERE name = 'PKG_WEB_API'
 ORDER BY sequence;
PROMPT === Наличие demo-матча ===
SELECT match_id, match_date, opponent_name, stadium_id
  FROM dim_match
 WHERE match_id = 1;
PROMPT === Количество мест на демонстрационный матч ===
SELECT COUNT(*) AS demo_seats,
       COUNT(DISTINCT sector_id) AS sectors,
       COUNT(DISTINCT seat_row) AS rows_count
  FROM tickets t
  JOIN dim_match m ON m.match_id=t.match_id
 WHERE m.match_id = 1;
PROMPT === Билеты по статусам на demo-матч ===
SELECT t.status, COUNT(*) AS tickets_count
  FROM tickets t
  JOIN dim_match m ON m.match_id=t.match_id
 WHERE m.match_id = 1
 GROUP BY t.status
 ORDER BY t.status;
PROMPT === Технический пользователь ===
SELECT username
  FROM all_users
 WHERE username = 'HK_WEB_APP';
