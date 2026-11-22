import crypto from 'node:crypto';

export function isValidSetupToken(submitted, expected) {
  if (!submitted || !expected) return false;
  const a = Buffer.from(String(submitted));
  const b = Buffer.from(String(expected));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// API-oriented authorization helpers. The HTML client receives JSON responses,
// never a server-rendered template.
export function requireAuth(req, res, next) {
  if (!req.session.user) return res.status(401).json({ ok: false, error: 'Необходим вход в систему.' });
  next();
}

export function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.session.user) return res.status(401).json({ ok: false, error: 'Необходим вход в систему.' });
    if (!roles.includes(req.session.user.role)) return res.status(403).json({ ok: false, error: 'Недостаточно прав.' });
    next();
  };
}

export function csrfProtection(req, res, next) {
  const submitted = req.body?._csrf || req.get('x-csrf-token');
  if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') return next();
  if (!submitted || submitted !== req.session.csrfToken) {
    return res.status(403).json({ ok: false, error: 'Защитный токен формы устарел. Обнови страницу и повтори действие.' });
  }
  next();
}
