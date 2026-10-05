// Renderiza uma página (canvas) em PNG com Chromium headless.
// Uso: node shot.mjs <arquivo.html[?params]> <saida.png> [largura] [altura]
let pw;
try { pw = await import('playwright'); } catch { pw = await import('/opt/node22/lib/node_modules/playwright/index.mjs'); }
const [,, file, out, w='1920', h='1080'] = process.argv;
const b = await pw.chromium.launch();
const p = await b.newPage({viewport:{width:+w,height:+h}});
p.on('pageerror', e=>console.log('pageerror:', e.message));
await p.goto(file.includes('://') ? file : 'file://' + process.cwd() + '/' + file);
await p.waitForFunction(()=>window.DONE, null, {timeout:240000});
await p.screenshot({path:out});
await b.close();
console.log('ok', out);
