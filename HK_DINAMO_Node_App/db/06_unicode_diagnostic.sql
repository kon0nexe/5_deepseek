-- Проверка Unicode в Oracle. Выполнять от HK_DINAMO в PDB.
SET LINESIZE 180
SET PAGESIZE 80
PROMPT === Character sets ===
SELECT parameter, value
  FROM nls_database_parameters
 WHERE parameter IN ('NLS_CHARACTERSET','NLS_NCHAR_CHARACTERSET')
 ORDER BY parameter;
PROMPT === Unicode test literal (should display: Минск-Арена) ===
SELECT UNISTR('\041C\0438\043D\0441\043A-\0410\0440\0435\043D\0430') AS unicode_test,
       ASCIISTR(UNISTR('\041C\0438\043D\0441\043A-\0410\0440\0435\043D\0430')) AS unicode_codepoints
  FROM dual;
PROMPT === Stored demo values ===
SELECT match_id, ASCIISTR(opponent_name) AS opponent_codepoints
  FROM dim_match
 WHERE match_id=1;
SELECT stadium_id, ASCIISTR(name) AS stadium_codepoints,
       ASCIISTR(city) AS city_codepoints
  FROM dim_stadium
 WHERE stadium_id=(SELECT stadium_id FROM dim_match WHERE match_id=1);
