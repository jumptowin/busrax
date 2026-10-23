// Solo se envía la clave publicable. La clave secreta nunca es válida acá.
module.exports = function config(req, res) {
  const url = process.env.SUPABASE_URL || '';
  const key = process.env.SUPABASE_PUBLISHABLE_KEY || '';
  if (!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url) || !key.startsWith('sb_publishable_')) {
    res.statusCode = 503;
    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    return res.end(JSON.stringify({ error: 'Falta completar la configuración pública de Supabase.' }));
  }
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'public, max-age=120');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.end(JSON.stringify({ SUPABASE_URL: url, SUPABASE_ANON_KEY: key }));
};
