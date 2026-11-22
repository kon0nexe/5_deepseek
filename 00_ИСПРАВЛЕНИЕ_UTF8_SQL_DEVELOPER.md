# Исправление отображения русских символов в Oracle SQL Developer

В базе проекта уже проверялась функция ASCIISTR: она возвращала Unicode-коды русских названий (`\041C\0438...`). Это означает, что текстовые значения в Oracle сохранены корректно. Не нужно пересоздавать базу или менять её charset.

1. Открой SQL Developer.
2. Перейди в Tools → Preferences → Environment → Encoding и выбери UTF-8.
3. Перейди в Tools → Preferences → Code Editor → Fonts и выбери Consolas или Segoe UI (шрифт должен содержать кириллицу).
4. Нажми OK и полностью перезапусти SQL Developer.
5. Открой `HK_DINAMO_Node_App/db/06_unicode_diagnostic.sql`, выполни F5 и сравни `UNICODE_TEST` со столбцом `UNICODE_CODEPOINTS`.

Для контрольной проверки выполни:

```sql
SELECT name, ASCIISTR(name) AS codepoints FROM dim_stadium;
SELECT opponent_name, ASCIISTR(opponent_name) AS codepoints
FROM dim_match WHERE match_id=1;
```

Если `ASCIISTR` возвращает `\041C\0438...`, а обычный текст по-прежнему отображается как `????`/`����`, данные есть, проблема на стороне интерфейса/шрифта SQL Developer.

Важно: SQL Developer работает через Oracle JDBC и использует Unicode; NLS_LANG не является настройкой кодировки JDBC-клиента. Установщик задаёт `NLS_LANG=AMERICAN_AMERICA.AL32UTF8` и `LANG=C.UTF-8` только для SQL*Plus внутри Linux-контейнера. Не задавай наугад Windows `NLS_LANG=...AL32UTF8` и не запускай `ALTER DATABASE CHARACTER SET` на заполненной базе.
