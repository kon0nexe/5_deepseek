-- =====================================================================
-- Демонстрационные справочные и операционные данные.
-- Выполнять от HK_DINAMO на пустой схеме после установки объектов.
-- =====================================================================
WHENEVER SQLERROR EXIT SQL.SQLCODE
SET SERVEROUTPUT ON

-- Календарь на 2024–2035 гг. Включает текущую дату и даты тестовых матчей.
INSERT INTO dim_time(time_id,full_date,day_of_week,day_num,month_num,
                     month_name,quarter_num,year_num,season)
SELECT TO_NUMBER(TO_CHAR(d,'YYYYMMDD')),
       d,
       TO_CHAR(d,'FMDAY','NLS_DATE_LANGUAGE=RUSSIAN'),
       TO_NUMBER(TO_CHAR(d,'DD')),
       TO_NUMBER(TO_CHAR(d,'MM')),
       TO_CHAR(d,'FMMONTH','NLS_DATE_LANGUAGE=RUSSIAN'),
       TO_NUMBER(TO_CHAR(d,'Q')),
       TO_NUMBER(TO_CHAR(d,'YYYY')),
       CASE WHEN TO_NUMBER(TO_CHAR(d,'MM')) >= 7
            THEN TO_CHAR(TO_NUMBER(TO_CHAR(d,'YYYY'))) || '/' ||
                 TO_CHAR(TO_NUMBER(TO_CHAR(d,'YYYY'))+1)
            ELSE TO_CHAR(TO_NUMBER(TO_CHAR(d,'YYYY'))-1) || '/' ||
                 TO_CHAR(TO_NUMBER(TO_CHAR(d,'YYYY')))
       END
  FROM (SELECT DATE '2024-01-01' + LEVEL - 1 AS d
          FROM dual
        CONNECT BY LEVEL <= (DATE '2035-12-31' - DATE '2024-01-01') + 1);

DECLARE
    l_stadium_id NUMBER;
    l_sector_a   NUMBER;
    l_sector_b   NUMBER;
    l_player_1   NUMBER;
    l_player_2   NUMBER;
    l_player_3   NUMBER;
    l_fan_id     NUMBER;
    l_merch_1    NUMBER;
    l_merch_2    NUMBER;
    l_match_id   NUMBER;
    l_today_id   NUMBER;
    l_match_time NUMBER;
    l_ticket_id  NUMBER;
    l_order_id   NUMBER;
