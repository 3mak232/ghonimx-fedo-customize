const CACHE='fedo-factory-dev-v2';
const ASSETS=['./','./index.html','./app.js','./factory-v5.js','./style.css','./theme.css','./theme-palette.css','./theme-accents.css','./manifest.webmanifest','./brand/fedo-mark.svg','./brand/fedo-symbol-dark.svg','./brand/fedo-logo-dark.svg','./icons/icon.svg','./icons/icon-192.png','./icons/icon-512.png','./icons/apple-touch-icon.png'];
self.addEventListener('install',event=>event.waitUntil(caches.open(CACHE).then(c=>c.addAll(ASSETS)).then(()=>self.skipWaiting())));
self.addEventListener('activate',event=>event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim())));
// الشبكة أولاً: أي تحديث بيوصل المستخدم فوراً، والكاش بيشتغل بس لو مفيش نت
self.addEventListener('fetch',event=>{
  const req=event.request;
  if(req.method!=='GET') return;
  const url=new URL(req.url);
  // لا نخزن طلبات Supabase (API/Auth)، ونخزن الشل المحلي بس
  if(url.origin!==self.location.origin) return;
  const key=req.mode==='navigate'?'./index.html':req;
  event.respondWith(fetch(req).then(r=>{if(r&&r.ok){const copy=r.clone();caches.open(CACHE).then(c=>c.put(key,copy))}return r}).catch(()=>caches.match(key)));
});
