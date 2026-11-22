/* ============================================================================
   Клиентское приложение ХК «Динамо-Минск».
   Обычные HTML/CSS/JavaScript без шаблонизатора. Данные — через REST API
   Node.js/Express, который обращается к пакету PKG_WEB_API в Oracle 19c.
   ========================================================================== */
'use strict';

const appRoot = document.getElementById('app');
const state = { session: null, selectedSeat: null, notice: null };

const ADMIN_ROLES = ['ADMIN', 'MAIN_ADMIN'];
const USER_ROLE = 'USER';

/* ---------- Утилиты ---------- */
const esc = (value) => String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const money = (v) => new Intl.NumberFormat('ru-RU', { style: 'currency', currency: 'BYN', maximumFractionDigits: 0 }).format(Number(v || 0));
const num = (v) => Number(v || 0);

const dateFmt = (value, withTime = false) => {
  if (!value) return '—';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return esc(value);
  return new Intl.DateTimeFormat('ru-RU', withTime ? { dateStyle: 'medium', timeStyle: 'short' } : { dateStyle: 'long', timeZone: 'UTC' }).format(d);
};
const dateShort = (value) => {
  if (!value) return '';
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return d.toISOString().slice(0, 10);
};
const position = (v) => ({ GOALTENDER: 'Вратарь', DEFENDER: 'Защитник', FORWARD: 'Нападающий' })[v] || v || '—';
const status = (v) => ({ FREE: 'Свободно', RESERVED: 'Резерв', SOLD: 'Продан', RETURNED: 'Возвращён', SCHEDULED: 'Запланирован', COMPLETED: 'Завершён', CANCELLED: 'Отменён', Y: 'Активен', N: 'Отключён', PENDING: 'Ожидает' })[v] || v || '—';
const categoryLabel = (v) => ({ VIP: 'VIP', STANDARD: 'Стандарт', FAN: 'Фанатский', GUEST: 'Гостевой', OTHER: 'Прочее' })[v] || v || '—';

const isAdmin = () => state.session?.user && ADMIN_ROLES.includes(state.session.user.role);
const isMainAdmin = () => state.session?.user?.role === 'MAIN_ADMIN';
const isUser = () => state.session?.user?.role === USER_ROLE;

/* ---------- HTTP ---------- */
async function request(url, options = {}) {
  const headers = new Headers(options.headers || {});
  if (state.session?.csrfToken && !['GET', 'HEAD'].includes((options.method || 'GET').toUpperCase())) headers.set('X-CSRF-Token', state.session.csrfToken);
  if (options.body && !(options.body instanceof FormData) && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');
  const response = await fetch(url, { credentials: 'same-origin', ...options, headers });
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.includes('application/json')) {
    if (!response.ok) throw new Error(`Ошибка сервера (${response.status}).`);
    return response;
  }
  const data = await response.json();
  if (!response.ok || data.ok === false) throw new Error(data.error || `Ошибка сервера (${response.status}).`);
  return data;
}
const get = (url) => request(url);
const send = (url, method, body) => request(url, { method, body: JSON.stringify(body || {}) });

/* ---------- SVG-графика ---------- */
function crestSvg(extraClass = 'brand-crest') {
  return `<svg class="${extraClass}" viewBox="0 0 40 46" aria-hidden="true"><path d="M20 2 L37 8 V21 C37 33 30 41 20 45 C10 41 3 33 3 21 V8 Z" fill="#0b63c8" stroke="#ffffff" stroke-width="2"/><path d="M8 15 H32" stroke="#ffffff" stroke-width="2.4"/><text x="20" y="33" text-anchor="middle" font-family="Arial" font-size="19" font-weight="800" fill="#ffffff">Д</text></svg>`;
}
function heroRinkSvg() {
  return `<svg viewBox="0 0 560 320" aria-hidden="true">
    <defs>
      <linearGradient id="ice" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#f3faff"/><stop offset="0.5" stop-color="#ffffff"/><stop offset="1" stop-color="#e6f3fc"/>
      </linearGradient>
      <linearGradient id="puck" x1="0" y1="0" x2="1" y2="1">
        <stop offset="0" stop-color="#1b1f28"/><stop offset="1" stop-color="#3a3f4b"/>
      </linearGradient>
    </defs>
    <rect x="30" y="20" width="500" height="280" rx="44" fill="url(#ice)" stroke="#ffffff" stroke-width="4"/>
    <line x1="280" y1="20" x2="280" y2="300" stroke="#d23c46" stroke-width="3"/>
    <line x1="150" y1="20" x2="150" y2="300" stroke="#2f7ed8" stroke-width="3"/>
    <line x1="410" y1="20" x2="410" y2="300" stroke="#2f7ed8" stroke-width="3"/>
    <circle cx="280" cy="160" r="42" fill="none" stroke="#d23c46" stroke-width="3"/>
    <circle cx="150" cy="160" r="30" fill="none" stroke="#d23c46" stroke-width="2.5"/>
    <circle cx="410" cy="160" r="30" fill="none" stroke="#d23c46" stroke-width="2.5"/>
    <circle cx="150" cy="160" r="5" fill="#d23c46"/>
    <circle cx="410" cy="160" r="5" fill="#d23c46"/>
    <rect x="26" y="140" width="14" height="40" rx="5" fill="#d23c46"/>
    <rect x="520" y="140" width="14" height="40" rx="5" fill="#d23c46"/>
    <g>
      <ellipse cx="280" cy="160" rx="30" ry="30" fill="url(#puck)"/>
      <text x="280" y="171" text-anchor="middle" font-family="Arial" font-size="28" font-weight="800" fill="#ffffff">Д</text>
    </g>
  </svg>`;
}
function merchGlyphSvg() {
  return `<svg viewBox="0 0 40 40" aria-hidden="true"><path d="M20 3 L34 8 V21 C34 29 28 35 20 38 C12 35 6 29 6 21 V8 Z" fill="none" stroke="#ffffff" stroke-width="2.4"/><path d="M10 12 H30" stroke="#ffffff" stroke-width="2.2"/><text x="20" y="26" text-anchor="middle" font-family="Arial" font-size="15" font-weight="800" fill="#ffffff">Д</text></svg>`;
}

