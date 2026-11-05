// Servicio de pedidos / reportes pensado para ejecutarse en AWS Lambda.
// Compatible con eventos de ALB (target group tipo lambda), API Gateway (REST y HTTP) y Function URL.
const APP_ENV = process.env.APP_ENV ?? 'local';
// Prefijo opcional para montar todo el servicio bajo un contexto (ej. BASE_PATH=/ventas)
const BASE_PATH = (process.env.BASE_PATH ?? '').replace(/\/+$/, '');
const BUILD_ID = '5230ec53';
const VERSION = '1.0.0';

const pedidos = [
  { id: 1001, clienteId: 1, total: 670.5, estado: 'ENTREGADO' },
  { id: 1002, clienteId: 2, total: 5200.0, estado: 'EN_CAMINO' },
  { id: 1003, clienteId: 1, total: 450.0, estado: 'PENDIENTE' },
];

const reportes = [
  { id: 'ventas-diarias', descripcion: 'Ventas del día', total: pedidos.reduce((s, p) => s + p.total, 0) },
  { id: 'pendientes', descripcion: 'Pedidos pendientes', total: pedidos.filter((p) => p.estado === 'PENDIENTE').length },
];

const health = (context) => ({
  status: 'ok',
  service: 'app-lambda',
  version: VERSION,
  build: BUILD_ID,
  env: APP_ENV,
  runtime: process.version,
  functionName: context?.functionName ?? 'local',
  timestamp: new Date().toISOString(),
});

// Contextos expuestos. Cada uno puede mapearse a una regla de listener / ruta distinta.
const contextos = {
  '/health': (_id, context) => [200, health(context)],
  '/api/pedidos': (id) => coleccion(pedidos, id),
  '/api/reportes': (id) => coleccion(reportes, id),
};

function coleccion(items, id) {
  if (id === undefined) return [200, items];
  const item = items.find((i) => String(i.id) === id);
  return item ? [200, item] : [404, { error: 'no encontrado', id }];
}

function resolver(pathname) {
  if (BASE_PATH && !pathname.startsWith(BASE_PATH)) return null;
  const ruta = pathname.slice(BASE_PATH.length).replace(/\/+$/, '') || '/';
  if (ruta === '/') return () => [200, { service: 'app-lambda', mensaje: 'ok', contextos: Object.keys(contextos) }];
  for (const [ctx, handler] of Object.entries(contextos)) {
    if (ruta === ctx) return (context) => handler(undefined, context);
    if (ruta.startsWith(ctx + '/')) return (context) => handler(ruta.slice(ctx.length + 1), context);
  }
  return null;
}

export const handler = async (event = {}, context) => {
  // ALB y API Gateway REST usan event.path; HTTP API y Function URL usan event.rawPath
  const pathname = event.rawPath ?? event.path ?? '/';
  const method = event.requestContext?.http?.method ?? event.httpMethod ?? 'GET';
  const resolved = method === 'GET' ? resolver(pathname) : null;
  const [status, body] = resolved ? resolved(context) : [404, { error: 'ruta no encontrada', path: pathname }];

  console.log(JSON.stringify({ method, path: pathname, status }));

  return {
    statusCode: status,
    // statusDescription: `${status}`, // requerido por ALB
    statusDescription: `${status} ${({ 200: 'OK', 404: 'Not Found', 500: 'Internal Server Error' })[status] ?? 'Error'}`, // Formato HTTP que espera el ALB: código y descripción, por ejemplo "200 OK".
    isBase64Encoded: false,
    headers: { 'content-type': 'application/json; charset=utf-8', 'x-build-id': BUILD_ID },
    body: JSON.stringify(body),
  };
};
