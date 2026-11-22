-- =====================================================================
-- Выдача доступа через пакеты PL/SQL. Табличные привилегии не выдаются.
-- Выполнять от HK_DINAMO после создания пакетов.
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE

GRANT EXECUTE ON pkg_user_api TO HK_USER_ROLE;
GRANT EXECUTE ON pkg_admin_api TO HK_ADMIN_ROLE;
GRANT EXECUTE ON pkg_json_io TO HK_ADMIN_ROLE;
GRANT EXECUTE ON pkg_security_api TO HK_MAIN_ADMIN_ROLE;
GRANT EXECUTE ON f_ticket_revenue TO HK_ADMIN_ROLE;
GRANT EXECUTE ON f_player_popularity TO HK_ADMIN_ROLE;

PROMPT Права EXECUTE выданы ролям HK_USER_ROLE, HK_ADMIN_ROLE и HK_MAIN_ADMIN_ROLE.
PROMPT Прямых SELECT/INSERT/UPDATE/DELETE-привилегий на таблицы не выдавалось.
