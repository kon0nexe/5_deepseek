-- Выполнять после CONNECT HK_MAIN_ADMIN/...@<PDB_SERVICE>
VAR app_user_id NUMBER;
EXEC HK_DINAMO.PKG_SECURITY_API.CREATE_APP_USER(
  'demo_admin_app',
  'DEMO_HASH_VALUE_FROM_APPLICATION_PASSWORD_HASHER_2026',
  'demo.admin@example.local',
  'ADMIN',
  NULL,
  :app_user_id
);
PRINT app_user_id;
-- При необходимости привяжите запись к уже созданной Oracle-учётной записи:
-- EXEC HK_DINAMO.PKG_SECURITY_API.BIND_APP_USER_DB_USER(:app_user_id, 'HK_ADMIN');
COMMIT;
