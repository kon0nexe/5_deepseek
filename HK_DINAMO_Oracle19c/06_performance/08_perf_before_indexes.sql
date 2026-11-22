-- =====================================================================
-- Фиксация плана и времени выполнения ДО создания дополнительного индекса.
-- Выполнять от HK_DINAMO после загрузки 100 000 строк.
-- =====================================================================
SET TIMING ON
SET LINESIZE 180
SET PAGESIZE 100

EXPLAIN PLAN SET STATEMENT_ID='TICKETS_BEFORE_IDX' FOR
SELECT /*+ FULL(t) */ COUNT(*) AS sold_tickets,
       NVL(SUM(t.price),0) AS revenue
  FROM tickets t
 WHERE t.status='SOLD'
   AND t.sale_time_id=(
       SELECT MAX(m.time_id)
         FROM dim_match m
        WHERE m.opponent_name LIKE 'TEST PERF %'
   );

SELECT *
  FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,'TICKETS_BEFORE_IDX','BASIC +COST +ROWS +PREDICATE'));

PROMPT Фактический запуск запроса ДО индексации:
SELECT /*+ FULL(t) */ COUNT(*) AS sold_tickets,
       NVL(SUM(t.price),0) AS revenue
  FROM tickets t
 WHERE t.status='SOLD'
   AND t.sale_time_id=(
       SELECT MAX(m.time_id)
         FROM dim_match m
        WHERE m.opponent_name LIKE 'TEST PERF %'
   );

PROMPT Сохраните время выполнения и план в таблицу результатов курсовой.
SET TIMING OFF