BEGIN
    INSERT INTO dim_stadium(name,city,capacity)
    VALUES(UNISTR('\041C\0438\043D\0441\043A-\0410\0440\0435\043D\0430'),UNISTR('\041C\0438\043D\0441\043A'),15000)
    RETURNING stadium_id INTO l_stadium_id;

    INSERT INTO dim_sector(stadium_id,sector_code,category,capacity)
    VALUES(l_stadium_id,'A','STANDARD',5000)
    RETURNING sector_id INTO l_sector_a;

    INSERT INTO dim_sector(stadium_id,sector_code,category,capacity)
    VALUES(l_stadium_id,'B','FAN',5000)
    RETURNING sector_id INTO l_sector_b;

    INSERT INTO dim_player(first_name,last_name,position,jersey_number,
                           birth_date,country,height_cm,weight_kg)
    VALUES(UNISTR('\0414\0435\043C\043E'),UNISTR('\041D\0430\043F\0430\0434\0430\044E\0449\0438\0439'),'FORWARD',10,DATE '1998-04-12',UNISTR('\0411\0435\043B\0430\0440\0443\0441\044C'),183,82)
    RETURNING player_id INTO l_player_1;

    INSERT INTO dim_player(first_name,last_name,position,jersey_number,
                           birth_date,country,height_cm,weight_kg)
    VALUES(UNISTR('\0414\0435\043C\043E'),UNISTR('\0417\0430\0449\0438\0442\043D\0438\043A'),'DEFENDER',22,DATE '1997-08-03',UNISTR('\0411\0435\043B\0430\0440\0443\0441\044C'),188,90)
    RETURNING player_id INTO l_player_2;

    INSERT INTO dim_player(first_name,last_name,position,jersey_number,
                           birth_date,country,height_cm,weight_kg)
    VALUES(UNISTR('\0414\0435\043C\043E'),UNISTR('\0412\0440\0430\0442\0430\0440\044C'),'GOALTENDER',30,DATE '1999-01-20',UNISTR('\0411\0435\043B\0430\0440\0443\0441\044C'),190,87)
    RETURNING player_id INTO l_player_3;

    INSERT INTO dim_fan(first_name,last_name,email,phone,city)
    VALUES(UNISTR('\0422\0435\0441\0442\043E\0432\044B\0439'),UNISTR('\0411\043E\043B\0435\043B\044C\0449\0438\043A'),'fan.demo@example.local','+375000000000',UNISTR('\041C\0438\043D\0441\043A'))
    RETURNING fan_id INTO l_fan_id;

    INSERT INTO dim_merch(name,category,price,description)
    VALUES(UNISTR('\0428\0430\0440\0444 \043A\043B\0443\0431\0430'),UNISTR('\0421\0443\0432\0435\043D\0438\0440\044B'),35.00,UNISTR('\0414\0435\043C\043E\043D\0441\0442\0440\0430\0446\0438\043E\043D\043D\044B\0439 \0448\0430\0440\0444 \0441 \0441\0438\043C\0432\043E\043B\0438\043A\043E\0439 \043A\043B\0443\0431\0430'))
    RETURNING merch_id INTO l_merch_1;

    INSERT INTO dim_merch(name,category,price,description)
    VALUES(UNISTR('\0424\0443\0442\0431\043E\043B\043A\0430 \043A\043B\0443\0431\0430'),UNISTR('\041E\0434\0435\0436\0434\0430'),65.00,UNISTR('\0414\0435\043C\043E\043D\0441\0442\0440\0430\0446\0438\043E\043D\043D\0430\044F \0444\0443\0442\0431\043E\043B\043A\0430 \043A\043B\0443\0431\0430'))
    RETURNING merch_id INTO l_merch_2;

    SELECT time_id INTO l_today_id
      FROM dim_time WHERE full_date=TRUNC(SYSDATE);

    SELECT time_id INTO l_match_time
      FROM dim_time WHERE full_date=DATE '2026-11-20';

    INSERT INTO dim_match(match_date,time_id,opponent_name,stadium_id,is_home)
    VALUES(DATE '2026-11-20',l_match_time,UNISTR('\0414\0435\043C\043E\043D\0441\0442\0440\0430\0446\0438\043E\043D\043D\044B\0439 \0441\043E\043F\0435\0440\043D\0438\043A'),l_stadium_id,'Y')
    RETURNING match_id INTO l_match_id;

    -- Три статуса билета для демонстрации операций.
    INSERT INTO tickets(match_id,sector_id,seat_row,seat_number,price,status)
    VALUES(l_match_id,l_sector_a,1,1,45,'FREE')
    RETURNING ticket_id INTO l_ticket_id;

    INSERT INTO tickets(match_id,sector_id,seat_row,seat_number,price,status,
                        reserved_by,reserved_until)
    VALUES(l_match_id,l_sector_a,1,2,45,'RESERVED',l_fan_id,SYSDATE+30/1440);

    INSERT INTO tickets(match_id,sector_id,seat_row,seat_number,price,status,
                        fan_id,sale_time_id)
    VALUES(l_match_id,l_sector_a,1,3,45,'SOLD',l_fan_id,l_today_id);

    INSERT INTO tickets(match_id,sector_id,seat_row,seat_number,price,status)
    VALUES(l_match_id,l_sector_b,1,1,55,'RETURNED');

    INSERT INTO fact_match_stats(match_id,player_id,time_id,goals,assists,
                                 penalty_minutes,plus_minus,shots,time_on_ice_sec)
    VALUES(l_match_id,l_player_1,l_match_time,1,1,2,1,4,1020);

    INSERT INTO fact_match_stats(match_id,player_id,time_id,goals,assists,
                                 penalty_minutes,plus_minus,shots,time_on_ice_sec)
    VALUES(l_match_id,l_player_2,l_match_time,0,1,0,1,2,1240);

    INSERT INTO fan_player_favorites(fan_id,player_id)
    VALUES(l_fan_id,l_player_1);

    INSERT INTO merch_orders(merch_id,fan_id,time_id,quantity,unit_price,status)
    VALUES(l_merch_1,l_fan_id,l_today_id,2,35,'COMPLETED');

    -- Связь учебной Oracle-учётной записи HK_USER с болельщиком.
    INSERT INTO app_users(username,password_hash,email,role,fan_id,db_username)
    VALUES('demo_user','DEMO_HASH_REPLACE_WITH_BCRYPT_OR_PBKDF2_HASH',
           'demo.user@example.local','USER',l_fan_id,'HK_USER');

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Демонстрационные данные добавлены. FAN_ID='||l_fan_id||
                         ', MATCH_ID='||l_match_id||', PLAYER_ID='||l_player_1);
END;
/

PROMPT Демонстрационные данные созданы.
