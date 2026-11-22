-- HK_DINAMO schema install. Use absolute paths in the container to avoid SQL*Plus @@ path ambiguity.
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET ECHO ON
SET SERVEROUTPUT ON

@/tmp/HK_DINAMO_Oracle19c/01_schema/01_tables.sql
@/tmp/HK_DINAMO_Oracle19c/02_logic/02_triggers.sql
@/tmp/HK_DINAMO_Oracle19c/02_logic/03_functions.sql
@/tmp/HK_DINAMO_Oracle19c/02_logic/04_views.sql
@/tmp/HK_DINAMO_Oracle19c/02_logic/05_packages.sql
@/tmp/HK_DINAMO_Oracle19c/04_data/06_seed_demo_data.sql
@/tmp/HK_DINAMO_Oracle19c/03_security/07_grants.sql
@/tmp/HK_DINAMO_Oracle19c/06_performance/07_load_100k_tickets.sql

PROMPT Проверка состояния объектов:
SELECT object_type, status, COUNT(*) AS object_count
  FROM user_objects
 WHERE object_type IN ('TABLE','VIEW','FUNCTION','PROCEDURE','PACKAGE','TRIGGER','INDEX')
 GROUP BY object_type,status
 ORDER BY object_type,status;

PROMPT Ошибки компиляции:
SELECT name, type, line, position, text
  FROM user_errors
 ORDER BY name, sequence;
