import 'dotenv/config';
import express from 'express';
import session from 'express-session';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import multer from 'multer';
import bcrypt from 'bcryptjs';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import oracledb from 'oracledb';
import {
  initOraclePool, callCursor, callProcedure, dateValue, readLob, closeOraclePool
} from './src/oracle.js';
import { asNumber, nullableNumber, nullableDate } from './src/utils.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PUBLIC_DIR = path.join(__dirname, 'public');
const INDEX_FILE = path.join(PUBLIC_DIR, 'index.html');
const app = express();
const PORT = Number(process.env.PORT || 3000);
const ADMIN_ROLES = ['ADMIN', 'MAIN_ADMIN'];
const USER_ROLE = ['USER'];
const upload = multer({ storage: multer.memoryStorage(), limits: { fileSize: 2 * 1024 * 1024, files: 1 } });

app.disable('x-powered-by');
app.set('trust proxy', 1);
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", 'data:'],
      connectSrc: ["'self'"],
      fontSrc: ["'self'", 'data:'],
      objectSrc: ["'none'"],
      upgradeInsecureRequests: null
    }
  }
}));
app.use(express.urlencoded({ extended: true, limit: '1mb' }));
app.use(express.json({ limit: '2mb' }));
app.use(express.static(PUBLIC_DIR, { maxAge: process.env.NODE_ENV === 'production' ? '1h' : 0, index: false }));
app.use(session({
  name: 'dinamo.sid',
  secret: process.env.SESSION_SECRET || crypto.randomBytes(48).toString('hex'),
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production',
    maxAge: 1000 * 60 * 60 * 8
  }
}));

const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 20, standardHeaders: 'draft-8', legacyHeaders: false });
const asyncRoute = (handler) => (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);
const outNumber = () => ({ dir: oracledb.BIND_OUT, type: oracledb.NUMBER });
const outString = (maxSize = 4000) => ({ dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize });
const outClob = () => ({ dir: oracledb.BIND_OUT, type: oracledb.CLOB });
const userId = (req) => Number(req.session.user.id);
const safeDate = (value) => nullableDate(value, dateValue);
const safeNumber = (value) => nullableNumber(value);

function apiError(res, status, message, details) {
  return res.status(status).json({ ok: false, error: message, ...(details ? { details } : {}) });
}
function oracleMessage(error) {
  const message = String(error?.message || 'Внутренняя ошибка.');
  const ora = message.match(/ORA-\d{5}:\s*([^\n]+)/);
  return ora ? ora[1] : message.split('\n')[0];
}
function requireAuthApi(req, res, next) {
  if (!req.session.user) return apiError(res, 401, 'Для этого действия необходимо войти в систему.');
  next();
}
function requireRoleApi(...roles) {
  return (req, res, next) => {
    if (!req.session.user) return apiError(res, 401, 'Необходим вход в систему.');
    if (!roles.includes(req.session.user.role)) return apiError(res, 403, 'Недостаточно прав для выполнения действия.');
    next();
  };
}
function checkCsrf(req, res, next) {
  const supplied = req.get('x-csrf-token') || req.body?._csrf;
  if (!supplied || !req.session.csrfToken || supplied !== req.session.csrfToken) {
    return apiError(res, 403, 'Защитный токен устарел. Обнови страницу и повтори действие.');
  }
  next();
}
async function hasMainAdmin() {
  const out = await callProcedure('HAS_MAIN_ADMIN', { p_exists: outNumber() });
  return Number(out.p_exists || 0) > 0;
}
function setApiUser(req, user) {
  return new Promise((resolve, reject) => {
    req.session.regenerate((error) => {
      if (error) return reject(error);
      req.session.csrfToken = crypto.randomBytes(32).toString('hex');
      req.session.user = user;
      req.session.save((saveError) => saveError ? reject(saveError) : resolve());
    });
  });
}

