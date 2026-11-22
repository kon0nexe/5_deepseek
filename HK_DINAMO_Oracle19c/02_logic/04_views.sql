-- =====================================================================
-- Представления для аналитических запросов и отчётности.
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE

CREATE OR REPLACE VIEW v_ticket_sales_by_period AS
SELECT d.full_date,
       d.year_num,
       d.month_num,
       d.month_name,
       d.season,
       COUNT(*) AS tickets_sold,
       SUM(t.price) AS revenue
  FROM tickets t
  JOIN dim_time d ON d.time_id = t.sale_time_id
 WHERE t.status = 'SOLD'
 GROUP BY d.full_date, d.year_num, d.month_num, d.month_name, d.season;

CREATE OR REPLACE VIEW v_player_popularity AS
SELECT p.player_id,
       p.first_name,
       p.last_name,
       COUNT(DISTINCT f.fan_id) AS fans_favorited
  FROM dim_player p
  LEFT JOIN fan_player_favorites f ON f.player_id = p.player_id
 GROUP BY p.player_id, p.first_name, p.last_name;

CREATE OR REPLACE VIEW v_player_performance AS
SELECT p.player_id,
       p.first_name,
       p.last_name,
       COUNT(s.stat_id) AS matches_count,
       NVL(SUM(s.goals), 0) AS goals_total,
       NVL(SUM(s.assists), 0) AS assists_total,
       NVL(SUM(s.points), 0) AS points_total,
       NVL(SUM(s.shots), 0) AS shots_total,
       NVL(SUM(s.penalty_minutes), 0) AS penalty_minutes_total
  FROM dim_player p
  LEFT JOIN fact_match_stats s ON s.player_id = p.player_id
 GROUP BY p.player_id, p.first_name, p.last_name;

CREATE OR REPLACE VIEW v_merch_sales_by_period AS
SELECT d.full_date,
       d.year_num,
       d.month_num,
       d.season,
       m.merch_id,
       m.name AS merch_name,
       SUM(o.quantity) AS quantity_sold,
       SUM(o.total_amount) AS revenue
  FROM merch_orders o
  JOIN dim_time d ON d.time_id = o.time_id
  JOIN dim_merch m ON m.merch_id = o.merch_id
 WHERE o.status = 'COMPLETED'
 GROUP BY d.full_date, d.year_num, d.month_num, d.season, m.merch_id, m.name;

PROMPT Представления V_TICKET_SALES_BY_PERIOD, V_PLAYER_POPULARITY,
PROMPT V_PLAYER_PERFORMANCE и V_MERCH_SALES_BY_PERIOD созданы.
