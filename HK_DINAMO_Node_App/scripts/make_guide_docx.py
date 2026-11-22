from docx import Document
from docx.shared import Cm, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_CELL_VERTICAL_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.enum.section import WD_SECTION
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / 'Руководство_по_запуску_и_использованию.docx'
doc = Document()
sec = doc.sections[0]
sec.top_margin = Cm(2.0); sec.bottom_margin = Cm(1.8); sec.left_margin = Cm(2.4); sec.right_margin = Cm(1.8)

# Theme helpers
NAVY = '0B2441'; BLUE = '1679C5'; LIGHT = 'EAF3FB'; MUTED = '62778C'; WHITE='FFFFFF'
styles = doc.styles
for style_name in ['Normal','Title','Subtitle','Heading 1','Heading 2','Heading 3']:
    st = styles[style_name]
    st.font.name = 'Arial'
    st._element.rPr.rFonts.set(qn('w:ascii'), 'Arial')
    st._element.rPr.rFonts.set(qn('w:hAnsi'), 'Arial')
styles['Normal'].font.size = Pt(10.5)
styles['Normal'].font.color.rgb = RGBColor.from_string('21364D')
styles['Normal'].paragraph_format.space_after = Pt(5)
styles['Normal'].paragraph_format.line_spacing = 1.12
styles['Title'].font.size=Pt(27); styles['Title'].font.bold=True; styles['Title'].font.color.rgb=RGBColor.from_string(NAVY)
styles['Heading 1'].font.size=Pt(18); styles['Heading 1'].font.bold=True; styles['Heading 1'].font.color.rgb=RGBColor.from_string(NAVY)
styles['Heading 1'].paragraph_format.space_before=Pt(14); styles['Heading 1'].paragraph_format.space_after=Pt(6)
styles['Heading 2'].font.size=Pt(13); styles['Heading 2'].font.bold=True; styles['Heading 2'].font.color.rgb=RGBColor.from_string(BLUE)
styles['Heading 2'].paragraph_format.space_before=Pt(9); styles['Heading 2'].paragraph_format.space_after=Pt(4)

header = sec.header.paragraphs[0]
header.text = 'ХК «ДИНАМО-МИНСК»  |  NODE.JS WEB APP  |  ORACLE DATABASE 19c'
header.alignment = WD_ALIGN_PARAGRAPH.RIGHT
for r in header.runs:
    r.font.name='Arial'; r.font.size=Pt(8); r.font.bold=True; r.font.color.rgb=RGBColor.from_string('7890A8')
footer = sec.footer.paragraphs[0]
footer.text = 'Учебное демонстрационное приложение · Node.js / Express / PL/SQL'
footer.alignment = WD_ALIGN_PARAGRAPH.CENTER
for r in footer.runs:
    r.font.name='Arial'; r.font.size=Pt(8); r.font.color.rgb=RGBColor.from_string('7890A8')

# Title page block
p=doc.add_paragraph(); p.paragraph_format.space_before=Pt(55); p.alignment=WD_ALIGN_PARAGRAPH.CENTER
r=p.add_run('ДИНАМО'); r.font.name='Arial'; r.font.size=Pt(14); r.font.bold=True; r.font.letter_spacing=Pt(2) if hasattr(r.font,'letter_spacing') else None; r.font.color.rgb=RGBColor.from_string(BLUE)
p=doc.add_paragraph(style='Title'); p.alignment=WD_ALIGN_PARAGRAPH.CENTER
p.add_run('Руководство по запуску\nи использованию веб-приложения')
p=doc.add_paragraph(); p.alignment=WD_ALIGN_PARAGRAPH.CENTER
r=p.add_run('Node.js + Oracle Database 19c'); r.font.size=Pt(15); r.font.color.rgb=RGBColor.from_string(MUTED)
p=doc.add_paragraph(); p.alignment=WD_ALIGN_PARAGRAPH.CENTER; p.paragraph_format.space_before=Pt(28)
r=p.add_run('Курсовая работа: «Реализация базы данных хоккейного клуба\n„Динамо-Минск“ с применением OLAP-технологии»'); r.font.size=Pt(11); r.font.color.rgb=RGBColor.from_string('52677D')
p=doc.add_paragraph(); p.alignment=WD_ALIGN_PARAGRAPH.CENTER; p.paragraph_format.space_before=Pt(90)
r=p.add_run('Приложение предназначено для демонстрации взаимодействия\nвеб-интерфейса, серверной логики Node.js и хранимых пакетов PL/SQL.'); r.font.size=Pt(10); r.font.italic=True; r.font.color.rgb=RGBColor.from_string(MUTED)
doc.add_page_break()

def para(text, bold_prefix=None):
    p=doc.add_paragraph()
    if bold_prefix and text.startswith(bold_prefix):
        p.add_run(bold_prefix).bold=True; p.add_run(text[len(bold_prefix):])
    else: p.add_run(text)
    return p

def bullet(text):
    p=doc.add_paragraph(style='List Bullet'); p.add_run(text); return p

_numbered_index = 0
def reset_numbering():
    global _numbered_index
    _numbered_index = 0