// Session state and CSRF token used by the plain HTML/JavaScript client.
app.get('/api/session', asyncRoute(async (req, res) => {
  if (!req.session.csrfToken) req.session.csrfToken = crypto.randomBytes(32).toString('hex');
  const setupRequired = !(await hasMainAdmin());
  const payload = {
    ok: true,
    csrfToken: req.session.csrfToken,
    user: req.session.user || null,
    setupRequired
  };
  res.json(payload);
}));
app.get('/api/health', asyncRoute(async (_req, res) => {
  const info = await callCursor('DASHBOARD');
  res.json({ status: 'ok', database: 'Oracle 19c', service: info.length ? 'connected' : 'connected-no-rows' });
}));
app.get('/health', asyncRoute(async (_req, res) => {
  const info = await callCursor('DASHBOARD');
  res.json({ status: 'ok', database: 'Oracle 19c', service: info.length ? 'connected' : 'connected-no-rows' });
}));

// ---------------------------------------------------------------------------
// Public data API
// ---------------------------------------------------------------------------
app.get('/api/home', asyncRoute(async (_req, res) => {
  const [metrics, matches, players] = await Promise.all([
    callCursor('DASHBOARD'),
    callCursor('LIST_MATCHES', { p_date_from: null, p_date_to: null }),
    callCursor('LIST_PLAYERS')
  ]);
  res.json({ metrics: metrics[0] || {}, matches: matches.slice(0, 3), players: players.slice(0, 4) });
}));
app.get('/api/matches', asyncRoute(async (req, res) => {
  const matches = await callCursor('LIST_MATCHES', {
    p_date_from: safeDate(req.query.from), p_date_to: safeDate(req.query.to)
  });
  res.json({ matches });
}));
app.get('/api/matches/:id/seats', asyncRoute(async (req, res) => {
  const matchId = asNumber(req.params.id, 'Матч');
  const match = (await callCursor('MATCH_DETAIL', { p_match_id: matchId }))[0];
  if (!match) return apiError(res, 404, 'Матч не найден или недоступен для продажи.');
  const sectors = await callCursor('LIST_SECTORS', { p_stadium_id: match.stadium_id });
  if (!sectors.length) return apiError(res, 404, 'Для арены не созданы сектора.');
  const sectorId = Number(req.query.sector || sectors[0].sector_id);
  const sector = sectors.find((item) => Number(item.sector_id) === sectorId) || sectors[0];
  const rows = await callCursor('LIST_SECTOR_ROWS', { p_match_id: matchId, p_sector_id: sector.sector_id });
  const requestedRow = Number(req.query.row || rows[0]?.seat_row || 1);
  const row = rows.find((item) => Number(item.seat_row) === requestedRow) || rows[0] || null;
  const seats = row ? await callCursor('LIST_SEATS', {
    p_match_id: matchId, p_sector_id: sector.sector_id, p_seat_row: Number(row.seat_row)
  }) : [];
  res.json({ match, sectors, selectedSectorId: sector.sector_id, rows, selectedRow: row?.seat_row || null, seats });
}));
app.get('/api/matches/:id/arena', asyncRoute(async (req, res) => {
  const matchId = asNumber(req.params.id, 'Матч');
  const match = (await callCursor('MATCH_DETAIL', { p_match_id: matchId }))[0];
  if (!match) return apiError(res, 404, 'Матч не найден или недоступен для продажи.');
  const sectors = await callCursor('LIST_SECTORS', { p_stadium_id: match.stadium_id });
  if (!sectors.length) return apiError(res, 404, 'Для арены не созданы сектора.');
  const seats = await callCursor('ARENA_SEATS', { p_match_id: matchId });
  res.json({ match, sectors, seats });
}));
app.get('/api/players', asyncRoute(async (req, res) => {
  const [players, favorites] = await Promise.all([
    callCursor('LIST_PLAYERS'),
    req.session.user ? callCursor('LIST_FAVORITES', { p_app_user_id: userId(req) }) : Promise.resolve([])
  ]);
  res.json({ players, favoriteIds: favorites.map((x) => Number(x.player_id)) });
}));
app.get('/api/merch', asyncRoute(async (_req, res) => {
  res.json({ items: await callCursor('LIST_MERCH') });
}));

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------
app.post('/api/setup', authLimiter, checkCsrf, asyncRoute(async (req, res) => {
  if (await hasMainAdmin()) return apiError(res, 409, 'Главный администратор уже существует.');
  const b = req.body || {};
  const submittedToken = String(b.setupToken || '');
  const expectedToken = String(process.env.SETUP_TOKEN || '');
  const a = Buffer.from(submittedToken);
  const expected = Buffer.from(expectedToken);
  if (!expected.length || a.length !== expected.length || !crypto.timingSafeEqual(a, expected)) {
    return apiError(res, 403, 'Неверный SETUP_TOKEN. Проверь настройки .env.');
  }
  if (!b.username || !b.password || !b.email || !b.firstName || !b.lastName || String(b.password).length < 10) {
    return apiError(res, 400, 'Заполни обязательные поля. Пароль главного администратора — не менее 10 символов.');
  }
  const hash = await bcrypt.hash(String(b.password), 12);
  const out = await callProcedure('BOOTSTRAP_MAIN_ADMIN', {
    p_username: String(b.username).trim(), p_password_hash: hash, p_email: String(b.email).trim().toLowerCase(),
    p_first_name: String(b.firstName).trim(), p_last_name: String(b.lastName).trim(),
    p_city: String(b.city || 'Минск').trim(), p_user_id: outNumber()
  });
  await setApiUser(req, { id: Number(out.p_user_id), username: String(b.username).trim(), email: String(b.email).trim(), role: 'MAIN_ADMIN' });
  res.json({ ok: true, message: 'Главный администратор создан.', user: req.session.user });
}));
app.post('/api/register', authLimiter, checkCsrf, asyncRoute(async (req, res) => {
  const b = req.body || {};
  if (!b.username || !b.password || !b.email || !b.firstName || !b.lastName) return apiError(res, 400, 'Заполни все обязательные поля.');
  if (String(b.password).length < 8 || String(b.password) !== String(b.confirmPassword || '')) return apiError(res, 400, 'Пароль должен содержать минимум 8 символов; подтверждение должно совпадать.');
  const hash = await bcrypt.hash(String(b.password), 12);
  const out = await callProcedure('REGISTER_USER', {
    p_username: String(b.username).trim(), p_password_hash: hash, p_email: String(b.email).trim().toLowerCase(),
    p_first_name: String(b.firstName).trim(), p_last_name: String(b.lastName).trim(),
    p_city: String(b.city || 'Минск').trim(), p_user_id: outNumber()
  });
  await setApiUser(req, { id: Number(out.p_user_id), username: String(b.username).trim(), email: String(b.email).trim(), role: 'USER' });
  res.json({ ok: true, message: 'Регистрация завершена.', user: req.session.user });
}));
app.post('/api/login', authLimiter, checkCsrf, asyncRoute(async (req, res) => {
  const username = String(req.body?.username || '').trim();
  const password = String(req.body?.password || '');
  if (!username || !password) return apiError(res, 400, 'Укажи логин и пароль.');
  const out = await callProcedure('GET_LOGIN', {
    p_username: username, p_user_id: outNumber(), p_password_hash: outString(200),
    p_email: outString(200), p_role: outString(30),
    p_is_active: { dir: oracledb.BIND_OUT, type: oracledb.STRING, maxSize: 1 }
  });
  const valid = Boolean(out.p_password_hash && out.p_is_active === 'Y' && await bcrypt.compare(password, out.p_password_hash));
  if (!valid) return apiError(res, 401, 'Неверный логин или пароль, либо учётная запись отключена.');
  await setApiUser(req, { id: Number(out.p_user_id), username, email: out.p_email, role: out.p_role });
  res.json({ ok: true, message: `Вход выполнен. Роль: ${out.p_role}.`, user: req.session.user });
}));
app.post('/api/logout', requireAuthApi, checkCsrf, (req, res, next) => {
  req.session.destroy((error) => {
    if (error) return next(error);
    res.clearCookie('dinamo.sid');
    res.json({ ok: true });
  });
});

