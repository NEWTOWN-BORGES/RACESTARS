// Veículos desenhados em 2D com cel-shading + contorno estilo anime.

// Corredor terrestre visto por trás (2 turbinas laterais + cabine central)
function racerRear(ctx, x, y, s, o={}){
  const C = Object.assign({body:'#f4eee2', bodyS:'#9a98bf', red:'#e5483a', redS:'#8c3352', dark:'#272b47', darker:'#14162a', glow:'#7ff6ff', helmet:'#ff9d2e', line:'#1b1f3b', rim:'#fff3d6'}, o.colors||{});
  ctx.save(); ctx.translate(x,y);
  // sombra no chão (não gira com o veículo)
  ellipse(ctx, 0, s*0.72, s*1.3, s*0.16, 'rgba(25,40,50,0.32)');
  ellipse(ctx, 0, s*0.72, s*0.85, s*0.1, 'rgba(20,30,45,0.35)');
  ctx.rotate((o.roll||0)*DEG); ctx.scale(s,s);
  const LW=0.017; ctx.lineJoin='round'; ctx.lineCap='round';
  const out=(w=LW)=>{ctx.strokeStyle=C.line; ctx.lineWidth=w; ctx.stroke();};

  // aletas (atrás de tudo)
  for(const sd of [-1,1]){
    ctx.beginPath(); ctx.moveTo(sd*0.74,-0.12); ctx.quadraticCurveTo(sd*1.05,-0.32,sd*1.38,-0.62); ctx.lineTo(sd*1.30,-0.68); ctx.quadraticCurveTo(sd*0.9,-0.52,sd*0.56,-0.36); ctx.closePath();
    ctx.fillStyle=css(sd>0?C.red:C.redS); ctx.fill(); out();
    ctx.beginPath(); ctx.moveTo(sd*1.18,-0.52); ctx.lineTo(sd*1.38,-0.62); ctx.lineTo(sd*1.30,-0.68); ctx.lineTo(sd*1.10,-0.58); ctx.closePath(); ctx.fillStyle=css(C.body); ctx.fill(); out(0.016);
  }
  // turbinas laterais
  for(const sd of [-1,1]){
    const rx=sd*0.84, ry=0.2, fx=sd*0.56, fy=-0.62;
    capsule(ctx, rx, ry, 0.35, fx, fy, 0.13); ctx.fillStyle=css(C.body); ctx.fill();
    ctx.save(); capsule(ctx, rx, ry, 0.35, fx, fy, 0.13); ctx.clip();
    ellipse(ctx, rx-sd*0.05-0.2, ry+0.05, 0.36, 0.5, css(C.bodyS), -0.3);
    ctx.lineWidth=0.09; ctx.strokeStyle=css(C.red); ctx.beginPath(); ctx.moveTo(rx+0.02,ry-0.3); ctx.lineTo(fx+0.01,fy-0.08); ctx.stroke();
    ctx.restore();
    capsule(ctx, rx, ry, 0.35, fx, fy, 0.13); out();
    // aro superior iluminado
    ctx.beginPath(); ctx.arc(rx,ry,0.35,-2.2,-0.5); ctx.strokeStyle=css(C.rim,0.9); ctx.lineWidth=0.025; ctx.stroke();
    // face traseira
    ellipse(ctx, rx, ry+0.02, 0.33, 0.32, css(C.dark)); ctx.beginPath(); ctx.ellipse(rx,ry+0.02,0.33,0.32,0,0,TAU); out();
    ellipse(ctx, rx, ry+0.03, 0.25, 0.24, css(C.darker));
    ctx.beginPath(); ctx.ellipse(rx,ry+0.03,0.19,0.18,0,0,TAU); ctx.strokeStyle=css(C.glow); ctx.lineWidth=0.055; ctx.stroke();
    const g=ctx.createRadialGradient(rx,ry+0.03,0,rx,ry+0.03,0.16); g.addColorStop(0,'#ffffff'); g.addColorStop(0.5,css(C.glow)); g.addColorStop(1,css(C.glow,0.2));
    ellipse(ctx, rx, ry+0.03, 0.15, 0.14, g);
    for(let k=0;k<6;k++){ const a=k/6*TAU+0.3; ctx.beginPath(); ctx.moveTo(rx+Math.cos(a)*0.05,ry+0.03+Math.sin(a)*0.05); ctx.lineTo(rx+Math.cos(a)*0.15,ry+0.03+Math.sin(a)*0.14); ctx.strokeStyle='rgba(20,30,60,0.55)'; ctx.lineWidth=0.018; ctx.stroke(); }
  }
  // suportes
  for(const sd of [-1,1]){ ctx.beginPath(); ctx.moveTo(sd*0.3,0.0); ctx.lineTo(sd*0.56,0.06); ctx.strokeStyle=css(C.line); ctx.lineWidth=0.13; ctx.stroke(); ctx.strokeStyle=css(C.dark); ctx.lineWidth=0.08; ctx.stroke(); ctx.beginPath(); ctx.moveTo(sd*0.3,-0.02); ctx.lineTo(sd*0.56,0.03); ctx.strokeStyle=css(C.rim,0.5); ctx.lineWidth=0.02; ctx.stroke(); }
  // fuselagem
  capsule(ctx, 0, 0.04, 0.38, 0, -0.66, 0.12); ctx.fillStyle=css(C.red); ctx.fill();
  ctx.save(); capsule(ctx, 0, 0.04, 0.38, 0, -0.66, 0.12); ctx.clip();
  ellipse(ctx, -0.32, 0.05, 0.3, 0.7, css(C.redS), 0.2);
  ctx.lineWidth=0.08; ctx.strokeStyle=css(C.body); ctx.beginPath(); ctx.moveTo(0.1,-0.25); ctx.lineTo(0.04,-0.7); ctx.stroke();
  ctx.restore(); capsule(ctx, 0, 0.04, 0.38, 0, -0.66, 0.12); out();
  // cabine + piloto
  ellipse(ctx, 0, -0.3, 0.21, 0.18, css('#1d4558')); ctx.beginPath(); ctx.ellipse(0,-0.3,0.21,0.18,0,0,TAU); out(0.018);
  circle(ctx, 0, -0.28, 0.12, css(C.helmet)); ctx.save(); ctx.beginPath(); ctx.arc(0,-0.28,0.12,0,TAU); ctx.clip(); ellipse(ctx,-0.07,-0.25,0.1,0.14,css(shadowOf(C.helmet))); ctx.fillStyle=css(C.body); ctx.fillRect(-0.02,-0.42,0.04,0.3); ctx.restore();
  ctx.beginPath(); ctx.arc(0,-0.28,0.12,0,TAU); out(0.016);
  ctx.beginPath(); ctx.ellipse(0.06,-0.37,0.1,0.05,-0.4,0,TAU); ctx.fillStyle='rgba(255,255,255,0.55)'; ctx.fill();
  // traseira da fuselagem
  ellipse(ctx, 0, 0.1, 0.29, 0.24, css(C.dark)); ctx.beginPath(); ctx.ellipse(0,0.1,0.29,0.24,0,0,TAU); out();
  ctx.beginPath(); ctx.ellipse(0,0.11,0.12,0.1,0,0,TAU); ctx.strokeStyle=css(C.glow); ctx.lineWidth=0.04; ctx.stroke();
  ctx.beginPath(); ctx.arc(0,0.04,0.38,-2.0,-0.6); ctx.strokeStyle=css(C.rim,0.9); ctx.lineWidth=0.022; ctx.stroke();
  // número
  ctx.fillStyle=css(C.body); ctx.font='bold 0.16px sans-serif'; ctx.textAlign='center'; ctx.fillText('7',0,0.17);
  ctx.restore();
  // brilho dos motores (aditivo, sem rotação de escala)
  const ca=Math.cos((o.roll||0)*DEG), sa=Math.sin((o.roll||0)*DEG);
  for(const [lx,ly,r] of [[-0.84,0.22,1],[0.84,0.22,1],[0,0.11,0.5]]){ const gx=x+(lx*ca-ly*sa)*s, gy=y+(lx*sa+ly*ca)*s; glow(ctx,gx,gy,s*0.75*r,C.glow,0.55); glow(ctx,gx,gy,s*0.25*r,'#ffffff',0.6); }
}

