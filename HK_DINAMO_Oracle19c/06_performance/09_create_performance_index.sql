-- =====================================================================
-- Индекс, проверяемый в эксперименте производительности.
-- Выполнять от HK_DINAMO после скрипта 08_perf_before_indexes.sql.
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE
CREATE INDEX idx_tickets_perf_date_status ON tickets(sale_time_id,status);
BEGIN
    DBMS_STATS.GATHER_TABLE_STATS(USER,'TICKETS',cascade=>TRUE);
END;
/
PROMPT Индекс IDX_TICKETS_PERF_DATE_STATUS создан; статистика обновлена.