// ---------------------------------------------------------------------------
// User operations
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Fan operations are USER-only. Admin / MAIN_ADMIN roles manage data through
// the admin API and must not purchase or reserve tickets for themselves.
// ---------------------------------------------------------------------------
app.get('/api/account/tickets', requireRoleApi('USER'), asyncRoute(async (req, res) => {
  res.json({ tickets: await callCursor('MY_TICKETS', { p_app_user_id: userId(req) }) });
}));
app.get('/api/account/favorites', requireRoleApi('USER'), asyncRoute(async (req, res) => {
  res.json({ players: await callCursor('LIST_FAVORITES', { p_app_user_id: userId(req) }) });
}));
app.post('/api/tickets/:id/reserve', requireRoleApi('USER'), checkCsrf, asyncRoute(async (req, res) => {
  const minutes = Math.min(120, Math.max(1, Number(req.body?.minutes || 15)));
  await callProcedure('RESERVE_TICKET', { p_ticket_id: asNumber(req.params.id), p_app_user_id: userId(req), p_minutes: minutes });
  res.json({ ok: true, message: `Место зарезервировано на ${minutes} минут.` });
}));
app.post('/api/tickets/:id/purchase', requireRoleApi('USER'), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('PURCHASE_TICKET', { p_ticket_id: asNumber(req.params.id), p_app_user_id: userId(req) });
  res.json({ ok: true, message: 'Покупка зарегистрирована в Oracle. Оплата демонстрационная.' });
}));
app.post('/api/tickets/:id/cancel', requireRoleApi('USER'), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('CANCEL_RESERVATION', { p_ticket_id: asNumber(req.params.id), p_app_user_id: userId(req) });
  res.json({ ok: true, message: 'Резерв отменён.' });
}));
app.post('/api/players/:id/favorite', requireRoleApi('USER'), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('ADD_FAVORITE', { p_app_user_id: userId(req), p_player_id: asNumber(req.params.id) });
  res.json({ ok: true, message: 'Игрок добавлен в избранное.' });
}));
app.delete('/api/players/:id/favorite', requireRoleApi('USER'), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('REMOVE_FAVORITE', { p_app_user_id: userId(req), p_player_id: asNumber(req.params.id) });
  res.json({ ok: true, message: 'Игрок удалён из избранного.' });
}));