def numbered(text):
    global _numbered_index
    _numbered_index += 1
    p=doc.add_paragraph()
    p.paragraph_format.left_indent=Cm(0.55)
    p.paragraph_format.first_line_indent=Cm(-0.55)
    p.add_run(f'{_numbered_index}. ').bold=True
    p.add_run(text)
    return p

def shade(cell, fill):
    tcPr=cell._tc.get_or_add_tcPr(); shd=OxmlElement('w:shd'); shd.set(qn('w:fill'),fill); tcPr.append(shd)

def set_cell_text(cell,text,bold=False,color=None,size=9):
    cell.text=''; p=cell.paragraphs[0]; p.paragraph_format.space_after=Pt(0)
    r=p.add_run(str(text)); r.bold=bold; r.font.name='Arial'; r.font.size=Pt(size)
    if color: r.font.color.rgb=RGBColor.from_string(color)
    cell.vertical_alignment=WD_CELL_VERTICAL_ALIGNMENT.CENTER

def table(headers, rows, widths=None):
    t=doc.add_table(rows=1, cols=len(headers)); t.alignment=WD_TABLE_ALIGNMENT.CENTER; t.style='Table Grid'
    for i,h in enumerate(headers):
        set_cell_text(t.rows[0].cells[i],h,True,WHITE,8.5); shade(t.rows[0].cells[i],NAVY)
    for ri,row in enumerate(rows):
        cells=t.add_row().cells
        for i,val in enumerate(row):
            set_cell_text(cells[i],val,False,'21364D',8.5)
            if ri%2==1: shade(cells[i],'F2F7FB')
    if widths:
        for row in t.rows:
            for i,w in enumerate(widths): row.cells[i].width=Cm(w)
    doc.add_paragraph().paragraph_format.space_after=Pt(1)
    return t

# Architecture
doc.add_heading('1. Назначение и архитектура', level=1)
para('Веб-приложение предназначено для демонстрации функциональных требований курсовой работы: просмотра состава и календаря матчей, резервирования мест, управления данными клуба, обмена JSON и формирования OLAP-отчётов.')
para('Поток обработки запроса: браузер (HTML/CSS/JavaScript) → Node.js / Express → Oracle-пакет HK_DINAMO.PKG_WEB_API → существующие пакеты PL/SQL и таблицы схемы HK_DINAMO.')
para('Доступ к таблицам из веб-приложения напрямую не предоставляется. Node.js подключается отдельной технической Oracle-учётной записью HK_WEB_APP, которой выдаётся EXECUTE только на PKG_WEB_API. Пакет выполняется с правами владельца схемы и вызывает исходные PKG_USER_API, PKG_ADMIN_API и PKG_SECURITY_API.')

doc.add_heading('2. Разделение ролей', level=1)
table(['Роль','Возможности в приложении'],[
('USER','Регистрация и вход; просмотр игроков, матчей и атрибутики; выбор сектора, ряда и места; резервирование на 15 минут; отмена или подтверждение покупки; избранные игроки; личные билеты.'),
('ADMIN','Все публичные возможности; CRUD игроков и матчей; управление билетами и атрибутикой; освобождение просроченных резервов; импорт/экспорт JSON; OLAP-аналитика.'),
('MAIN_ADMIN','Все возможности ADMIN; просмотр прикладных учётных записей; изменение ролей USER/ADMIN/MAIN_ADMIN; включение и отключение аккаунтов.')])
para('Главный администратор является прикладной ролью сайта и хранится в APP_USERS. Учётные записи SYS и SYSTEM относятся к администрированию самой СУБД в SQL Developer и не используются для входа в веб-приложение.')

doc.add_heading('3. Подготовка Oracle Database 19c', level=1)
reset_numbering()
numbered('Убедиться, что контейнер Oracle запущен и порт 1521 опубликован на Windows. Для другой публикации порта изменить значение в строке подключения приложения.')
numbered('В SQL Developer подключиться пользователем HK_DINAMO к нужной PDB (например, ORCLPDB1). Открыть db/01_web_app_api.sql и выполнить как Script (F5).')
numbered('Проверить, что HK_DINAMO.PKG_WEB_API имеет статус VALID. Скрипт также создаёт недостающие места демонстрационного матча, сохраняя уже существующие тестовые билеты.')
numbered('В SQL Developer подключиться как SYSDBA к той же PDB, открыть db/02_create_web_user.sql, заменить пароль в файле и выполнить сценарий. Он создаёт/обновляет HK_WEB_APP и выдаёт только CREATE SESSION и EXECUTE на PKG_WEB_API.')
numbered('Снова подключиться как HK_DINAMO и выполнить db/03_verify_web_app.sql. Убедиться, что пакет имеет статус VALID, ошибок компиляции нет, а для демонстрационного матча создано не менее 10 000 мест.')
para('Важно: SQL-сценарии веб-приложения не удаляют исходные таблицы и записи курсового проекта. Их нужно выполнять после успешной установки основной схемы HK_DINAMO.')