/* ---------- Общие элементы ---------- */
function pageHeader(kicker, title, description = '') {
  return `<section class="page-hero"><div class="eyebrow">${esc(kicker)}</div><h1>${title}</h1>${description ? `<p>${esc(description)}</p>` : ''}</section>`;
}
function emptyState(text, href = '/matches', linkText = 'Перейти к матчам') {
  return `<div class="empty-state">${esc(text)} <a class="text-link" href="${href}">${esc(linkText)}</a>.</div>`;
}
function table(headers, rows, className = '') {
  return `<div class="table-wrap"><table class="${className}"><thead><tr>${headers.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows || `<tr><td colspan="${headers.length}">Нет записей.</td></tr>`}</tbody></table></div>`;
}
function metricCard(label, value, note = '') {
  return `<article class="stat-card"><span>${esc(label)}</span><strong>${esc(value)}</strong><small>${esc(note)}</small></article>`;
}
function matchCard(m) {
  const home = m.is_home === 'Y';
  return `<a class="match-card" href="/matches/${num(m.match_id)}/seats">
    <div class="match-card-top"><span>${home ? 'Домашний матч' : 'Выездной матч'}</span><span class="status-pill status-${esc(m.match_status)}">${esc(status(m.match_status))}</span></div>
    <div class="match-date">${esc(dateFmt(m.match_date))}</div>
    <div class="match-versus">
      <div class="team-name"><b>ДИНАМО</b><small>МИНСК</small></div>
      <span class="versus-mark">VS</span>
      <div class="team-name opponent"><b>${esc(m.opponent_name)}</b><small>${esc(m.stadium || '')}</small></div>
    </div>
    <div class="match-card-bottom"><span>${num(m.available_tickets).toLocaleString('ru-RU')} мест доступно</span><b>Выбрать место →</b></div>
  </a>`;
}
function playerCard(p, favorite = false) {
  const full = `${p.first_name || ''} ${p.last_name || ''}`.trim();
  return `<article class="player-card">
    <div class="player-number">${p.jersey_number == null ? 'Д' : esc(p.jersey_number)}</div>
    <div class="player-info">
      <div class="eyebrow">${esc(position(p.position))}</div>
      <h3>${esc(full)}</h3>
      <p>${esc(p.country || 'ХК Динамо-Минск')}</p>
      <div class="player-stats">
        <span>Голы <b>${num(p.goals_total)}</b></span>
        <span>Очки <b>${num(p.points_total)}</b></span>
        <span>В избранном <b>${num(p.fans_favorited)}</b></span>
      </div>
    </div>
    ${isUser() ? `<button class="favorite-btn ${favorite ? 'is-favorite' : ''}" data-action="favorite" data-id="${p.player_id}" data-favorite="${favorite}" title="${favorite ? 'Убрать из избранного' : 'В избранное'}">${favorite ? '♥' : '♡'}</button>` : ''}
  </article>`;
}
function merchCard(item) {
  return `<article class="merch-card">
    <div class="merch-visual">${merchGlyphSvg()}<span class="merch-cat">${esc(item.category)}</span></div>
    <div class="merch-info">
      <div class="eyebrow">Клубная атрибутика</div>
      <h3>${esc(item.name)}</h3>
      <p>${esc(item.description || 'Товар с символикой клуба.')}</p>
      <div class="merch-buy"><b>${money(item.price)}</b><span class="status-pill">В каталоге</span></div>
    </div>
  </article>`;
}
function adminNav() {
  const items = [
    ['/admin/players', '01', 'Игроки', 'Состав и параметры'],
    ['/admin/matches', '02', 'Матчи', 'Календарь и результаты'],
    ['/admin/tickets', '03', 'Билеты', 'Места и статусы'],
    ['/admin/merch', '04', 'Атрибутика', 'Каталог товаров'],
    ['/admin/json', '05', 'JSON', 'Импорт и экспорт'],
    ['/admin/olap', '06', 'OLAP', 'Аналитика продаж']
  ];
  return `<nav class="admin-shortcuts">${items.map(([href, n, title, sub]) => `<a href="${href}"><span>${n}</span><div><b>${title}</b><small>${sub}</small></div></a>`).join('')}</nav>`;
}

/* ---------- Каркас ---------- */
function roleBadge(role) {
  const cls = role === 'MAIN_ADMIN' ? 'role-main_admin' : role === 'ADMIN' ? 'role-admin' : 'role-user';
  const label = role === 'MAIN_ADMIN' ? 'Глав. админ' : role === 'ADMIN' ? 'Админ' : 'Болельщик';
  return `<span class="role-badge ${cls}">${label}</span>`;
}
function renderLayout(content, title = 'Динамо-Минск') {
  const u = state.session?.user;
  const path = location.pathname;
  const navLinks = [];
  navLinks.push(['/matches', 'Матчи', path.startsWith('/matches')]);
  navLinks.push(['/players', 'Команда', path === '/players']);
  navLinks.push(['/merch', 'Атрибутика', path === '/merch']);
  if (isUser()) navLinks.push(['/account/tickets', 'Мои билеты', path.startsWith('/account')]);
  if (isAdmin()) navLinks.push(['/admin', 'Администрирование', path.startsWith('/admin')]);
  if (isMainAdmin()) navLinks.push(['/super/users', 'Пользователи', path.startsWith('/super')]);

  const account = u
    ? `<a class="account-chip" href="${isUser() ? '/account/tickets' : '/admin'}">
         <span class="avatar">${esc(u.username.slice(0, 1).toUpperCase())}</span>
         <span class="ac-name"><b>${esc(u.username)}</b><small>${roleBadge(u.role)}</small></span>
       </a>
       <button class="btn btn-ghost btn-small" data-action="logout">Выйти</button>`
    : `<a class="btn btn-ghost btn-small" href="/login">Войти</a><a class="btn btn-primary btn-small" href="/register">Регистрация</a>`;

  appRoot.innerHTML = `
    <header class="topbar">
      <a class="brand" href="/" aria-label="На главную">
        ${crestSvg()}
        <span class="brand-text"><b>ДИНАМО</b><span>МИНСК · HOCKEY CLUB</span></span>
      </a>
      <nav class="main-nav">${navLinks.map(([href, label, active]) => `<a href="${href}" class="${active ? 'active' : ''}">${label}</a>`).join('')}</nav>
      <div class="nav-account">${account}</div>
    </header>
    <main class="site-main">
      ${state.notice ? `<div class="flash flash-${state.notice.type || 'success'}" role="status"><span>${esc(state.notice.message)}</span><button class="flash-close" data-action="close-notice">×</button></div>` : ''}
      ${content}
    </main>
    <footer class="footer">
      <div class="footer-inner">
        <div class="footer-brand">
          <div class="brand">${crestSvg()}<span class="brand-text"><b>ДИНАМО</b><span>МИНСК · HOCKEY CLUB</span></span></div>
          <p>Учебная информационная система хоккейного клуба «Динамо-Минск». Каталог, билеты, атрибутика и аналитика на базе Oracle Database 19c.</p>
        </div>
        <div class="footer-col"><h4>Навигация</h4><a href="/matches">Матчи</a><a href="/players">Команда</a><a href="/merch">Атрибутика</a><a href="/guide">О приложении</a></div>
        <div class="footer-col"><h4>Информация</h4><span>Oracle Database 19c</span><span>Демонстрационный режим</span><span>Платёжная система не подключена</span></div>
      </div>
      <div class="footer-bottom"><span>© 2026 ХК «Динамо-Минск» · Курсовой проект «Базы данных»</span><span>БГТУ · ФИТ · Программная инженерия</span></div>
    </footer>`;
  document.title = `${title} — Динамо-Минск`;
}
function toast(message, type = 'success') {
  state.notice = { message, type };
  const old = document.querySelector('.flash');
  if (old) old.remove();
  const node = document.createElement('div');
  node.className = `flash flash-${type}`;
  node.innerHTML = `<span>${esc(message)}</span><button class="flash-close" data-action="close-notice">×</button>`;
  document.querySelector('.site-main')?.prepend(node);
  setTimeout(() => { node.remove(); state.notice = null; }, 5000);
}
function field(label, name, type = 'text', value = '', extra = '') {
  return `<label>${esc(label)}<input type="${type}" name="${name}" value="${esc(value)}" ${extra}></label>`;
}
function selectField(label, name, options, value = '', extra = '') {
  return `<label>${esc(label)}<select name="${name}" ${extra}>${options.map((o) => `<option value="${esc(o.value)}" ${String(o.value) === String(value) ? 'selected' : ''}>${esc(o.label)}</option>`).join('')}</select></label>`;
}
function noDataBlock() { return `<div class="empty-state">Данные пока отсутствуют.</div>`; }

