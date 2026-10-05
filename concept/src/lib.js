// Kit de pintura procedural: cores, ruído, formas com borda orgânica,
// nuvens em cel-shading, câmera de perspectiva simples e pós-processo.
let W = 1920, H = 1080;

function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}
let R = mulberry32(7);
function seed(s){ R = mulberry32(s); }
const rnd = (a=0,b=1)=>a+(b-a)*R();
const rndi = (a,b)=>Math.floor(rnd(a,b+1));
const pick = arr => arr[Math.floor(R()*arr.length)];
const lerp=(a,b,t)=>a+(b-a)*t;
const clamp=(x,a=0,b=1)=>Math.max(a,Math.min(b,x));
const smooth=t=>t*t*(3-2*t);
const TAU = Math.PI*2, DEG = Math.PI/180;

// ---------- ruído Perlin 2D ----------
const Noise = (function(){
  const p = new Uint8Array(512), r = mulberry32(1337), perm=[...Array(256).keys()];
  for(let i=255;i>0;i--){const j=Math.floor(r()*(i+1));[perm[i],perm[j]]=[perm[j],perm[i]];}
  for(let i=0;i<512;i++) p[i]=perm[i&255];
  const G=[[1,1],[-1,1],[1,-1],[-1,-1],[1,0],[-1,0],[0,1],[0,-1]];
  const fade=t=>t*t*t*(t*(t*6-15)+10);
  function n2(x,y){
    const xi=Math.floor(x), yi=Math.floor(y), X=xi&255, Y=yi&255; x-=xi; y-=yi;
    const u=fade(x), v=fade(y);
    const g=(h,dx,dy)=>{const q=G[h&7];return q[0]*dx+q[1]*dy;};
    const aa=p[p[X]+Y], ab=p[p[X]+Y+1], ba=p[p[X+1]+Y], bb=p[p[X+1]+Y+1];
    return lerp(lerp(g(aa,x,y),g(ba,x-1,y),u), lerp(g(ab,x,y-1),g(bb,x-1,y-1),u), v);
  }
  function fbm(x,y,oct=4){let s=0,a=0.5,f=1,n=0;for(let i=0;i<oct;i++){s+=a*n2(x*f,y*f);n+=a;a*=0.5;f*=2.03;}return s/n;}
  return {n2, fbm};
})();

// ---------- cores ----------
function rgb(h){ if(Array.isArray(h)) return h; h=h.replace('#',''); return [parseInt(h.substr(0,2),16),parseInt(h.substr(2,2),16),parseInt(h.substr(4,2),16)]; }
function mix(a,b,t){a=rgb(a);b=rgb(b);return [lerp(a[0],b[0],t),lerp(a[1],b[1],t),lerp(a[2],b[2],t)];}
function css(c,al=1){c=rgb(c);return `rgba(${c[0]|0},${c[1]|0},${c[2]|0},${al})`;}
function mul(c,k){c=rgb(c);return [c[0]*k,c[1]*k,c[2]*k];}
// sombra "de pintor": escurece e puxa para um tom frio
function shadowOf(c, tint='#5a5f9a', k=0.62, t=0.28){ return mix(mul(c,k), tint, t); }

// ---------- canvas ----------
function setup(w=W,h=H){ W=w; H=h; const cv=document.createElement('canvas'); cv.width=W; cv.height=H; document.body.style.margin='0'; document.body.style.background='#000'; document.body.appendChild(cv); return cv.getContext('2d'); }
function layer(){ const c=document.createElement('canvas'); c.width=W; c.height=H; return c.getContext('2d'); }
function copyOf(ctx){ const l=layer(); l.drawImage(ctx.canvas,0,0); return l; }

function pathPts(ctx, pts, closed=true){ ctx.beginPath(); ctx.moveTo(pts[0][0],pts[0][1]); for(let i=1;i<pts.length;i++) ctx.lineTo(pts[i][0],pts[i][1]); if(closed) ctx.closePath(); }
function poly(ctx, pts, fill, stroke, lw=1){ pathPts(ctx,pts,true); if(fill){ctx.fillStyle=fill;ctx.fill();} if(stroke){ctx.strokeStyle=stroke;ctx.lineWidth=lw;ctx.lineJoin='round';ctx.stroke();} }
// borda orgânica: subdivide arestas e desloca pela normal com ruído
function rough(pts, amp=4, step=8, freq=0.02, closed=true, ns=0){
  const out=[], n=pts.length, m=closed?n:n-1;
  for(let i=0;i<m;i++){
    const a=pts[i], b=pts[(i+1)%n], dx=b[0]-a[0], dy=b[1]-a[1], L=Math.hypot(dx,dy)||1;
    const k=Math.max(1,Math.ceil(L/step)), nx=-dy/L, ny=dx/L;
    for(let j=0;j<k;j++){ const t=j/k, x=a[0]+dx*t, y=a[1]+dy*t; const d=Noise.fbm(x*freq+ns, y*freq-ns*1.7, 3)*amp*2; out.push([x+nx*d, y+ny*d]); }
  }
  if(!closed) out.push(pts[n-1]);
  return out;
}
function blobPts(cx,cy,rx,ry,wob=0.12,n=72,ns=0,rot=0){
  const pts=[]; for(let i=0;i<n;i++){ const a=i/n*TAU; const k=1+wob*Noise.fbm(Math.cos(a)*1.3+ns, Math.sin(a)*1.3+ns*0.7, 3)*2;
    const x=Math.cos(a)*rx*k, y=Math.sin(a)*ry*k; pts.push([cx+x*Math.cos(rot)-y*Math.sin(rot), cy+x*Math.sin(rot)+y*Math.cos(rot)]); } return pts; }
