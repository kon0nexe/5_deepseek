export function asNumber(value, label = 'Число') {
  const n = Number(value);
  if (!Number.isFinite(n)) throw new Error(`${label}: укажи корректное число.`);
  return n;
}

export function nullableNumber(value) {
  if (value === '' || value === undefined || value === null) return null;
  return asNumber(value);
}

export function nullableDate(value, dateValue) {
  return value ? dateValue(value) : null;
}

export function formatDate(value, withTime = false) {
  if (!value) return '—';
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat('ru-RU', withTime
    ? { dateStyle: 'short', timeStyle: 'short' }
    : { dateStyle: 'medium', timeZone: 'UTC' }).format(date);
}

export function money(value) {
  return new Intl.NumberFormat('ru-RU', { style: 'currency', currency: 'BYN', maximumFractionDigits: 2 }).format(Number(value || 0));
}

export function positionLabel(position) {
  return ({ GOALTENDER: 'Вратарь', DEFENDER: 'Защитник', FORWARD: 'Нападающий' })[position] || position || '—';
}

export function statusLabel(status) {
  return ({ FREE: 'Свободно', RESERVED: 'Резерв', SOLD: 'Продан', RETURNED: 'Возвращён', SCHEDULED: 'Запланирован', COMPLETED: 'Завершён', CANCELLED: 'Отменён', Y: 'Активен', N: 'Отключён' })[status] || status || '—';
}

export function dateInput(value) {
  if (!value) return '';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return d.toISOString().slice(0, 10);
}
