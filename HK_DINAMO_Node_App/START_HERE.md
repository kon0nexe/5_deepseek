# Быстрый старт веб-приложения «Динамо-Минск»

Клиентская часть написана на обычных **HTML, CSS и JavaScript**. Node.js + Express предоставляет REST API и подключение к Oracle Database 19c. Шаблонизатор EJS не используется; папки `views/` в проекте нет.

1. Убедись, что Docker Desktop запущен и контейнер Oracle `oracle19c-dinamo` работает.
2. Для новой базы используй корневой установщик комплекта `01_INSTALL_ALL.bat`; для уже созданной схемы HK_DINAMO выбирай режим 3.
3. Проверь, что в PDB установлены `PKG_WEB_API` и пользователь `HK_WEB_APP`, которому выдан EXECUTE на `HK_DINAMO.PKG_WEB_API`.
4. В каталоге приложения создай `.env` на основе `.env.example` и укажи DB_PASSWORD пользователя HK_WEB_APP, connect string и свои секреты.
5. Установи Node.js 22 или новее.
6. Выполни `npm install`, затем `npm run check`, затем `npm start`.
7. Открой `http://localhost:3000/health`, затем `http://localhost:3000/setup` для создания главного администратора, если он ещё не создан.

Файлы frontend: `public/index.html` (статическая HTML-оболочка), `public/styles.css` (CSS) и `public/app.js` (браузерный JavaScript, который формирует содержимое экранов и обращается к REST API). Сервер и REST API: `server.js`. Oracle PL/SQL-шлюз: `db/01_web_app_api.sql`. Отдельных EJS-шаблонов и зависимости `ejs` нет.

Секретный файл `.env` не отправляй и не публикуй.