// Hidroplanador (mar) visto por trás: dois flutuadores, cabine e vela-asa quadriculada
function hydroRear(ctx, x, y, s, o={}){
  const C = Object.assign({body:'#f6f2ea', bodyS:'#93a4c8', orange:'#ff8a3d', orangeS:'#b4506a', red:'#e43d3d', dark:'#23304e', glow:'#8ff7ff', line:'#1b2340', rim:'#ffffff', glass:'#1c4a62', helmet:'#ffd23f'}, o.colors||{});
  ctx.save(); ctx.translate(x,y); ctx.rotate((o.roll||0)*DEG); ctx.scale(s,s);
  const LW=0.017; ctx.lineJoin='round'; ctx.lineCap='round';
  const out=(w=LW)=>{ctx.strokeStyle=C.line; ctx.lineWidth=w; ctx.stroke();};
  // vela-asa (atrás)
  ctx.save();
  const sail=()=>{ ctx.beginPath(); ctx.moveTo(-0.06,-0.35); ctx.bezierCurveTo(-0.05,-1.0,0.05,-1.6,0.42,-2.15); ctx.bezierCurveTo(0.3,-1.6,0.26,-0.9,0.2,-0.32); ctx.closePath(); };
  sail(); ctx.fillStyle=css(C.body); ctx.fill(); ctx.save(); sail(); ctx.clip();
  for(let r=0;r<16;r++) for(let c=0;c<4;c++){ if((r+c)%2) continue; ctx.fillStyle=css(C.red); ctx.fillRect(-0.1+c*0.14,-2.2+r*0.14,0.14,0.14); }
  ctx.fillStyle='rgba(60,70,140,0.28)'; ctx.fillRect(-0.12,-2.3,0.16,2.1);
  ctx.restore(); sail(); out();
  ctx.restore();
  // braços e flutuadores
  for(const sd of [-1,1]){
    ctx.beginPath(); ctx.moveTo(sd*0.2,-0.05); ctx.quadraticCurveTo(sd*0.6,-0.25,sd*0.88,0.15); ctx.strokeStyle=css(C.line); ctx.lineWidth=0.11; ctx.stroke(); ctx.strokeStyle=css(C.body); ctx.lineWidth=0.065; ctx.stroke();
    const rx=sd*0.92, ry=0.36, fx=sd*0.74, fy=-0.25;
    capsule(ctx, rx, ry, 0.2, fx, fy, 0.08); ctx.fillStyle=css(C.orange); ctx.fill();
    ctx.save(); capsule(ctx, rx, ry, 0.2, fx, fy, 0.08); ctx.clip(); ellipse(ctx, rx+sd*0.12, ry, 0.16, 0.5, css(C.orangeS)); ctx.restore();
    capsule(ctx, rx, ry, 0.2, fx, fy, 0.08); out();
    ellipse(ctx, rx, ry+0.02, 0.17, 0.12, css(C.dark)); ctx.beginPath(); ctx.ellipse(rx,ry+0.02,0.17,0.12,0,0,TAU); out();
    ctx.beginPath(); ctx.ellipse(rx,ry+0.02,0.09,0.06,0,0,TAU); ctx.strokeStyle=css(C.glow); ctx.lineWidth=0.035; ctx.stroke();
  }
  // cabine central
  capsule(ctx, 0, 0.0, 0.3, 0, -0.62, 0.1); ctx.fillStyle=css(C.body); ctx.fill();
  ctx.save(); capsule(ctx, 0, 0.0, 0.3, 0, -0.62, 0.1); ctx.clip(); ellipse(ctx,0.25,0.05,0.25,0.6,css(C.bodyS)); ctx.fillStyle=css(C.orange); ctx.fillRect(-0.05,-0.8,0.1,0.9); ctx.restore();
  capsule(ctx, 0, 0.0, 0.3, 0, -0.62, 0.1); out();
  ellipse(ctx, 0, -0.27, 0.18, 0.15, css(C.glass)); ctx.beginPath(); ctx.ellipse(0,-0.27,0.18,0.15,0,0,TAU); out(0.014);
  circle(ctx, 0, -0.25, 0.1, css(C.helmet)); ctx.save(); ctx.beginPath(); ctx.arc(0,-0.25,0.1,0,TAU); ctx.clip(); ellipse(ctx,0.07,-0.22,0.08,0.12,css(shadowOf(C.helmet))); ctx.restore(); ctx.beginPath(); ctx.arc(0,-0.25,0.1,0,TAU); out(0.013);
  // cachecol ao vento
  ctx.beginPath(); ctx.moveTo(0.05,-0.18); ctx.bezierCurveTo(0.25,-0.2,0.35,-0.05,0.6,-0.12); ctx.bezierCurveTo(0.45,-0.0,0.3,-0.1,0.05,-0.13); ctx.closePath(); ctx.fillStyle=css(C.red); ctx.fill(); out(0.01);
  ellipse(ctx, 0, 0.06, 0.22, 0.17, css(C.dark)); ctx.beginPath(); ctx.ellipse(0,0.06,0.22,0.17,0,0,TAU); out();
  ctx.beginPath(); ctx.ellipse(0,0.07,0.1,0.07,0,0,TAU); ctx.strokeStyle=css(C.glow); ctx.lineWidth=0.035; ctx.stroke();
  ctx.beginPath(); ctx.arc(0,0,0.3,-2.3,-0.9); ctx.strokeStyle=css(C.rim,0.95); ctx.lineWidth=0.02; ctx.stroke();
  ctx.restore();
  const ca=Math.cos((o.roll||0)*DEG), sa=Math.sin((o.roll||0)*DEG);
  for(const [lx,ly,r] of [[-0.92,0.38,0.6],[0.92,0.38,0.6],[0,0.07,0.6]]){ const gx=x+(lx*ca-ly*sa)*s, gy=y+(lx*sa+ly*ca)*s; glow(ctx,gx,gy,s*0.6*r,C.glow,0.5); }
}