/* ---------- Страницы ---------- */
async function pageHome() {
  const data = await get('/api/home');
  const m = data.metrics || {};
  const content = `
    <section class="hero">
      <div class="hero-copy">
        <div class="eyebrow">Хоккейный клуб · Минск</div>
        <h1>Сила. Характер.<br><em>Динамо.</em></h1>
        <p>Единая информационная система клуба: состав, календарь матчей, продажа билетов, клубная атрибутика и аналитика на платформе Oracle Database 19c.</p>
        <div class="hero-actions"><a class="btn btn-primary" href="/matches">Выбрать матч</a><a class="btn btn-outline" href="/players">Состав команды</a></div>
        <div class="hero-footnote">Официальная демонстрационная среда курсового проекта</div>
      </div>
      <div class="hero-art">${heroRinkSvg()}</div>
    </section>
    <section class="stat-grid">
      ${metricCard('Активные игроки', m.players_count ?? 0, 'Состав команды')}
      ${metricCard('Будущие матчи', m.upcoming_matches ?? 0, 'Календарь клуба')}
      ${metricCard('Продано билетов', m.sold_tickets ?? 0, 'Все матчи')}
      ${metricCard('Выручка с билетов', money(m.ticket_revenue), 'BYN · учёт Oracle')}
    </section>
    <section class="section-block">
      <div class="section-heading"><div><div class="eyebrow">Ближайшие события</div><h2>Календарь <em>матчей</em></h2></div><a href="/matches" class="text-link">Все матчи →</a></div>
      <div class="match-grid">${data.matches.length ? data.matches.map(matchCard).join('') : emptyState('Матчи не найдены.')}</div>
    </section>
    <section class="section-block">
      <div class="section-heading"><div><div class="eyebrow">Состав команды</div><h2>Наши <em>игроки</em></h2></div><a href="/players" class="text-link">Весь состав →</a></div>
      <div class="player-grid">${data.players.map((p) => playerCard(p, false)).join('') || noDataBlock()}</div>
    </section>`;
  renderLayout(content, 'Главная');
}

async function pageMatches() {
  const params = new URLSearchParams(location.search);
  const data = await get(`/api/matches${location.search}`);
  const content = `
    ${pageHeader('Календарь клуба', 'Матчи <em>Динамо</em>', 'Выберите матч, чтобы открыть схему арены и выбрать место.')}
    <form class="filter-bar" method="get">
      <label>Дата с<input type="date" name="from" value="${esc(params.get('from') || '')}"></label>
      <label>Дата по<input type="date" name="to" value="${esc(params.get('to') || '')}"></label>
      <button class="btn btn-outline">Фильтровать</button>
      <a class="text-link" href="/matches">Сбросить</a>
    </form>
    <div class="match-grid match-grid-wide">${data.matches.length ? data.matches.map(matchCard).join('') : emptyState('По выбранному периоду матчей нет.')}</div>`;
  renderLayout(content, 'Матчи');
}

/* ---------- 2D-карта арены ---------- */
function groupSeatsBySector(seats) {
  const bySector = new Map();
  for (const s of seats) {
    const id = num(s.sector_id);
    if (!bySector.has(id)) bySector.set(id, []);
    bySector.get(id).push(s);
  }
  return bySector;
}
function sectorRows(seats) {
  const byRow = new Map();
  for (const s of seats) {
    const r = num(s.seat_row);
    if (!byRow.has(r)) byRow.set(r, []);
    byRow.get(r).push(s);
  }
  return [...byRow.entries()]
    .map(([row, list]) => ({ row, seats: list.sort((a, b) => num(a.seat_number) - num(b.seat_number)) }))
    .sort((a, b) => a.row - b.row);
}
function isSeatFree(seat) { return seat.status === 'FREE' || seat.status === 'RETURNED'; }
function seatClass(seat, selected) {
  if (isSeatFree(seat)) return selected ? 'seat-free seat-selected' : 'seat-free';
  return `seat-${String(seat.status).toLowerCase()}`;
}
function renderSeatRow(rowSeats, selected, sectorCode) {
  const cells = [];
  const total = rowSeats.length;
  rowSeats.forEach((s, i) => {
    const free = isSeatFree(s);
    const sel = selected && num(selected.ticket_id) === num(s.ticket_id);
    const title = `${sectorCode} · ряд ${s.seat_row} · место ${s.seat_number} · ${money(s.price)} · ${free ? 'Свободно' : status(s.status)}`;
    const attrs = free
      ? `data-seat-id="${s.ticket_id}" data-sector-code="${esc(sectorCode)}" data-seat-row="${s.seat_row}" data-seat-number="${s.seat_number}" data-price="${s.price}"`
      : 'disabled';
    cells.push(`<button class="seat ${seatClass(s, sel)}" ${attrs} title="${esc(title)}" aria-label="${esc(title)}"></button>`);
    if ((i + 1) % 25 === 0 && i + 1 < total) cells.push('<span class="seat-aisle"></span>');
  });
  return cells.join('');
}
function renderStand(sector, seats, selected, reverseRows = false) {
  const rows = sectorRows(seats);
  if (reverseRows) rows.reverse();
  const freeCount = seats.filter(isSeatFree).length;
  const prices = seats.map((s) => num(s.price));
  const minPrice = prices.length ? Math.min(...prices) : 0;
  const maxPrice = prices.length ? Math.max(...prices) : 0;
  const priceRange = minPrice === maxPrice ? money(minPrice) : `${money(minPrice)} – ${money(maxPrice)}`;
  const rowsHtml = rows.map((r) =>
    `<div class="seat-row"><span class="row-label">${r.row}</span><div class="seat-run">${renderSeatRow(r.seats, selected, sector.sector_code)}</div><span class="row-label">${r.row}</span></div>`
  ).join('');
  return `
    <div class="stand" data-sector="${sector.sector_id}">
      <div class="stand-header">
        <span class="stand-code">${esc(sector.sector_code)}</span>
        <span class="stand-title">Сектор ${esc(sector.sector_code)} · ${esc(categoryLabel(sector.category))}</span>
        <span class="stand-meta"><span>${freeCount.toLocaleString('ru-RU')} свободно</span><span>${priceRange}</span><span>${rows.length} рядов</span></span>
      </div>
      <div class="stand-body">${rowsHtml}</div>
      <div class="stand-note">Ряд 1 — ближе к льду</div>
    </div>`;
}
function renderIceRink() {
  return `<div class="ice-rink" aria-hidden="true">
    <span class="rink-line center-line"></span>
    <span class="rink-line blue-line left"></span>
    <span class="rink-line blue-line right"></span>
    <span class="center-circle"></span><span class="center-dot"></span>
    <span class="faceoff left"></span><span class="faceoff right"></span>
    <span class="goal left"></span><span class="goal right"></span>
    <span class="rink-label">Динамо</span>
  </div>`;
}
function summaryReserveArea(selected) {
  if (!selected) return `<button class="btn btn-primary btn-block" disabled>Выберите место</button><p class="small-note">Кликните по свободному месту на схеме, чтобы выбрать его.</p>`;
  if (!state.session?.user) {
    return `<a class="btn btn-primary btn-block" href="/login">Войти и зарезервировать</a><p class="small-note">Для покупки билета войдите как болельщик (роль USER).</p>`;
  }
  if (!isUser()) {
    return `<button class="btn btn-primary btn-block" disabled>Недоступно для роли администратора</button><p class="small-note">Учётная запись администратора предназначена для управления данными, а не для покупки билетов.</p>`;
  }
  return `<button class="btn btn-accent btn-block" id="reserve-selected">Зарезервировать на 15 минут</button><p class="small-note">Резерв временно удерживает место. Покупка в учебном проекте демонстрационная.</p>`;
}
function seatSummaryPanel(m, sectors, selected) {
  const sector = selected ? sectors.find((s) => num(s.sector_id) === num(selected.sector_id)) : null;
  return `
    <aside class="seat-summary">
      <div class="eyebrow">Ваш билет</div>
      <h2>${esc(m.opponent_name)}</h2>
      <div class="summary-row"><span>Дата</span><b>${esc(dateFmt(m.match_date))}</b></div>
      <div class="summary-row"><span>Арена</span><b>${esc(m.stadium)}</b></div>
      <div class="summary-row"><span>Сектор</span><b id="seat-sector">${selected ? esc(sector?.sector_code || selected.sector_code) : '—'}</b></div>
      <div class="summary-row"><span>Ряд / место</span><b id="seat-label">${selected ? `${selected.seat_row} / ${selected.seat_number}` : 'Не выбрано'}</b></div>
      <div class="summary-total"><span>Стоимость</span><b id="seat-price">${selected ? money(selected.price) : '—'}</b></div>
      <div id="reserve-slot">${summaryReserveArea(selected)}</div>
    </aside>`;
}
async function pageArena(matchId) {
  state.selectedSeat = null;
  const data = await get(`/api/matches/${matchId}/arena`);
  const m = data.match;
  const sectors = data.sectors;
  const bySector = groupSeatsBySector(data.seats);

  const ordered = [...sectors].sort((a, b) => String(a.sector_code).localeCompare(String(b.sector_code)));
  let stage;
  if (ordered.length === 2) {
    stage = `${renderStand(ordered[0], bySector.get(num(ordered[0].sector_id)) || [], null, true)}${renderIceRink()}${renderStand(ordered[1], bySector.get(num(ordered[1].sector_id)) || [], null)}`;
  } else {
    stage = `${renderIceRink()}${ordered.map((s) => renderStand(s, bySector.get(num(s.sector_id)) || [], null)).join('')}`;
  }

  const content = `
    ${pageHeader('Билеты · Схема арены', 'Выбор <em>места</em>', `${m.opponent_name} · ${dateFmt(m.match_date)} · ${m.stadium}`)}
    <div class="arena-layout">
      <section class="arena-panel">
        <div class="arena-toolbar">
          <h3>${esc(m.stadium)}</h3>
          <div class="arena-legend">
            <span class="legend-item"><i class="legend-dot free"></i>Свободно</span>
            <span class="legend-item"><i class="legend-dot reserved"></i>Резерв</span>
            <span class="legend-item"><i class="legend-dot sold"></i>Продано</span>
            <span class="legend-item"><i class="legend-dot selected"></i>Выбрано</span>
          </div>
        </div>
        <div class="arena-viewport"><div class="arena-stage">${stage}</div></div>
      </section>
      ${seatSummaryPanel(m, sectors, null)}
    </div>`;
  renderLayout(content, 'Выбор места');
}