// ---------------------------------------------------------------------------
// ADMIN API: dashboards and CRUD
// ---------------------------------------------------------------------------
app.get('/api/admin/dashboard', requireRoleApi(...ADMIN_ROLES), asyncRoute(async (_req, res) => {
  const [stats, matches] = await Promise.all([callCursor('DASHBOARD'), callCursor('ADMIN_MATCHES')]);
  res.json({ stats: stats[0] || {}, matches: matches.filter((m) => !String(m.opponent_name).startsWith('TEST PERF')).slice(0, 6) });
}));
app.get('/api/admin/players', requireRoleApi(...ADMIN_ROLES), asyncRoute(async (_req, res) => {
  res.json({ players: await callCursor('ADMIN_PLAYERS') });
}));
app.post('/api/admin/players', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  const b = req.body;
  const out = await callProcedure('ADD_PLAYER', {
    p_first_name: b.first_name, p_last_name: b.last_name, p_position: b.position,
    p_jersey_number: safeNumber(b.jersey_number), p_birth_date: safeDate(b.birth_date),
    p_country: b.country || null, p_height_cm: safeNumber(b.height_cm), p_weight_kg: safeNumber(b.weight_kg),
    p_player_id: outNumber()
  });
  res.json({ ok: true, id: Number(out.p_player_id), message: 'Игрок добавлен.' });
}));
app.put('/api/admin/players/:id', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  const b = req.body;
  await callProcedure('UPDATE_PLAYER', {
    p_player_id: asNumber(req.params.id), p_first_name: b.first_name, p_last_name: b.last_name,
    p_position: b.position, p_jersey_number: safeNumber(b.jersey_number), p_birth_date: safeDate(b.birth_date),
    p_country: b.country || null, p_height_cm: safeNumber(b.height_cm), p_weight_kg: safeNumber(b.weight_kg), p_is_active: b.is_active || 'Y'
  });
  res.json({ ok: true, message: 'Сведения об игроке обновлены.' });
}));
app.delete('/api/admin/players/:id', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('DELETE_PLAYER', { p_player_id: asNumber(req.params.id) });
  res.json({ ok: true, message: 'Игрок удалён.' });
}));

