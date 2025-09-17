import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

// In-memory store: code -> { ip, port, name, ts }
const store = new Map();
const TTL_MS = 30_000; // Entries expire if not refreshed for 30s

function now() { return Date.now(); }

function cleanup() {
  const cutoff = now() - TTL_MS;
  for (const [code, rec] of store.entries()) {
    if (!rec || rec.ts < cutoff) store.delete(code);
  }
}
setInterval(cleanup, 5_000);

app.get('/', (req, res) => res.json({ ok: true, message: 'Sakspan Matchmaker' }));

// Register or refresh a lobby
// Body: { code, ip, port, name }
app.post('/register', (req, res) => {
  const { code, ip, port, name } = req.body || {};
  if (!code || !ip || !port) return res.status(400).json({ ok: false, error: 'Missing code/ip/port' });
  const norm = String(code).toUpperCase().trim();
  store.set(norm, { ip: String(ip), port: Number(port), name: String(name || ''), ts: now() });
  return res.json({ ok: true });
});

// Lookup a lobby by code
app.get('/lookup', (req, res) => {
  const norm = String(req.query.code || '').toUpperCase().trim();
  if (!norm) return res.status(400).json({ ok: false, error: 'Missing code' });
  const rec = store.get(norm);
  if (!rec) return res.status(404).json({ ok: false, error: 'Not found' });
  return res.json({ ok: true, code: norm, ip: rec.ip, port: rec.port, name: rec.name });
});

const PORT = process.env.PORT || 7070;
const HOST = process.env.HOST || '0.0.0.0';
app.listen(PORT, HOST, () => console.log(`[Matchmaker] Listening on ${HOST}:${PORT}`));