async function pagePlayers() {
  const data = await get('/api/players');
  const ids = new Set(data.favoriteIds || []);
  const content = `
    ${pageHeader('Команда', 'Состав <em>Динамо</em>', 'Карточки игроков и статистика, рассчитанная по данным Oracle.')}
    <div class="player-grid">${data.players.length ? data.players.map((p) => playerCard(p, ids.has(num(p.player_id)))).join('') : noDataBlock()}</div>`;
  renderLayout(content, 'Состав команды');
}

async function pageMerch() {
  const data = await get('/api/merch');
  const content = `
    ${pageHeader('Магазин клуба', 'Клубная <em>атрибутика</em>', 'Демонстрационный каталог товаров Динамо-Минск.')}
    <div class="merch-grid">${data.items.length ? data.items.map(merchCard).join('') : noDataBlock()}</div>`;
  renderLayout(content, 'Атрибутика');
}

async function pageAuth(mode) {
  const isSetup = mode === 'setup';
  if (isSetup && !state.session.setupRequired) return pageLogin();
  const title = isSetup ? 'Первичная настройка <em>администратора</em>' : mode === 'register' ? 'Создать <em>аккаунт</em>' : 'С возвращением, <em>болельщик</em>';
  let fields = '';
  if (isSetup) fields += field('Ключ первичной настройки', 'setupToken', 'password', '', 'required autocomplete="off"');
  if (mode !== 'login') fields += `<div class="form-row">${field('Имя', 'firstName', 'text', '', 'required')}${field('Фамилия', 'lastName', 'text', '', 'required')}</div>`;
  fields += field('Логин', 'username', 'text', '', 'required autocomplete="username"');
  if (mode !== 'login') fields += field('Электронная почта', 'email', 'email', '', 'required autocomplete="email"');
  fields += field('Пароль', 'password', 'password', '', `required minlength="${isSetup ? 10 : mode === 'register' ? 8 : 1}" autocomplete="${mode === 'login' ? 'current-password' : 'new-password'}"`);
  if (mode !== 'login') fields += field('Повтори пароль', 'confirmPassword', 'password', '', 'required minlength="8" autocomplete="new-password"') + field('Город', 'city', 'text', 'Минск');
  const endpoint = isSetup ? '/api/setup' : mode === 'register' ? '/api/register' : '/api/login';
  const submitLabel = isSetup ? 'Создать MAIN_ADMIN' : mode === 'register' ? 'Зарегистрироваться' : 'Войти';
  const content = `
    <div class="auth-wrap">
      <section class="auth-decoration">
        <div class="eyebrow">ХК Динамо · Минск</div>
        <h1>Свои среди <em>своих</em></h1>
        <p>Единая цифровая среда клуба и его болельщиков.</p>
      </section>
      <section class="auth-card">
        <div class="eyebrow">${isSetup ? 'Первый запуск' : mode === 'register' ? 'Новая учётная запись' : 'Личный кабинет'}</div>
        <h2>${title}</h2>
        <form class="form-stack" data-form data-endpoint="${endpoint}" data-method="POST">${fields}<button class="btn btn-primary btn-block">${submitLabel}</button></form>
        <div class="auth-switch">${mode === 'login' ? 'Нет аккаунта? <a href="/register">Зарегистрироваться</a>' : mode === 'register' ? 'Уже зарегистрированы? <a href="/login">Войти</a>' : 'После создания администратора откроется панель управления.'}</div>
      </section>
    </div>`;
  renderLayout(content, isSetup ? 'Первичная настройка' : mode === 'register' ? 'Регистрация' : 'Вход');
}
const pageLogin = () => pageAuth('login');

async function pageTickets() {
  const data = await get('/api/account/tickets');
  const rows = data.tickets.map((t) => `
    <article class="ticket-row">
      <div class="ticket-side"><span>Билет</span><b>#${t.ticket_id}</b></div>
      <div class="ticket-main">
        <div class="eyebrow">${esc(dateFmt(t.match_date))}</div>
        <h3>${esc(t.opponent_name)}</h3>
        <p>Сектор ${esc(t.sector_code)} · ряд ${t.seat_row} · место ${t.seat_number}${t.reserved_until ? ` · резерв до ${esc(dateFmt(t.reserved_until, true))}` : ''}</p>
        <span class="ticket-price">${money(t.price)}</span>
        <span class="status-pill status-${String(t.status).toLowerCase()}">${esc(status(t.status))}</span>
      </div>
      <div class="ticket-actions">
        ${t.status === 'RESERVED' ? `<button class="btn btn-primary btn-small" data-action="ticket" data-id="${t.ticket_id}" data-kind="purchase">Подтвердить покупку</button><button class="btn btn-outline btn-small" data-action="ticket" data-id="${t.ticket_id}" data-kind="cancel">Отменить резерв</button>` : ''}
      </div>
    </article>`).join('');
  renderLayout(`${pageHeader('Личный кабинет', 'Мои <em>билеты</em>', 'Информация поступает из таблицы TICKETS.')}<div class="ticket-list">${rows || emptyState('У вас пока нет билетов.', '/matches', 'Выбрать матч')}</div>`, 'Мои билеты');
}

async function pageFavorites() {
  const data = await get('/api/account/favorites');
  const rows = data.players.map((p) => `
    <div class="simple-list-row">
      <div class="player-mini"><b>${esc(p.first_name)} ${esc(p.last_name)}</b><small>${esc(position(p.position))}</small></div>
      <button class="btn btn-ghost btn-small" data-action="favorite" data-id="${p.player_id}" data-favorite="true">Убрать из избранного</button>
    </div>`).join('');
  renderLayout(`${pageHeader('Личный кабинет', 'Избранные <em>игроки</em>', 'Список хранится в FAN_PLAYER_FAVORITES.')}${rows ? `<div class="simple-list">${rows}</div>` : emptyState('Пока никого нет в избранном.', '/players', 'Перейти к составу')}`, 'Избранное');
}