app.get('/api/admin/matches', requireRoleApi(...ADMIN_ROLES), asyncRoute(async (_req, res) => {
  const [matches, stadiums] = await Promise.all([callCursor('ADMIN_MATCHES'), callCursor('LIST_STADIUMS')]);
  res.json({ matches: matches.filter((m) => !String(m.opponent_name).startsWith('TEST PERF')), stadiums });
}));
app.post('/api/admin/matches', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  const b = req.body;
  const out = await callProcedure('ADD_MATCH', {
    p_match_date: safeDate(b.match_date), p_opponent_name: b.opponent_name,
    p_stadium_id: asNumber(b.stadium_id), p_is_home: b.is_home || 'Y', p_match_id: outNumber()
  });
  res.json({ ok: true, id: Number(out.p_match_id), message: 'Матч добавлен.' });
}));
app.put('/api/admin/matches/:id', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  const b = req.body;
  await callProcedure('UPDATE_MATCH', {
    p_match_id: asNumber(req.params.id), p_match_date: safeDate(b.match_date), p_opponent_name: b.opponent_name,
    p_stadium_id: asNumber(b.stadium_id), p_is_home: b.is_home || 'Y', p_match_status: b.match_status,
    p_goals_for: safeNumber(b.goals_for), p_goals_against: safeNumber(b.goals_against)
  });
  res.json({ ok: true, message: 'Матч обновлён.' });
}));
app.delete('/api/admin/matches/:id', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('DELETE_MATCH', { p_match_id: asNumber(req.params.id) });
  res.json({ ok: true, message: 'Матч удалён.' });
}));

app.get('/api/admin/tickets', requireRoleApi(...ADMIN_ROLES), asyncRoute(async (req, res) => {
  const [tickets, matches, stadiums, fans] = await Promise.all([
    callCursor('ADMIN_TICKETS', {
      p_match_id: safeNumber(req.query.match_id), p_status: req.query.status || null,
      p_page: Number(req.query.page || 1), p_page_size: Number(req.query.page_size || 50)
    }),
    callCursor('ADMIN_MATCHES'), callCursor('LIST_STADIUMS'), callCursor('LIST_FANS')
  ]);
  const sectorLists = await Promise.all(stadiums.map((s) => callCursor('LIST_SECTORS', { p_stadium_id: s.stadium_id })));
  res.json({ tickets, matches: matches.filter((m) => !String(m.opponent_name).startsWith('TEST PERF')), stadiums, sectors: sectorLists.flat(), fans });
}));
app.post('/api/admin/tickets', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  const b = req.body;
  const out = await callProcedure('ADD_TICKET', {
    p_match_id: asNumber(b.match_id), p_sector_id: asNumber(b.sector_id),
    p_seat_row: asNumber(b.seat_row), p_seat_number: asNumber(b.seat_number), p_price: asNumber(b.price), p_ticket_id: outNumber()
  });
  res.json({ ok: true, id: Number(out.p_ticket_id), message: 'Билет добавлен.' });
}));
app.post('/api/admin/tickets/release-expired', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (_req, res) => {
  const out = await callProcedure('RELEASE_EXPIRED', { p_released_count: outNumber() });
  res.json({ ok: true, released: Number(out.p_released_count || 0), message: 'Просроченные резервы освобождены.' });
}));
app.post('/api/admin/tickets/:id/sell', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('SELL_TICKET', { p_ticket_id: asNumber(req.params.id), p_fan_id: asNumber(req.body.fan_id) });
  res.json({ ok: true, message: 'Билет отмечен проданным.' });
}));
app.put('/api/admin/tickets/:id', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('UPDATE_TICKET', {
    p_ticket_id: asNumber(req.params.id), p_seat_row: asNumber(req.body.seat_row),
    p_seat_number: asNumber(req.body.seat_number), p_price: asNumber(req.body.price)
  });
  res.json({ ok: true, message: 'Параметры билета обновлены.' });
}));
app.delete('/api/admin/tickets/:id', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('DELETE_TICKET', { p_ticket_id: asNumber(req.params.id) });
  res.json({ ok: true, message: 'Билет удалён.' });
}));
app.post('/api/admin/tickets/:id/return', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('RETURN_TICKET', { p_ticket_id: asNumber(req.params.id) });
  res.json({ ok: true, message: 'Оформлен возврат билета.' });
}));