// Planador (ar) visto por trás e de cima: asa voadora branca com piloto deitado
function gliderRear(ctx, x, y, s, o={}){
  const C = Object.assign({wing:'#f7f1ea', wingS:'#a99ac4', under:'#7c6aa8', rim:'#ffd59a', red:'#e8463c', suit:'#2f8f9a', suitS:'#1f5e72', pants:'#2a5d6e', boot:'#2a2238', skin:'#f2b48a', line:'#231d3e', glow:'#ffe7a8'}, o.colors||{});
  ctx.save(); ctx.translate(x,y); ctx.rotate((o.roll||0)*DEG); ctx.scale(s,s);
  const LW=0.014; ctx.lineJoin='round'; ctx.lineCap='round';
  const out=(w=LW)=>{ctx.strokeStyle=C.line; ctx.lineWidth=w; ctx.stroke();};
  // asa: superfície de cima (fina) + bordo de fuga
  const wingTop=()=>{ ctx.beginPath(); ctx.moveTo(-1.75,-0.02); ctx.quadraticCurveTo(-0.9,-0.2,-0.18,-0.42); ctx.lineTo(0,-0.62); ctx.lineTo(0.18,-0.42); ctx.quadraticCurveTo(0.9,-0.2,1.75,-0.02); ctx.quadraticCurveTo(1.0,0.0,0.3,0.06); ctx.lineTo(0,0.1); ctx.lineTo(-0.3,0.06); ctx.quadraticCurveTo(-1.0,0.0,-1.75,-0.02); ctx.closePath(); };
  // espessura (lado de baixo/fuga em sombra)
  ctx.beginPath(); ctx.moveTo(-1.75,-0.02); ctx.quadraticCurveTo(-1.0,0.0,-0.3,0.06); ctx.lineTo(0,0.1); ctx.lineTo(0.3,0.06); ctx.quadraticCurveTo(1.0,0.0,1.75,-0.02); ctx.quadraticCurveTo(1.0,0.07,0.3,0.14); ctx.lineTo(0,0.19); ctx.lineTo(-0.3,0.14); ctx.quadraticCurveTo(-1.0,0.07,-1.75,-0.02); ctx.closePath(); ctx.fillStyle=css(C.under); ctx.fill(); out();
  wingTop(); ctx.fillStyle=css(C.wing); ctx.fill();
  ctx.save(); wingTop(); ctx.clip();
  ellipse(ctx,-0.9,0.02,0.9,0.12,css(C.wingS),0.1); ellipse(ctx,0.95,0.03,0.85,0.1,css(mix(C.wingS,C.wing,0.4)),-0.1);
  ctx.strokeStyle=css(C.rim); ctx.lineWidth=0.035; ctx.beginPath(); ctx.moveTo(-1.75,-0.03); ctx.quadraticCurveTo(-0.9,-0.21,-0.18,-0.43); ctx.lineTo(0,-0.63); ctx.lineTo(0.18,-0.43); ctx.quadraticCurveTo(0.9,-0.21,1.75,-0.03); ctx.stroke();
  for(const sd of [-1,1]){ ctx.fillStyle=css(C.red); ctx.beginPath(); ctx.moveTo(sd*1.75,-0.02); ctx.lineTo(sd*1.45,-0.08); ctx.lineTo(sd*1.4,0.02); ctx.closePath(); ctx.fill(); }
  ctx.strokeStyle='rgba(60,50,110,0.35)'; ctx.lineWidth=0.008; for(const k of [0.45,0.8,1.15]) for(const sd of [-1,1]){ ctx.beginPath(); ctx.moveTo(sd*k,-0.22+k*0.1); ctx.lineTo(sd*(k+0.05),0.03); ctx.stroke(); }
  ctx.restore(); wingTop(); out();
  // piloto deitado (visto por trás e de cima: botas, pernas encurtadas, costas, capacete)
  for(const sd of [-1,1]){ capsule(ctx,sd*0.055,-0.07,0.034,sd*0.05,-0.17,0.045); ctx.fillStyle=css(C.pants); ctx.fill(); out(0.009); ellipse(ctx,sd*0.06,-0.05,0.026,0.018,css('#4a3428')); }
  capsule(ctx,0,-0.2,0.105,0,-0.33,0.125); ctx.fillStyle=css(C.suit); ctx.fill();
  ctx.save(); capsule(ctx,0,-0.2,0.105,0,-0.33,0.125); ctx.clip(); ellipse(ctx,-0.09,-0.27,0.08,0.18,css(C.suitS)); ellipse(ctx,0.07,-0.36,0.06,0.05,css('#7fd0cf',0.6));
  ctx.strokeStyle='rgba(40,30,50,0.85)'; ctx.lineWidth=0.018; ctx.beginPath(); ctx.moveTo(-0.09,-0.36); ctx.lineTo(0.05,-0.17); ctx.moveTo(0.09,-0.36); ctx.lineTo(-0.05,-0.17); ctx.stroke(); ctx.restore();
  capsule(ctx,0,-0.2,0.105,0,-0.33,0.125); out(0.01);
  for(const sd of [-1,1]){ ctx.beginPath(); ctx.moveTo(sd*0.11,-0.38); ctx.lineTo(sd*0.085,-0.46); ctx.strokeStyle=css(C.line); ctx.lineWidth=0.06; ctx.stroke(); ctx.strokeStyle=css(C.suitS); ctx.lineWidth=0.042; ctx.stroke(); }
  ctx.beginPath(); ctx.moveTo(-0.13,-0.47); ctx.lineTo(0.13,-0.47); ctx.strokeStyle=css(C.line); ctx.lineWidth=0.02; ctx.stroke();
  circle(ctx,0,-0.42,0.068,css('#8a5a3a')); ctx.save(); ctx.beginPath(); ctx.arc(0,-0.42,0.068,0,TAU); ctx.clip(); ellipse(ctx,-0.04,-0.4,0.05,0.08,css('#5e3a2a')); ctx.fillStyle='#3a3550'; ctx.fillRect(-0.08,-0.425,0.16,0.022); ctx.restore(); ctx.beginPath(); ctx.arc(0,-0.42,0.068,0,TAU); out(0.009);
  // cachecol vermelho esvoaçando
  ctx.beginPath(); ctx.moveTo(0.03,-0.37); ctx.bezierCurveTo(0.2,-0.33,0.24,-0.18,0.42,-0.17); ctx.bezierCurveTo(0.6,-0.17,0.66,-0.04,0.86,-0.06); ctx.bezierCurveTo(0.7,0.03,0.58,-0.1,0.43,-0.09); ctx.bezierCurveTo(0.26,-0.08,0.2,-0.26,0.0,-0.33); ctx.closePath(); ctx.fillStyle=css(C.red); ctx.fill(); out(0.01);
  ctx.restore();
}