async function pageAdminDashboard() {
  const data = await get('/api/admin/dashboard'); const s = data.stats;
  const content = `
    ${pageHeader('Администраторский раздел', 'Панель <em>управления</em>', 'Все изменения проходят через процедуры и пакет PL/SQL Oracle.')}
    <section class="stat-grid">${metricCard('Игроки', s.players_count ?? 0, 'Активный состав')}${metricCard('Будущие матчи', s.upcoming_matches ?? 0, 'Не тестовые')}${metricCard('Продано билетов', s.sold_tickets ?? 0, 'Учитываются в OLAP')}${metricCard('Выручка', money(s.ticket_revenue), 'Oracle Database 19c')}</section>
    ${adminNav()}
    <section class="section-block">
      <div class="section-heading"><div><div class="eyebrow">Календарь</div><h2>Ближайшие матчи</h2></div></div>
      ${table(['Матч', 'Дата', 'Арена', 'Статус'], data.matches.map((m) => `<tr><td><b>${esc(m.opponent_name)}</b></td><td>${esc(dateFmt(m.match_date))}</td><td>${esc(m.stadium || '—')}</td><td>${esc(status(m.match_status))}</td></tr>`).join(''))}
    </section>`;
  renderLayout(content, 'Панель администратора');
}

async function pageAdminPlayers() {
  const data = await get('/api/admin/players'); const list = data.players;
  const id = location.pathname.match(/\/admin\/players\/(\d+)\/edit/); const edit = id ? list.find((p) => num(p.player_id) === num(id[1])) : null;
  const form = `<div class="admin-form-card">
    <div class="eyebrow">${edit ? 'Редактирование' : 'Новая запись'}</div>
    <h2>${edit ? 'Изменить игрока' : 'Добавить игрока'}</h2>
    <form class="form-stack" data-form data-endpoint="${edit ? `/api/admin/players/${edit.player_id}` : '/api/admin/players'}" data-method="${edit ? 'PUT' : 'POST'}">
      <div class="form-row">${field('Имя', 'first_name', 'text', edit?.first_name || '', 'required')}${field('Фамилия', 'last_name', 'text', edit?.last_name || '', 'required')}</div>
      ${selectField('Позиция', 'position', [{ value: 'FORWARD', label: 'Нападающий' }, { value: 'DEFENDER', label: 'Защитник' }, { value: 'GOALTENDER', label: 'Вратарь' }], edit?.position || 'FORWARD')}
      <div class="form-row">${field('Номер', 'jersey_number', 'number', edit?.jersey_number ?? '', 'min="0" max="99"')}${field('Дата рождения', 'birth_date', 'date', dateShort(edit?.birth_date))}</div>
      <div class="form-row three">${field('Страна', 'country', 'text', edit?.country || '')}${field('Рост, см', 'height_cm', 'number', edit?.height_cm ?? '')}${field('Вес, кг', 'weight_kg', 'number', edit?.weight_kg ?? '')}</div>
      ${edit ? selectField('Активность', 'is_active', [{ value: 'Y', label: 'Активен' }, { value: 'N', label: 'Неактивен' }], edit.is_active) : ''}
      <div class="form-row"><button class="btn btn-primary">${edit ? 'Сохранить' : 'Добавить'}</button>${edit ? '<a class="btn btn-outline" href="/admin/players">Отмена</a>' : ''}</div>
    </form>
  </div>`;
  const rows = list.map((p) => `<tr><td><b>${esc(p.first_name)} ${esc(p.last_name)}</b><span class="table-sub">${esc(p.country || '—')}</span></td><td>${esc(position(p.position))}</td><td>${esc(p.jersey_number ?? '—')}</td><td>${esc(status(p.is_active))}</td><td><a class="text-link" href="/admin/players/${p.player_id}/edit">Изменить</a> <button class="link-danger" data-action="api" data-endpoint="/api/admin/players/${p.player_id}" data-method="DELETE" data-confirm="Удалить игрока? При наличии связанных данных Oracle может запретить удаление.">Удалить</button></td></tr>`).join('');
  renderLayout(`${pageHeader('Администрирование · DIM_PLAYER', 'Управление <em>игроками</em>', 'Добавление, изменение и удаление сведений о составе.')}<div class="admin-columns">${form}<section><div class="section-heading"><h2>Состав команды</h2><span class="count-chip">${list.length} записей</span></div>${table(['Игрок', 'Позиция', '№', 'Статус', 'Операции'], rows)}</section></div>`, 'Управление игроками');
}

async function pageAdminMatches() {
  const data = await get('/api/admin/matches'); const list = data.matches;
  const id = location.pathname.match(/\/admin\/matches\/(\d+)\/edit/); const edit = id ? list.find((m) => num(m.match_id) === num(id[1])) : null;
  const stadiumOpts = data.stadiums.map((s) => ({ value: s.stadium_id, label: `${s.name} · ${s.city}` }));
  const form = `<div class="admin-form-card">
    <div class="eyebrow">${edit ? 'Редактирование' : 'Календарь'}</div>
    <h2>${edit ? 'Изменить матч' : 'Добавить матч'}</h2>
    <form class="form-stack" data-form data-endpoint="${edit ? `/api/admin/matches/${edit.match_id}` : '/api/admin/matches'}" data-method="${edit ? 'PUT' : 'POST'}">
      ${field('Дата матча', 'match_date', 'date', dateShort(edit?.match_date), 'required')}
      ${field('Соперник', 'opponent_name', 'text', edit?.opponent_name || '', 'required')}
      ${selectField('Арена', 'stadium_id', stadiumOpts, edit?.stadium_id || data.stadiums[0]?.stadium_id)}
      ${selectField('Матч', 'is_home', [{ value: 'Y', label: 'Домашний' }, { value: 'N', label: 'Выездной' }], edit?.is_home || 'Y')}
      ${edit ? selectField('Статус', 'match_status', [{ value: 'SCHEDULED', label: 'Запланирован' }, { value: 'COMPLETED', label: 'Завершён' }, { value: 'CANCELLED', label: 'Отменён' }], edit.match_status) + `<div class="form-row">${field('Голы Динамо', 'goals_for', 'number', edit.goals_for ?? '')}${field('Голы соперника', 'goals_against', 'number', edit.goals_against ?? '')}</div>` : ''}
      <div class="form-row"><button class="btn btn-primary">${edit ? 'Сохранить' : 'Добавить матч'}</button>${edit ? '<a class="btn btn-outline" href="/admin/matches">Отмена</a>' : ''}</div>
    </form>
  </div>`;
  const rows = list.map((m) => `<tr><td><b>${esc(m.opponent_name)}</b><span class="table-sub">#${m.match_id}</span></td><td>${esc(dateFmt(m.match_date))}</td><td>${esc(m.stadium || '—')}</td><td>${esc(status(m.match_status))}</td><td>${m.goals_for == null ? '—' : `${m.goals_for}:${m.goals_against}`}</td><td><a class="text-link" href="/admin/matches/${m.match_id}/edit">Изменить</a> <button class="link-danger" data-action="api" data-endpoint="/api/admin/matches/${m.match_id}" data-method="DELETE" data-confirm="Удалить матч?">Удалить</button></td></tr>`).join('');
  renderLayout(`${pageHeader('Администрирование · DIM_MATCH', 'Управление <em>матчами</em>', 'Календарь матчей, статус и результаты.')}<div class="admin-columns">${form}<section><div class="section-heading"><h2>Календарь</h2><span class="count-chip">${list.length} матчей</span></div>${table(['Соперник', 'Дата', 'Арена', 'Статус', 'Счёт', 'Операции'], rows)}</section></div>`, 'Управление матчами');
}

