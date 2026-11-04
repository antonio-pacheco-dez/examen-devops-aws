// Servicio de catálogo (clientes / productos) pensado para ejecutarse en ECS detrás de un ALB.
// Sin dependencias externas: solo módulos nativos de Node.js.
import http from 'node:http';
import os from 'node:os';

const PORT = Number(process.env.PORT ?? 3000);
const APP_ENV = process.env.APP_ENV ?? 'local';
// Prefijo opcional para montar todo el servicio bajo un contexto (ej. BASE_PATH=/catalogo)
const BASE_PATH = (process.env.BASE_PATH ?? '').replace(/\/+$/, '');
const BUILD_ID = '5230ec53';
const VERSION = '1.0.0';
const startedAt = Date.now();

const clientes = [
  { id: 1, nombre: 'Ana López', email: 'ana@example.com' },
  { id: 2, nombre: 'Carlos Ruiz', email: 'carlos@example.com' },
  { id: 3, nombre: 'María Pérez', email: 'maria@example.com' },
];

const productos = [
  { id: 1, nombre: 'Teclado', precio: 450.0 },
  { id: 2, nombre: 'Mouse', precio: 220.5 },
  { id: 3, nombre: 'Monitor 27"', precio: 5200.0 },
];

const health = () => ({
  status: 'ok',
  service: 'app-ecs',
  version: VERSION,
  build: BUILD_ID,
  env: APP_ENV,
  hostname: os.hostname(),
  uptimeSeconds: Math.round((Date.now() - startedAt) / 1000),
  timestamp: new Date().toISOString(),
});

// Contextos expuestos. Cada uno puede mapearse a una regla de listener distinta en el ALB.
const contextos = {
  '/health': () => [200, health()],
  '/api/clientes': (id) => coleccion(clientes, id),
  '/api/productos': (id) => coleccion(productos, id),
  '/api/info': () => [200, { service: 'app-ecs', contextos: Object.keys(contextos), basePath: BASE_PATH || '/' }],
};

function coleccion(items, id) {
  if (id === undefined) return [200, items];
  const item = items.find((i) => String(i.id) === id);
  return item ? [200, item] : [404, { error: 'no encontrado', id }];
}

function resolver(pathname) {
  if (BASE_PATH && !pathname.startsWith(BASE_PATH)) return null;
  const ruta = pathname.slice(BASE_PATH.length).replace(/\/+$/, '') || '/';
  if (ruta === '/') return () => [200, { service: 'app-ecs', mensaje: 'ok', contextos: Object.keys(contextos) }];
  for (const [ctx, handler] of Object.entries(contextos)) {
    if (ruta === ctx) return () => handler();
    if (ruta.startsWith(ctx + '/')) return () => handler(ruta.slice(ctx.length + 1));
  }
  return null;
}

const server = http.createServer((req, res) => {
  const inicio = Date.now();
  const { pathname } = new URL(req.url, 'http://localhost');
  const handler = req.method === 'GET' ? resolver(pathname) : null;
  const [status, body] = handler ? handler() : [404, { error: 'ruta no encontrada', path: pathname }];

  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8', 'x-build-id': BUILD_ID });
  res.end(JSON.stringify(body));

  // Logs en JSON hacia stdout -> CloudWatch Logs (awslogs driver)
  console.log(JSON.stringify({ method: req.method, path: pathname, status, ms: Date.now() - inicio }));
});

server.listen(PORT, () => {
  console.log(JSON.stringify({ msg: 'app-ecs iniciado', port: PORT, env: APP_ENV, basePath: BASE_PATH || '/' }));
});

// ECS envía SIGTERM al detener la tarea: cerramos conexiones de forma ordenada
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    console.log(JSON.stringify({ msg: `recibido ${signal}, cerrando` }));
    server.close(() => process.exit(0));
  });
}