app.get('/api/admin/merch', requireRoleApi(...ADMIN_ROLES), asyncRoute(async (_req, res) => {
  res.json({ items: await callCursor('ADMIN_MERCH') });
}));
app.post('/api/admin/merch', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  const b = req.body;
  const out = await callProcedure('ADD_MERCH', {
    p_name: b.name, p_category: b.category, p_price: asNumber(b.price),
    p_description: b.description || null, p_merch_id: outNumber()
  });
  res.json({ ok: true, id: Number(out.p_merch_id), message: 'Товар добавлен.' });
}));
app.put('/api/admin/merch/:id', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  const b = req.body;
  await callProcedure('UPDATE_MERCH', {
    p_merch_id: asNumber(req.params.id), p_name: b.name, p_category: b.category,
    p_price: asNumber(b.price), p_description: b.description || null, p_is_active: b.is_active || 'Y'
  });
  res.json({ ok: true, message: 'Товар обновлён.' });
}));
app.delete('/api/admin/merch/:id', requireRoleApi(...ADMIN_ROLES), checkCsrf, asyncRoute(async (req, res) => {
  await callProcedure('DELETE_MERCH', { p_merch_id: asNumber(req.params.id) });
  res.json({ ok: true, message: 'Товар удалён.' });
}));

app.post('/api/admin/json/import', requireRoleApi(...ADMIN_ROLES), upload.single('jsonFile'), (req, res, next) => checkCsrf(req, res, next), asyncRoute(async (req, res) => {
  if (!req.file) return apiError(res, 400, 'Выбери JSON-файл размером до 2 МБ.');
  const json = req.file.buffer.toString('utf8');
  let parsed;
  try { parsed = JSON.parse(json); } catch { return apiError(res, 400, 'Файл не является корректным JSON.'); }
  if (!parsed || !Array.isArray(parsed.players)) return apiError(res, 400, 'Ожидается JSON-объект с массивом players.');
  const out = await callProcedure('IMPORT_PLAYERS_JSON', { p_json: { val: json, type: oracledb.CLOB }, p_inserted: outNumber() });
  res.json({ ok: true, inserted: Number(out.p_inserted || 0), message: `Импортировано игроков: ${Number(out.p_inserted || 0)}.` });
}));
app.get('/api/admin/json/export', requireRoleApi(...ADMIN_ROLES), asyncRoute(async (_req, res) => {
  const out = await callProcedure('EXPORT_PLAYERS_JSON', { p_json: outClob() });
  const json = await readLob(out.p_json);
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Content-Disposition', 'attachment; filename="dinamo_players_export.json"');
  res.send(json || '{"players":[]}');
}));
app.get('/api/admin/olap', requireRoleApi(...ADMIN_ROLES), asyncRoute(async (req, res) => {
  const from = safeDate(req.query.from);
  const to = safeDate(req.query.to);
  const out = await callProcedure('OLAP_SUMMARY', {
    p_date_from: from, p_date_to: to,
    p_sold_count: outNumber(), p_revenue: outNumber(), p_merch_revenue: outNumber()
  });
  const [sales, cube, players] = await Promise.all([
    callCursor('OLAP_SALES_ROLLUP', { p_date_from: from, p_date_to: to }),
    callCursor('OLAP_SALES_CUBE', { p_date_from: from, p_date_to: to }),
    callCursor('OLAP_PLAYERS')
  ]);
  res.json({ summary: { sold: Number(out.p_sold_count || 0), revenue: Number(out.p_revenue || 0), merchRevenue: Number(out.p_merch_revenue || 0) }, sales, cube, players });
}));