async function pageAdminTickets() {
  const qs = new URLSearchParams(location.search); const data = await get(`/api/admin/tickets${location.search}`);
  const matches = data.matches.map((m) => ({ value: m.match_id, label: `#${m.match_id} · ${dateShort(m.match_date)} · ${m.opponent_name}` }));
  const sectors = data.sectors.map((s) => ({ value: s.sector_id, label: `${s.sector_code} · ${categoryLabel(s.category)}` }));
  const fans = data.fans.map((f) => ({ value: f.fan_id, label: `${f.first_name} ${f.last_name}` }));
  const createForm = `<div class="admin-form-card wide-card">
    <div class="section-heading"><div><div class="eyebrow">Создание билета</div><h2>Добавить место</h2></div><button class="btn btn-outline btn-small" data-action="api" data-endpoint="/api/admin/tickets/release-expired" data-method="POST">Освободить просроченные резервы</button></div>
    <form class="inline-create-form" data-form data-endpoint="/api/admin/tickets" data-method="POST">
      ${selectField('Матч', 'match_id', matches, matches[0]?.value, 'required')}
      ${selectField('Сектор', 'sector_id', sectors, sectors[0]?.value, 'required')}
      ${field('Ряд', 'seat_row', 'number', '', 'min="1" required')}
      ${field('Место', 'seat_number', 'number', '', 'min="1" required')}
      ${field('Цена, BYN', 'price', 'number', '45', 'min="0" step="0.01" required')}
      <button class="btn btn-primary">Создать</button>
    </form>
  </div>`;
  const rows = data.tickets.map((t) => `<tr><td>#${t.ticket_id}</td><td><b>${esc(t.opponent_name)}</b><span class="table-sub">${esc(dateFmt(t.match_date))}</span></td><td>${esc(t.sector_code)} · ${t.seat_row}/${t.seat_number}</td><td>${money(t.price)}</td><td><span class="status-pill status-${String(t.status).toLowerCase()}">${esc(status(t.status))}</span></td><td>${t.status === 'SOLD' ? `<button class="link-danger" data-action="api" data-endpoint="/api/admin/tickets/${t.ticket_id}/return" data-method="POST" data-confirm="Оформить возврат?">Возврат</button>` : ['FREE', 'RETURNED'].includes(t.status) ? `<details><summary class="link-action">Изменить</summary><form class="form-stack mini-form" data-form data-endpoint="/api/admin/tickets/${t.ticket_id}" data-method="PUT">${field('Ряд', 'seat_row', 'number', t.seat_row, 'required')}${field('Место', 'seat_number', 'number', t.seat_number, 'required')}${field('Цена', 'price', 'number', t.price, 'step="0.01" required')}<button class="btn btn-outline btn-small">Сохранить</button></form></details> <form class="inline-action" data-form data-endpoint="/api/admin/tickets/${t.ticket_id}/sell" data-method="POST">${selectField('Покупатель', 'fan_id', fans, fans[0]?.value)}<button class="btn btn-outline btn-small">Продать</button></form> <button class="link-danger" data-action="api" data-endpoint="/api/admin/tickets/${t.ticket_id}" data-method="DELETE" data-confirm="Удалить свободный билет?">Удалить</button>` : `До ${esc(dateFmt(t.reserved_until, true))}`}</td></tr>`).join('');
  const filters = `<form method="get" class="filter-bar compact-filter">${selectField('Матч', 'match_id', [{ value: '', label: 'Все матчи' }, ...matches], qs.get('match_id') || '')}${selectField('Статус', 'status', [{ value: '', label: 'Все статусы' }, ...['FREE', 'RESERVED', 'SOLD', 'RETURNED'].map((s) => ({ value: s, label: status(s) }))], qs.get('status') || '')}<button class="btn btn-outline">Фильтр</button></form>`;
  renderLayout(`${pageHeader('Администрирование · TICKETS', 'Билеты и <em>места</em>', 'Управление билетными записями и статусами.')}${createForm}<section class="section-block"><div class="section-heading"><h2>Список билетов</h2><span class="count-chip">50 записей на странице</span></div>${filters}${table(['ID', 'Матч', 'Место', 'Цена', 'Статус', 'Операции'], rows)}</section>`, 'Управление билетами');
}

async function pageAdminMerch() {
  const data = await get('/api/admin/merch'); const list = data.items;
  const id = location.pathname.match(/\/admin\/merch\/(\d+)\/edit/); const edit = id ? list.find((i) => num(i.merch_id) === num(id[1])) : null;
  const form = `<div class="admin-form-card">
    <div class="eyebrow">${edit ? 'Редактирование' : 'Каталог'}</div>
    <h2>${edit ? 'Изменить товар' : 'Добавить товар'}</h2>
    <form class="form-stack" data-form data-endpoint="${edit ? `/api/admin/merch/${edit.merch_id}` : '/api/admin/merch'}" data-method="${edit ? 'PUT' : 'POST'}">
      ${field('Название', 'name', 'text', edit?.name || '', 'required')}
      ${field('Категория', 'category', 'text', edit?.category || '', 'required')}
      ${field('Цена, BYN', 'price', 'number', edit?.price ?? '', 'min="0" step="0.01" required')}
      <label>Описание<textarea name="description" rows="3">${esc(edit?.description || '')}</textarea></label>
      ${edit ? selectField('Активность', 'is_active', [{ value: 'Y', label: 'Активен' }, { value: 'N', label: 'Неактивен' }], edit.is_active) : ''}
      <button class="btn btn-primary">${edit ? 'Сохранить' : 'Добавить'}</button>${edit ? '<a class="btn btn-outline" href="/admin/merch">Отмена</a>' : ''}
    </form>
  </div>`;
  const rows = list.map((m) => `<tr><td><b>${esc(m.name)}</b><span class="table-sub">${esc(m.description || '')}</span></td><td>${esc(m.category)}</td><td>${money(m.price)}</td><td>${esc(status(m.is_active))}</td><td><a class="text-link" href="/admin/merch/${m.merch_id}/edit">Изменить</a> <button class="link-danger" data-action="api" data-endpoint="/api/admin/merch/${m.merch_id}" data-method="DELETE" data-confirm="Удалить товар?">Удалить</button></td></tr>`).join('');
  renderLayout(`${pageHeader('Администрирование · DIM_MERCH', 'Управление <em>атрибутикой</em>', 'Добавление, изменение и удаление товаров каталога.')}<div class="admin-columns">${form}<section><div class="section-heading"><h2>Каталог</h2><span class="count-chip">${list.length} товаров</span></div>${table(['Товар', 'Категория', 'Цена', 'Статус', 'Операции'], rows)}</section></div>`, 'Управление атрибутикой');
}

async function pageAdminJson() {
  renderLayout(`${pageHeader('Администрирование · SQL/JSON', 'Импорт и экспорт <em>JSON</em>', 'Импорт игроков в Oracle через JSON_TABLE и экспорт результата в JSON.')}<div class="json-columns">
    <section class="admin-form-card"><div class="eyebrow">Импорт</div><h2>Загрузить игроков</h2><form class="form-stack" data-form data-endpoint="/api/admin/json/import" data-method="POST" data-multipart><label class="file-drop"><span class="file-icon">⇧</span><b>Выберите JSON-файл</b><small>Формат: объект с массивом players · до 2 МБ</small><input type="file" name="jsonFile" accept="application/json,.json" required></label><button class="btn btn-primary">Импортировать</button></form></section>
    <section class="admin-form-card"><div class="eyebrow">Экспорт</div><h2>Выгрузить игроков</h2><p class="muted">Серверный PL/SQL-пакет формирует JSON-документ из записей DIM_PLAYER.</p><div class="export-preview"><span><span class="json-brace">{</span> "players": [ … ] <span class="json-brace">}</span></span><br><small>UTF-8 · application/json</small></div><a class="btn btn-outline" href="/api/admin/json/export">Скачать JSON</a></section>
  </div>`, 'Импорт и экспорт JSON');
}