// Moto flutuante (floresta) vista por trás com piloto curvado
function hoverbikeRear(ctx, x, y, s, o={}){
  const C = Object.assign({body:'#3a2c62', bodyL:'#5d4a94', gold:'#ffc857', jacket:'#f0a03c', jacketS:'#9c4f4a', pants:'#25223e', helmet:'#f4f1ff', helmetS:'#9a94c8', glow:'#ff5fd2', rim:'#7ff6e6', line:'#120f26', hair:'#2e1b3a'}, o.colors||{});
  ctx.save(); ctx.translate(x,y);
  glow(ctx, 0, s*0.62, s*1.6, C.glow, 0.45); ellipse(ctx,0,s*0.62,s*0.9,s*0.12,css(C.glow,0.35));
  ctx.rotate((o.roll||0)*DEG); ctx.scale(s,s);
  const LW=0.016; ctx.lineJoin='round'; ctx.lineCap='round';
  const out=(w=LW)=>{ctx.strokeStyle=C.line; ctx.lineWidth=w; ctx.stroke();};
  // aletas laterais
  for(const sd of [-1,1]){ ctx.beginPath(); ctx.moveTo(sd*0.22,-0.04); ctx.lineTo(sd*0.55,-0.22); ctx.lineTo(sd*0.54,-0.15); ctx.lineTo(sd*0.26,0.06); ctx.closePath(); ctx.fillStyle=css(C.bodyL); ctx.fill(); out(); ctx.beginPath(); ctx.moveTo(sd*0.28,-0.02); ctx.lineTo(sd*0.53,-0.18); ctx.strokeStyle=css(C.gold); ctx.lineWidth=0.018; ctx.stroke(); circle(ctx,sd*0.55,-0.19,0.022,css(C.glow)); }
  // corpo da moto
  capsule(ctx,0,0.02,0.3,0,-0.62,0.12); ctx.fillStyle=css(C.body); ctx.fill();
  ctx.save(); capsule(ctx,0,0.02,0.3,0,-0.62,0.12); ctx.clip(); ellipse(ctx,0.22,-0.1,0.18,0.6,css(C.bodyL)); ctx.restore();
  capsule(ctx,0,0.02,0.3,0,-0.62,0.12); out();
  // pernas
  for(const sd of [-1,1]){ capsule(ctx,sd*0.2,-0.3,0.075,sd*0.27,0.0,0.065); ctx.fillStyle=css(C.pants); ctx.fill(); out(0.012); ellipse(ctx,sd*0.28,0.04,0.07,0.05,css('#16142a')); }
  // tronco curvado
  capsule(ctx,0,-0.3,0.15,0,-0.5,0.19); ctx.fillStyle=css(C.jacket); ctx.fill();
  ctx.save(); capsule(ctx,0,-0.3,0.15,0,-0.5,0.19); ctx.clip(); ellipse(ctx,-0.13,-0.38,0.12,0.3,css(C.jacketS)); 
  ctx.beginPath(); ctx.arc(0,-0.5,0.19,-2.5,-0.6); ctx.strokeStyle=css(C.rim,0.9); ctx.lineWidth=0.03; ctx.stroke(); ctx.restore();
  capsule(ctx,0,-0.3,0.15,0,-0.5,0.19); out();
  for(const sd of [-1,1]){ ctx.beginPath(); ctx.moveTo(sd*0.16,-0.55); ctx.lineTo(sd*0.3,-0.6); ctx.strokeStyle=css(C.line); ctx.lineWidth=0.08; ctx.stroke(); ctx.strokeStyle=css(C.jacketS); ctx.lineWidth=0.055; ctx.stroke(); }
  // trança ao vento
  ctx.beginPath(); ctx.moveTo(0.02,-0.6); ctx.bezierCurveTo(0.15,-0.5,0.2,-0.35,0.38,-0.32); ctx.bezierCurveTo(0.5,-0.3,0.55,-0.2,0.66,-0.22); ctx.bezierCurveTo(0.55,-0.16,0.48,-0.24,0.37,-0.26); ctx.bezierCurveTo(0.2,-0.28,0.12,-0.45,0.0,-0.55); ctx.closePath(); ctx.fillStyle=css(C.hair); ctx.fill(); out(0.01);
  circle(ctx,0.66,-0.22,0.025,css(C.gold));
  // capacete
  circle(ctx,0,-0.63,0.11,css(C.helmet)); ctx.save(); ctx.beginPath(); ctx.arc(0,-0.63,0.11,0,TAU); ctx.clip(); ellipse(ctx,-0.07,-0.6,0.08,0.13,css(C.helmetS)); ctx.fillStyle=css(C.glow); ctx.fillRect(-0.012,-0.75,0.024,0.24); ctx.restore(); ctx.beginPath(); ctx.arc(0,-0.63,0.11,0,TAU); out(0.012);
  ctx.beginPath(); ctx.arc(0,-0.63,0.11,-2.4,-0.9); ctx.strokeStyle=css(C.rim,0.9); ctx.lineWidth=0.02; ctx.stroke();
  // propulsor traseiro
  ellipse(ctx,0,0.08,0.26,0.24,css('#1c1636')); ctx.beginPath(); ctx.ellipse(0,0.08,0.26,0.24,0,0,TAU); out();
  ctx.beginPath(); ctx.ellipse(0,0.08,0.18,0.165,0,0,TAU); ctx.strokeStyle=css(C.glow); ctx.lineWidth=0.05; ctx.stroke();
  const g=ctx.createRadialGradient(0,0.08,0,0,0.08,0.13); g.addColorStop(0,'#ffffff'); g.addColorStop(0.5,css(C.glow)); g.addColorStop(1,css(C.glow,0.1)); ellipse(ctx,0,0.08,0.13,0.12,g);
  ctx.beginPath(); ctx.ellipse(0,0.08,0.26,0.24,0,-2.6,-0.5); ctx.strokeStyle=css(C.gold); ctx.lineWidth=0.025; ctx.stroke();
  ctx.restore();
  glow(ctx, x, y+0.08*s, s*0.9, C.glow, 0.6); glow(ctx, x, y+0.08*s, s*0.25, '#ffffff', 0.6);
}