doc.add_heading('4. Подготовка Node.js и запуск', level=1)
reset_numbering()
numbered('Установить Node.js версии 22 или новее и открыть PowerShell в каталоге проекта HK_DINAMO_Node_App.')
numbered('Скопировать .env.example в .env командой: Copy-Item .env.example .env.')
numbered('Заполнить DB_USER=HK_WEB_APP, DB_PASSWORD (тот же пароль, который был задан в SQL Developer), DB_CONNECT_STRING=127.0.0.1:1521/ORCLPDB1.')
numbered('Сгенерировать случайные значения SETUP_TOKEN и SESSION_SECRET: node -e "console.log(require(\'crypto\').randomBytes(32).toString(\'hex\'))". Выполнить команду дважды и сохранить разные результаты в .env.')
numbered('Выполнить npm install, затем npm run check и npm start. Для запуска из Проводника можно использовать start.bat (файл .env должен быть уже заполнен).')
numbered('Открыть браузер по адресу http://localhost:3000. При первом запуске перейти на /setup и создать первого MAIN_ADMIN.')

doc.add_heading('5. Основные страницы приложения', level=1)
table(['URL','Назначение'],[
('/', 'Главная страница и KPI из Oracle.'),
('/matches', 'Календарь матчей; карточка матча ведёт к схеме арены.'),
('/matches/:id/seats', 'Выбор сектора и ряда, отображение 100 мест выбранного ряда и резервирование.'),
('/players', 'Состав и спортивные показатели; добавить/удалить игрока из избранного.'),
('/merch', 'Каталог клубной атрибутики.'),
('/account/tickets', 'Мои резервы и покупки; подтверждение или отмена резерва.'),
('/admin', 'Панель администратора.'),
('/admin/players · /admin/matches · /admin/tickets · /admin/merch', 'Управление игроками, матчами, билетами и атрибутикой.'),
('/admin/json', 'Импорт и экспорт игроков в JSON.'),
('/admin/olap', 'Продажи по периодам, выручка, срезы и аналитика игроков.'),
('/super/users', 'Управление пользователями и ролями — только MAIN_ADMIN.')])

doc.add_heading('6. Выбор места и резервирование', level=1)
para('В пользовательском календаре выбирается матч, после чего приложение загружает из Oracle арену, сектора и строки билетов. В демонстрационной конфигурации два сектора содержат по 5 000 мест: 50 рядов по 100 мест. Каждое место соответствует отдельной записи TICKETS.')
para('Нажатие на свободное место вызывает PL/SQL-процедуру резервирования. Она блокирует выбранную запись билета, проверяет статус, очищает просроченный резерв и записывает FAN_ID пользователя и время окончания резерва. Это предотвращает одновременное бронирование одного места разными пользователями.')
para('После резервирования пользователь может отменить резерв или нажать «Завершить покупку». В учебном приложении второй шаг меняет статус билета на SOLD и сохраняет дату продажи. Реальная оплата банковской картой не выполняется.')

doc.add_heading('7. OLAP и JSON', level=1)
para('Страница /admin/olap выполняет SQL-запросы в Oracle по фактическим данным. Оператор ROLLUP формирует иерархические итоги продаж по сезону, году и месяцу. Оператор CUBE выдаёт комбинации измерений «сезон» и «категория сектора». GROUPING_ID позволяет определить уровень итоговой строки.')
para('Популярность игроков вычисляется по количеству болельщиков, добавивших хоккеиста в избранное. Спортивная результативность рассчитывается отдельно по голам, передачам и суммарным очкам из FACT_MATCH_STATS.')
para('Для JSON-импорта приложение передаёт содержимое выбранного файла в Oracle как CLOB. PKG_WEB_API разбирает массив players с помощью JSON_TABLE. Экспорт формируется средствами JSON_OBJECT и JSON_ARRAYAGG и возвращается браузеру как JSON-файл.')

doc.add_heading('8. Учебные ограничения и проверка', level=1)
bullet('Подтверждение билета — демонстрационная операция в БД; платёжный шлюз отсутствует.')
bullet('100 000 записей тестирования производительности остаются в TICKETS; матчи TEST PERF % скрыты из публичного календаря.')
bullet('Пользовательские пароли хранятся как bcrypt-хеши в APP_USERS.PASSWORD_HASH; открытый пароль не передаётся в Oracle.')
bullet('Перед запуском проверь статус пакета: SELECT OBJECT_NAME, STATUS FROM ALL_OBJECTS WHERE OWNER=\'HK_DINAMO\' AND OBJECT_NAME=\'PKG_WEB_API\';')
bullet('Проверить соединение приложения можно по адресу http://localhost:3000/health.')

p=doc.add_paragraph(); p.paragraph_format.space_before=Pt(10)
r=p.add_run('Состав поставки: '); r.bold=True
p.add_run('README.md, SQL-сценарии расширения, server.js, src/, public/index.html, public/styles.css, public/app.js и файл .env.example. Подробная последовательность запуска также приведена в README.md.')

doc.core_properties.title='Руководство по запуску и использованию веб-приложения ХК Динамо-Минск'
doc.core_properties.subject='Node.js + Oracle Database 19c'
doc.core_properties.author=''
doc.save(OUT)
print(OUT)