async function pageAdminOlap() {
  const params = new URLSearchParams(location.search); const data = await get(`/api/admin/olap${location.search}`); const s = data.summary;
  const salesRows = data.sales.map((r) => `<tr class="${String(r.period_label).includes('ВСЕГО') ? 'total-row' : ''}"><td>${esc(r.period_label)}</td><td>${num(r.tickets_sold).toLocaleString('ru-RU')}</td><td>${money(r.revenue)}</td><td>${r.grouping_level}</td></tr>`).join('');
  const cubeRows = data.cube.map((r) => `<tr><td>${esc(r.season)}</td><td>${esc(r.sector_category)}</td><td>${num(r.tickets_sold).toLocaleString('ru-RU')}</td><td>${money(r.revenue)}</td><td>${r.grouping_level}</td></tr>`).join('');
  const playerRows = data.players.map((p) => `<tr><td><b>${esc(p.first_name)} ${esc(p.last_name)}</b></td><td>${esc(position(p.position))}</td><td>${p.fans_count}</td><td>${p.matches_count}</td><td>${p.goals_total}</td><td>${p.assists_total}</td><td>${p.points_total}</td></tr>`).join('');
  const content = `
    ${pageHeader('Аналитическая подсистема', 'OLAP-<em>аналитика</em>', 'Агрегирование фактов по периодам и измерениям в Oracle Database 19c.')}
    <form class="filter-bar" method="get">${field('Дата с', 'from', 'date', params.get('from') || '')}${field('Дата по', 'to', 'date', params.get('to') || '')}<button class="btn btn-outline">Применить период</button><a class="text-link" href="/admin/olap">Сбросить</a></form>
    <section class="stat-grid">${metricCard('Продано билетов', s.sold, 'Количество')}${metricCard('Выручка билетов', money(s.revenue), 'BYN')}${metricCard('Выручка атрибутики', money(s.merchRevenue), 'BYN')}</section>
    <section class="section-block"><div class="section-heading"><div><div class="eyebrow">ROLLUP</div><h2>Продажи по <em>периодам</em></h2></div><span class="tech-pill">GROUP BY ROLLUP</span></div>${table(['Период', 'Продано', 'Выручка', 'Уровень'], salesRows)}</section>
    <section class="section-block"><div class="section-heading"><div><div class="eyebrow">CUBE</div><h2>Продажи по измерениям</h2></div><span class="tech-pill">GROUP BY CUBE</span></div>${table(['Сезон', 'Категория сектора', 'Продано', 'Выручка', 'Уровень'], cubeRows)}</section>
    <section class="section-block"><div class="section-heading"><div><div class="eyebrow">Ранжирование и агрегация</div><h2>Популярность и <em>результативность</em></h2></div></div>${table(['Игрок', 'Позиция', 'Избранное', 'Матчи', 'Голы', 'Передачи', 'Очки'], playerRows)}</section>`;
  renderLayout(content, 'OLAP-аналитика');
}

async function pageSuperUsers() {
  const data = await get('/api/super/users');
  const rows = data.users.map((u) => `<tr><td><b>${esc(u.username)}</b><span class="table-sub">ID: ${u.user_id}</span></td><td>${esc(u.email)}</td><td><form class="inline-action" data-form data-endpoint="/api/super/users/${u.user_id}/role" data-method="PUT">${selectField('Роль', 'role', ['USER', 'ADMIN', 'MAIN_ADMIN'].map((r) => ({ value: r, label: r })), u.role)}<button class="btn btn-outline btn-small">Сохранить</button></form></td><td>${esc(status(u.is_active))}</td><td>${esc(dateFmt(u.created_at))}</td><td><button class="${u.is_active === 'Y' ? 'link-danger' : 'link-action'}" data-action="user-active" data-id="${u.user_id}" data-active="${u.is_active}" ${num(u.user_id) === num(state.session.user.id) ? 'disabled' : ''}>${u.is_active === 'Y' ? 'Отключить' : 'Включить'}</button></td></tr>`).join('');
  renderLayout(`${pageHeader('MAIN_ADMIN · Безопасность', 'Пользователи и <em>роли</em>', 'Управление прикладными учётными записями. Oracle-пользователи управляются отдельно.')}<div class="info-banner"><b>Разделение уровней доступа</b><span>MAIN_ADMIN управляет ролями USER / ADMIN / MAIN_ADMIN в APP_USERS. Это роли сайта, а не логины SYS, SYSTEM или HK_WEB_APP.</span></div>${table(['Пользователь', 'Email', 'Роль', 'Статус', 'Создан', 'Управление'], rows)}`, 'Пользователи и роли');
}

function pageGuide() {
  const content = `
    ${pageHeader('Архитектура и руководство', 'Как устроено <em>приложение</em>', 'Клиент на HTML/CSS/JavaScript, сервер Node.js и база Oracle Database 19c.')}
    <div class="guide-grid">
      <article class="guide-card"><span>01</span><h3>USER — болельщик</h3><p>Регистрация и вход, просмотр игроков и матчей, выбор места на 2D-схеме арены, резервирование на 15 минут, подтверждение/отмена резерва, избранные игроки.</p></article>
      <article class="guide-card"><span>02</span><h3>ADMIN — администратор</h3><p>CRUD игроков, матчей, билетов и атрибутики, освобождение просроченных резервов, импорт/экспорт JSON, OLAP-отчёты. Не покупает билеты и не ведёт избранное.</p></article>
      <article class="guide-card"><span>03</span><h3>MAIN_ADMIN</h3><p>Все функции администратора плюс просмотр учётных записей, изменение ролей и включение/отключение прикладных пользователей.</p></article>
    </div>
    <section class="section-block">
      <div class="eyebrow">Поток данных</div>
      <h2 style="font-family:var(--font-display);font-weight:800;font-size:24px;margin-top:6px">Браузер → Node.js → PL/SQL → Oracle</h2>
      <div class="architecture-flow"><div><b>HTML / CSS / JavaScript</b><small>Страницы и интерфейс</small></div><span>→</span><div><b>Node.js / Express</b><small>REST API, сессии, bcrypt</small></div><span>→</span><div><b>PKG_WEB_API</b><small>Шлюз PL/SQL</small></div><span>→</span><div><b>Oracle 19c</b><small>Таблицы, роли, OLAP</small></div></div>
      <div class="guide-list">
        <div><b>Frontend</b><span>Статические HTML, CSS и JavaScript-файлы в каталоге public. Шаблонизатор EJS не используется.</span></div>
        <div><b>Backend</b><span>Node.js и Express обрабатывают REST-запросы, проверяют сессии и роли, обращаются к Oracle.</span></div>
        <div><b>Разграничение прав</b><span>Действия болельщика (резерв, покупка, избранное) доступны только роли USER; админ-операции — только ADMIN/MAIN_ADMIN.</span></div>
        <div><b>OLAP</b><span>ROLLUP, CUBE, агрегаты и ранжирование рассчитываются в Oracle, интерфейс показывает возвращённые результаты.</span></div>
      </div>
    </section>`;
  renderLayout(content, 'О приложении');
}

