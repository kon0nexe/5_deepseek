-- =====================================================================
-- Дополнительные B-tree индексы для типовых связей и фильтров приложения.
-- Выполнять после эксперимента сравнения планов.
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE

CREATE INDEX idx_sector_stadium ON dim_sector(stadium_id);
CREATE INDEX idx_match_date ON dim_match(match_date);
CREATE INDEX idx_match_stadium_date ON dim_match(stadium_id,match_date);
CREATE INDEX idx_player_name ON dim_player(last_name,first_name);
CREATE INDEX idx_ticket_match_status ON tickets(match_id,status);
CREATE INDEX idx_ticket_fan ON tickets(fan_id);
CREATE INDEX idx_merch_ord_time_st ON merch_orders(time_id,status);
CREATE INDEX idx_stats_player_match ON fact_match_stats(player_id,match_id);
CREATE INDEX idx_favorites_player ON fan_player_favorites(player_id);

BEGIN
    DBMS_STATS.GATHER_SCHEMA_STATS(USER,cascade=>TRUE);
END;
/
PROMPT Дополнительные индексы созданы; статистика схемы обновлена.