function ellipse(ctx,x,y,rx,ry,fill,rot=0){ ctx.beginPath(); ctx.ellipse(x,y,Math.max(1e-4,rx),Math.max(1e-4,ry),rot,0,TAU); ctx.fillStyle=fill; ctx.fill(); }
function circle(ctx,x,y,r,fill){ ellipse(ctx,x,y,r,r,fill); }
// casco convexo de dois círculos (cápsula afunilada)
function capsule(ctx,x1,y1,r1,x2,y2,r2){
  const th=Math.atan2(y2-y1,x2-x1), d=Math.hypot(x2-x1,y2-y1), al=Math.acos(clamp((r1-r2)/d,-1,1));
  ctx.beginPath(); ctx.arc(x1,y1,r1,th+al,th+TAU-al); ctx.arc(x2,y2,r2,th-al,th+al); ctx.closePath();
}

function skyGrad(ctx, stops, y0=0, y1=H){ const g=ctx.createLinearGradient(0,y0,0,y1); stops.forEach(([t,c])=>g.addColorStop(t,css(c))); ctx.fillStyle=g; ctx.fillRect(0,0,W,H); }
function glow(ctx,x,y,r,c,a=1,op='lighter'){ ctx.save(); ctx.globalCompositeOperation=op; const g=ctx.createRadialGradient(x,y,0,x,y,r); g.addColorStop(0,css(c,a)); g.addColorStop(0.35,css(c,a*0.35)); g.addColorStop(1,css(c,0)); ctx.fillStyle=g; ctx.fillRect(x-r,y-r,2*r,2*r); ctx.restore(); }

// ---------- nuvem cúmulo em cel-shading (luz vinda de lx,ly) ----------
function cloud(ctx, x, y, w, h, o={}){
  const lit=o.lit||'#ffffff', mid=o.mid||'#e9eefa', shd=o.shd||'#b9c3e6', deep=o.deep||'#9aa6d6', lx=o.lx??0.5, ly=o.ly??-0.8, alpha=o.alpha??1;
  const puffs=[]; const n=o.n||Math.max(4,Math.round(w/(h*0.42)));
  for(let i=0;i<n;i++){ const t=n===1?0.5:i/(n-1); const bell=Math.sin(Math.PI*(0.08+0.84*t));
    const r=h*(0.22+0.42*bell)*rnd(0.75,1.15); puffs.push([x-w/2+w*t+rnd(-h*0.1,h*0.1), y-r*0.55-h*0.35*bell*rnd(0.6,1.1), r]); }
  const m=Math.round(n*0.6); for(let i=0;i<m;i++){ const t=rnd(0.2,0.8), bell=Math.sin(Math.PI*t); const r=h*(0.18+0.3*bell)*rnd(0.7,1.1); puffs.push([x-w/2+w*t, y-h*(0.45+0.5*bell)*rnd(0.8,1.15), r]); }
  const L=layer();
  const sil=()=>{ L.beginPath(); for(const [px,py,r] of puffs){ L.moveTo(px+r,py); L.arc(px,py,r,0,TAU);} };
  L.save(); L.beginPath(); L.rect(0,0,W,y); L.clip();
  sil(); L.fillStyle=css(deep); L.fill();
  L.save(); sil(); L.clip();
  // sombra suave de baixo
  const g=L.createLinearGradient(0,y-h*1.2,0,y); g.addColorStop(0,css(shd)); g.addColorStop(1,css(deep)); L.fillStyle=g; L.fillRect(x-w,y-h*2.5,w*2,h*2.6);
  L.beginPath(); for(const [px,py,r] of puffs){ const cx=px+lx*r*0.28, cy=py+ly*r*0.28, rr=r*0.86; L.moveTo(cx+rr,cy); L.arc(cx,cy,rr,0,TAU);} L.fillStyle=css(mid); L.fill();
  L.beginPath(); for(const [px,py,r] of puffs){ const cx=px+lx*r*0.5, cy=py+ly*r*0.5, rr=r*0.6; L.moveTo(cx+rr,cy); L.arc(cx,cy,rr,0,TAU);} L.fillStyle=css(lit); L.fill();
  L.restore(); L.restore();
  ctx.save(); ctx.globalAlpha=alpha; ctx.drawImage(L.canvas,0,0); ctx.restore();
}

