import oracledb from 'oracledb';

oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT;
oracledb.fetchAsString = [oracledb.CLOB];

let pool;

export async function initOraclePool(config) {
  if (pool) return pool;
  pool = await oracledb.createPool({
    user: config.user,
    password: config.password,
    connectString: config.connectString,
    poolMin: config.poolMin,
    poolMax: config.poolMax,
    poolIncrement: 1,
    poolTimeout: 60,
    queueTimeout: 30000,
    homogeneous: true
  });
  // Fail early with a helpful message instead of discovering connection errors on first click.
  const connection = await pool.getConnection();
  try {
    const result = await connection.execute(
      `SELECT SYS_CONTEXT('USERENV','SERVICE_NAME') AS SERVICE_NAME,
              SYS_CONTEXT('USERENV','SESSION_USER') AS SESSION_USER FROM dual`
    );
    return { pool, connectionInfo: result.rows?.[0] ?? null };
  } finally {
    await connection.close();
  }
}

export function getOraclePool() {
  if (!pool) throw new Error('Пул соединений Oracle ещё не инициализирован.');
  return pool;
}

async function withConnection(callback) {
  const connection = await getOraclePool().getConnection();
  try {
    return await callback(connection);
  } finally {
    await connection.close();
  }
}


function nullBindType(name) {
  const key = String(name).toLowerCase();
  if (key.includes('date') || key.includes('time')) return oracledb.DATE;
  if (key.includes('json') || key.includes('clob')) return oracledb.CLOB;
  if (/(status|name|category|position|country|description|email|username|role|active|home|city|password|code)/.test(key)) {
    return oracledb.STRING;
  }
  return oracledb.NUMBER;
}

function typeNullBinds(binds) {
  const normalized = {};
  for (const [name, value] of Object.entries(binds)) {
    normalized[name] = value === null || value === undefined
      ? { val: null, type: nullBindType(name) }
      : value;
  }
  return normalized;
}

function makeBlock(procName, bindNames) {
  // procName is always a constant in this project; all user input is bound separately.
  const placeholders = bindNames.map((name) => `:${name}`).join(', ');
  return `BEGIN HK_DINAMO.PKG_WEB_API.${procName}(${placeholders}); END;`;
}

export async function callProcedure(procName, binds = {}, options = {}) {
  return withConnection(async (connection) => {
    const names = Object.keys(binds);
    const result = await connection.execute(makeBlock(procName, names), typeNullBinds(binds), {
      autoCommit: options.autoCommit !== false
    });
    return result.outBinds ?? {};
  });
}

export async function callCursor(procName, binds = {}, cursorName = 'p_result') {
  return withConnection(async (connection) => {
    const cursorBind = {
      dir: oracledb.BIND_OUT,
      type: oracledb.CURSOR
    };
    const allBinds = { ...typeNullBinds(binds), [cursorName]: cursorBind };
    const result = await connection.execute(makeBlock(procName, Object.keys(allBinds)), allBinds, {
      outFormat: oracledb.OUT_FORMAT_OBJECT,
      autoCommit: false
    });
    const resultSet = result.outBinds?.[cursorName];
    if (!resultSet) return [];
    try {
      // Seat rows and admin pages are bounded; public lists are small by design.
      const rows = await resultSet.getRows(12000);
      return rows.map(normalizeRow);
    } finally {
      await resultSet.close();
    }
  });
}

export async function callWithOut(procName, binds, outputName) {
  return callProcedure(procName, binds).then((outBinds) => outBinds[outputName]);
}

export function dateValue(value) {
  if (!value) return null;
  // Use UTC noon so a date-only form value cannot shift to the previous day
  // in time zones with a positive/negative offset.
  return new Date(`${value}T12:00:00.000Z`);
}

function normalizeRow(row) {
  const out = {};
  for (const [key, value] of Object.entries(row)) {
    out[key.toLowerCase()] = value instanceof Date ? value : value;
  }
  return out;
}

export async function readLob(lob) {
  if (lob == null) return '';
  if (typeof lob === 'string' || Buffer.isBuffer(lob)) return String(lob);
  return new Promise((resolve, reject) => {
    const chunks = [];
    lob.setEncoding?.('utf8');
    lob.on('data', (chunk) => chunks.push(chunk));
    lob.on('end', () => resolve(chunks.join('')));
    lob.on('error', reject);
  });
}

export async function closeOraclePool() {
  if (pool) {
    const current = pool;
    pool = undefined;
    await current.close(10);
  }
}