// ---------------------------------------------------------------------------
// MAIN_ADMIN account management
// ---------------------------------------------------------------------------
app.get('/api/super/users', requireRoleApi('MAIN_ADMIN'), asyncRoute(async (_req, res) => {
  res.json({ users: await callCursor('APP_USERS') });
}));
app.put('/api/super/users/:id/role', requireRoleApi('MAIN_ADMIN'), checkCsrf, asyncRoute(async (req, res) => {
  const targetId = asNumber(req.params.id);
  if (targetId === userId(req) && req.body.role !== 'MAIN_ADMIN') return apiError(res, 400, 'Нельзя понизить собственную роль главного администратора.');
  if (!['USER', 'ADMIN', 'MAIN_ADMIN'].includes(req.body.role)) return apiError(res, 400, 'Недопустимая роль.');
  await callProcedure('CHANGE_USER_ROLE', { p_user_id: targetId, p_role: req.body.role });
  res.json({ ok: true, message: 'Роль изменена.' });
}));
app.put('/api/super/users/:id/active', requireRoleApi('MAIN_ADMIN'), checkCsrf, asyncRoute(async (req, res) => {
  const targetId = asNumber(req.params.id);
  if (targetId === userId(req) && req.body.is_active === 'N') return apiError(res, 400, 'Нельзя отключить собственную учётную запись.');
  await callProcedure('SET_USER_ACTIVE', { p_user_id: targetId, p_is_active: req.body.is_active });
  res.json({ ok: true, message: 'Статус учётной записи изменён.' });
}));

// Unknown API paths return JSON; all browser page routes serve the same static HTML shell.
app.use('/api', (_req, res) => apiError(res, 404, 'API-маршрут не найден.'));
app.use((req, res, next) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') return next();
  res.sendFile(INDEX_FILE, (error) => error && next(error));
});
app.use((req, res) => apiError(res, 404, 'Маршрут не найден.'));
app.use((error, req, res, _next) => {
  console.error(`[${new Date().toISOString()}] ${req.method} ${req.originalUrl}`, error);
  if (res.headersSent) return;
  const message = oracleMessage(error);
  const status = error instanceof multer.MulterError ? 400 : (Number(error.status) || 500);
  if (req.originalUrl.startsWith('/api/')) return apiError(res, status, status === 500 ? `Не удалось выполнить операцию. ${message}` : message);
  res.status(status).sendFile(INDEX_FILE);
});

async function start() {
  const db = {
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    connectString: process.env.DB_CONNECT_STRING,
    poolMin: Number(process.env.DB_POOL_MIN || 1),
    poolMax: Number(process.env.DB_POOL_MAX || 6)
  };
  if (!db.user || !db.password || !db.connectString) throw new Error('Заполни DB_USER, DB_PASSWORD и DB_CONNECT_STRING в .env.');
  if (!process.env.SESSION_SECRET || process.env.SESSION_SECRET.startsWith('replace_')) console.warn('ВНИМАНИЕ: замени SESSION_SECRET в .env.');
  const info = await initOraclePool(db);
  console.log(`Oracle подключён: ${info.connectionInfo?.SERVICE_NAME || db.connectString} / ${info.connectionInfo?.SESSION_USER || db.user}`);
  const server = app.listen(PORT, () => {
    console.log(`Динамо-Минск Web App (HTML/CSS/JS): ${process.env.APP_BASE_URL || `http://localhost:${PORT}`}`);
    console.log(`Проверка: http://localhost:${PORT}/health`);
  });
  const shutdown = async () => server.close(async () => { await closeOraclePool(); process.exit(0); });
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}
start().catch((error) => {
  console.error('Не удалось запустить приложение:', error.message || error);
  console.error('Проверь Oracle, PDB, PKG_WEB_API и пользователя HK_WEB_APP.');
  process.exit(1);
});
