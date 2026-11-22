-- =====================================================================
-- Фиксация плана и времени выполнения ПОСЛЕ создания индекса.
-- =====================================================================
SET TIMING ON
SET LINESIZE 180
SET PAGESIZE 100

EXPLAIN PLAN SET STATEMENT_ID='TICKETS_AFTER_IDX' FOR
SELECT /*+ INDEX(t idx_tickets_perf_date_status) */ COUNT(*) AS sold_tickets,
       NVL(SUM(t.price),0) AS revenue
  FROM tickets t
 WHERE t.status='SOLD'
   AND t.sale_time_id=(
       SELECT MAX(m.time_id)
         FROM dim_match m
        WHERE m.opponent_name LIKE 'TEST PERF %'
   );

SELECT *
  FROM TABLE(DBMS_XPLAN.DISPLAY(NULL,'TICKETS_AFTER_IDX','BASIC +COST +ROWS +PREDICATE'));

PROMPT Фактический запуск запроса ПОСЛЕ индексации:
SELECT /*+ INDEX(t idx_tickets_perf_date_status) */ COUNT(*) AS sold_tickets,
       NVL(SUM(t.price),0) AS revenue
  FROM tickets t
 WHERE t.status='SOLD'
   AND t.sale_time_id=(
       SELECT MAX(m.time_id)
         FROM dim_match m
        WHERE m.opponent_name LIKE 'TEST PERF %'
   );

PROMPT Сопоставьте время выполнения и планы ДО/ПОСЛЕ создания индекса.
SET TIMING OFF