/* ---------- Роутер ---------- */
async function route() {
  const path = location.pathname;
  try {
    if (path === '/') return pageHome();
    if (path === '/matches') return pageMatches();
    const seatMatch = path.match(/^\/matches\/(\d+)\/seats$/); if (seatMatch) return pageArena(seatMatch[1]);
    if (path === '/players') return pagePlayers();
    if (path === '/merch') return pageMerch();
    if (path === '/setup') return pageAuth('setup');
    if (path === '/register') return pageAuth('register');
    if (path === '/login') return pageAuth('login');
    if (path === '/account/tickets') return requireUserPage(pageTickets);
    if (path === '/account/favorites') return requireUserPage(pageFavorites);
    if (path === '/admin') return requireAdminPage(pageAdminDashboard);
    if (path === '/admin/players' || /^\/admin\/players\/\d+\/edit$/.test(path)) return requireAdminPage(pageAdminPlayers);
    if (path === '/admin/matches' || /^\/admin\/matches\/\d+\/edit$/.test(path)) return requireAdminPage(pageAdminMatches);
    if (path === '/admin/tickets') return requireAdminPage(pageAdminTickets);
    if (path === '/admin/merch' || /^\/admin\/merch\/\d+\/edit$/.test(path)) return requireAdminPage(pageAdminMerch);
    if (path === '/admin/json') return requireAdminPage(pageAdminJson);
    if (path === '/admin/olap') return requireAdminPage(pageAdminOlap);
    if (path === '/super/users') return isMainAdmin() ? pageSuperUsers() : accessDenied();
    if (path === '/guide') return pageGuide();
    return renderLayout(`${pageHeader('404', 'Страница <em>не найдена</em>', 'Запрошенный адрес не существует.')}<a class="btn btn-primary" href="/">На главную</a>`, '404');
  } catch (error) {
    renderLayout(`${pageHeader('Ошибка', 'Не удалось <em>загрузить данные</em>', esc(error.message || 'Неизвестная ошибка.'))}<button class="btn btn-primary" data-action="reload">Повторить</button>`, 'Ошибка');
  }
}
async function requireUserPage(fn) {
  if (!state.session.user) { location.replace('/login'); return; }
  if (!isUser()) { location.replace(isAdmin() ? '/admin' : '/'); return; }
  return fn();
}
async function requireAdminPage(fn) {
  if (!isAdmin()) { location.replace(state.session.user ? '/' : '/login'); return; }
  return fn();
}
function accessDenied() { return renderLayout(`${pageHeader('Доступ запрещён', 'Недостаточно <em>прав</em>', 'Эта страница доступна только главному администратору.')}<a class="btn btn-primary" href="/">На главную</a>`, 'Нет доступа'); }

/* ---------- Обработчики событий ---------- */
function selectSeat(el) {
  const seat = {
    ticket_id: num(el.dataset.seatId),
    sector_code: el.dataset.sectorCode,
    seat_row: num(el.dataset.seatRow),
    seat_number: num(el.dataset.seatNumber),
    price: num(el.dataset.price)
  };
  state.selectedSeat = seat;
  document.querySelectorAll('.seat-selected').forEach((n) => n.classList.remove('seat-selected'));
  el.classList.add('seat-selected');
  const sectorCell = document.getElementById('seat-sector');
  const label = document.getElementById('seat-label');
  const price = document.getElementById('seat-price');
  const reserveSlot = document.getElementById('reserve-slot');
  if (sectorCell) sectorCell.textContent = seat.sector_code;
  if (label) label.textContent = `${seat.seat_row} / ${seat.seat_number}`;
  if (price) price.textContent = money(seat.price);
  if (reserveSlot) reserveSlot.innerHTML = summaryReserveArea(seat);
}

appRoot.addEventListener('click', async (event) => {
  const seatEl = event.target.closest('[data-seat-id]');
  if (seatEl) { selectSeat(seatEl); return; }

  const reserveButton = event.target.closest('#reserve-selected');
  if (reserveButton) {
    if (!state.selectedSeat) return;
    if (!state.session?.user) { location.href = '/login'; return; }
    if (!isUser()) { toast('Роль администратора не позволяет покупать билеты.', 'danger'); return; }
    try {
      await send(`/api/tickets/${state.selectedSeat.ticket_id}/reserve`, 'POST', { minutes: 15 });
      state.selectedSeat = null;
      toast('Место зарезервировано. Перейдите в «Мои билеты».', 'success');
      location.href = '/account/tickets';
    } catch (e) { toast(e.message, 'danger'); }
    return;
  }

  const button = event.target.closest('[data-action]'); if (!button) return;
  const action = button.dataset.action;
  try {
    if (action === 'close-notice') { button.closest('.flash')?.remove(); state.notice = null; return; }
    if (action === 'reload') { location.reload(); return; }
    if (action === 'logout') { await send('/api/logout', 'POST', {}); location.href = '/'; return; }
    if (action === 'favorite') {
      const id = button.dataset.id; const favorite = button.dataset.favorite === 'true';
      await request(`/api/players/${id}/favorite`, { method: favorite ? 'DELETE' : 'POST', body: JSON.stringify({}) });
      toast(favorite ? 'Игрок удалён из избранного.' : 'Игрок добавлен в избранное.'); await route(); return;
    }
    if (action === 'ticket') {
      const id = button.dataset.id; const kind = button.dataset.kind;
      await send(`/api/tickets/${id}/${kind}`, 'POST', {});
      toast(kind === 'purchase' ? 'Покупка зарегистрирована в Oracle (демо).' : 'Резерв отменён.'); await pageTickets(); return;
    }
    if (action === 'user-active') {
      const id = button.dataset.id; const newState = button.dataset.active === 'Y' ? 'N' : 'Y';
      if (!confirm(`${newState === 'N' ? 'Отключить' : 'Включить'} учётную запись?`)) return;
      await send(`/api/super/users/${id}/active`, 'PUT', { is_active: newState }); toast('Статус учётной записи изменён.'); await pageSuperUsers(); return;
    }
    if (action === 'api') {
      if (button.dataset.confirm && !confirm(button.dataset.confirm)) return;
      const endpoint = button.dataset.endpoint; const method = button.dataset.method || 'POST';
      const data = await send(endpoint, method, {}); toast(data.message || 'Операция выполнена.'); await route(); return;
    }
  } catch (error) { toast(error.message, 'danger'); }
});

appRoot.addEventListener('submit', async (event) => {
  const form = event.target.closest('form[data-form]'); if (!form) return;
  event.preventDefault();
  const endpoint = form.dataset.endpoint; const method = form.dataset.method || 'POST';
  const submitButton = form.querySelector('[type="submit"],button:not([type])');
  if (submitButton) { submitButton.disabled = true; submitButton.dataset.oldText = submitButton.textContent; submitButton.textContent = 'Выполняется…'; }
  try {
    let response;
    if (form.hasAttribute('data-multipart')) {
      response = await request(endpoint, { method, body: new FormData(form) });
    } else {
      response = await send(endpoint, method, Object.fromEntries(new FormData(form).entries()));
    }
    state.notice = { message: response.message || 'Операция выполнена.', type: 'success' };
    const redirect = endpoint === '/api/login' || endpoint === '/api/register' || endpoint === '/api/setup';
    if (redirect) {
      const session = await get('/api/session'); state.session = session;
      location.href = session.user?.role === 'MAIN_ADMIN' ? '/super/users' : session.user ? '/account/tickets' : '/';
      return;
    }
    await route(); toast(response.message || 'Данные сохранены.');
  } catch (error) {
    toast(error.message, 'danger');
  } finally {
    if (submitButton) { submitButton.disabled = false; submitButton.textContent = submitButton.dataset.oldText || 'Сохранить'; }
  }
});

window.addEventListener('DOMContentLoaded', async () => {
  try {
    state.session = await get('/api/session');
    await route();
  } catch (error) {
    renderLayout(`${pageHeader('Подключение', 'Не удалось получить <em>сессию</em>', esc(error.message || 'Проверьте сервер Node.js и Oracle.'))}<button class="btn btn-primary" data-action="reload">Повторить</button>`, 'Ошибка');
  }
});