// ---------- câmera de perspectiva ----------
function Camera(pos, pitchDeg=0, fovDeg=60, roll=0, cx=W/2, cy=H/2){
  const f=(H/2)/Math.tan(fovDeg*DEG/2), p=pitchDeg*DEG, cp=Math.cos(p), sp=Math.sin(p), cr=Math.cos(roll*DEG), sr=Math.sin(roll*DEG);
  return { f, pos, project(x,y,z){ const X=x-pos[0], Y=y-pos[1], Z=z-pos[2]; const yc=Y*cp+Z*sp, zc=-Y*sp+Z*cp; const xr=X*cr-yc*sr, yr=X*sr+yc*cr; const zz=Math.max(zc,0.05); return [cx+f*xr/zz, cy-f*yr/zz, zc]; } };
}

// ---------- pinceladas ----------
function strokes(ctx, n, fn){ for(let i=0;i<n;i++) fn(i); }
function birds(ctx, x, y, spread, n, size, col){ ctx.save(); ctx.strokeStyle=col; ctx.lineCap='round';
  for(let i=0;i<n;i++){ const bx=x+rnd(-spread,spread), by=y+rnd(-spread*0.4,spread*0.4), s=size*rnd(0.5,1.2), fl=rnd(-0.4,0.5);
    ctx.lineWidth=Math.max(1,s*0.22); ctx.beginPath(); ctx.moveTo(bx-s,by-s*fl); ctx.quadraticCurveTo(bx-s*0.4,by-s*0.5,bx,by); ctx.quadraticCurveTo(bx+s*0.4,by-s*0.5,bx+s,by-s*fl); ctx.stroke(); }
  ctx.restore(); }

// ---------- pós-processo ----------
function zoomBlur(ctx, cx, cy, strength=0.06, samples=12, r0=250, r1=1000){
  const src=copyOf(ctx), B=layer();
  for(let i=0;i<samples;i++){ const s=1+strength*i/samples; B.globalAlpha=1/(i+1); B.setTransform(s,0,0,s,cx*(1-s),cy*(1-s)); B.drawImage(src.canvas,0,0); }
  B.setTransform(1,0,0,1,0,0); B.globalAlpha=1; B.globalCompositeOperation='destination-in';
  const g=B.createRadialGradient(cx,cy,r0,cx,cy,r1); g.addColorStop(0,'rgba(0,0,0,0)'); g.addColorStop(1,'rgba(0,0,0,1)'); B.fillStyle=g; B.fillRect(0,0,W,H);
  ctx.drawImage(B.canvas,0,0);
}
function speedLines(ctx, cx, cy, n, r0, col='#ffffff', a=0.35){
  ctx.save(); ctx.lineCap='round';
  for(let i=0;i<n;i++){ const ang=rnd(0,TAU), d0=r0*rnd(1,1.6), len=rnd(120,420), lw=rnd(1,3.5);
    const x0=cx+Math.cos(ang)*d0, y0=cy+Math.sin(ang)*d0*0.75; const x1=cx+Math.cos(ang)*(d0+len), y1=cy+Math.sin(ang)*(d0+len)*0.75;
    const g=ctx.createLinearGradient(x0,y0,x1,y1); g.addColorStop(0,css(col,0)); g.addColorStop(1,css(col,a*rnd(0.4,1)));
    ctx.strokeStyle=g; ctx.lineWidth=lw; ctx.beginPath(); ctx.moveTo(x0,y0); ctx.lineTo(x1,y1); ctx.stroke(); }
  ctx.restore(); }
function finish(ctx, o={}){
  const grain=o.grain??9, paper=o.paper??10, vig=o.vignette??0.22, tint=o.tint||null;
  const id=ctx.getImageData(0,0,W,H), d=id.data, cx=W/2, cy=H/2, md=Math.hypot(cx,cy);
  for(let y=0;y<H;y++) for(let x=0;x<W;x++){
    const i=(y*W+x)*4; const pn=Noise.n2(x*0.006,y*0.006)*paper + Noise.n2(x*0.05+9,y*0.05)*paper*0.4; const g=(R()-0.5)*grain;
    const dd=Math.hypot(x-cx,y-cy)/md, v=1-vig*smooth(clamp((dd-0.35)/0.65));
    for(let c=0;c<3;c++){ let val=(d[i+c]+pn+g)*v; if(tint) val=lerp(val, val*tint[c]/255, 0.12); d[i+c]=clamp(val,0,255); }
  }
  ctx.putImageData(id,0,0);
}
