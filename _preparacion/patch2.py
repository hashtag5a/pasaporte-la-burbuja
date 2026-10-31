import sys
src='/home/claude/hashtag5a/pasaporte-la-burbuja/index.html'
s=open(src).read()
def rep(old,new,count=1):
    global s
    n=s.count(old); assert n==count,(old[:90],n); s=s.replace(old,new)
nc=open('/home/claude/newchar.js').read().rstrip('\n').replace('function charSvg(sp,o){','function charSvgNew(sp,o){',1)
# 1 personajes: se guardan los dos estilos y se elige según el diseño activo
rep('function charSvg(sp,o){','function charSvgOld(sp,o){')
THEMEJS=r"""
/* ---- ESTILO DE LA APP: «clásico» o «backstage» (nuevo). Lo elige el propietario en DISEÑO ---- */
function charSvg(sp,o){return THEME==='new'?charSvgNew(sp,o):charSvgOld(sp,o)}
var THEME=(function(){try{return localStorage.getItem('lb_theme')==='new'?'new':'classic'}catch(e){return 'classic'}})(),TH_PATH='games/app-theme.json';
try{document.body.classList.toggle('thNew',THEME==='new')}catch(e){}
function thApply(t){var old=THEME;THEME=t==='new'?'new':'classic';try{localStorage.setItem('lb_theme',THEME)}catch(e){}document.body.classList.toggle('thNew',THEME==='new');thMark();if(old!==THEME&&CUR==='chars'&&HOOKS.chars)HOOKS.chars()}
function thMark(){document.querySelectorAll('[data-th]').forEach(function(b){b.classList.toggle('on',b.dataset.th===THEME)})}
function thLoad(){if(!sb)return;fetch(pub(TH_PATH)+'?t='+Date.now(),{cache:'no-store'}).then(function(r){return r.ok?r.text():''}).then(function(t){var j=null;try{j=JSON.parse(t)}catch(e){}if(j&&j.theme)thApply(j.theme)}).catch(function(){})}
function thSet(t){setMsg('thMsg','Guardando…',true);var body=JSON.stringify({theme:t,at:new Date().toISOString()});
 function put(type){return sb.storage.from('assets').upload(TH_PATH,new Blob([body],{type:type}),{contentType:type,upsert:true}).then(function(r){if(r.error)throw r.error})}
 put('application/json').catch(function(){return put('text/plain')}).catch(function(){return put('image/png')})
 .then(function(){thApply(t);setMsg('thMsg',t==='new'?'Listo. Los clientes verán el diseño BACKSTAGE la próxima vez que abran la app.':'Listo. Los clientes verán el diseño CLÁSICO la próxima vez que abran la app.',true)})
 .catch(function(e){setMsg('thMsg','No se ha podido guardar: '+friendly(e))})}
HOOKS.designMenu=function(){thMark();setMsg('thMsg','')};
"""
i=s.find('\n\n/* ---- PROPIETARIO: lista de personajes'); assert i>0
s=s[:i]+'\n'+nc+'\n'+THEMEJS+s[i:]
rep("SET=r[1].data||null})}","SET=r[1].data||null;thLoad()})}")
# 2 menú DISEÑO: selector
rep("""<button onclick="go('doorBg')">🚪 FACHADA DE LA COLA</button><button class="secondary" onclick="go('admin')">VOLVER</button>""",
 """<button onclick="go('doorBg')">🚪 FACHADA DE LA COLA</button><p class="gsec">ESTILO DE LA APP</p><p class="small" style="margin:0 0 4px">Cambia los botones, los marcos y los muñecos de los juegos para todos los clientes. Puedes volver al otro cuando quieras.</p><div class="thPick"><button type="button" class="secondary" data-th="classic" onclick="thSet('classic')">CLÁSICO</button><button type="button" class="secondary" data-th="new" onclick="thSet('new')">BACKSTAGE</button></div><p class="small" id="thMsg" style="min-height:16px;text-align:center"></p><button class="secondary" onclick="go('admin')">VOLVER</button>""")
# 3 barman
rep("""'<div class="bmBoard" id="bmOffer">'""","""bmTenderHtml(g,rnd)+'<div class="bmBoard" id="bmOffer">'""")
rep("var free2=g.chars.filter(function(c){return!g.onBar[c.id]})","var free2=g.chars.filter(function(c){return!g.onBar[c.id]&&c.id!==g.tenderId})")
rep("charSvg(who?who.spec:chRandom(g.crnd),{ring:true})","charSvg(who?who.spec:chRandom(g.crnd),{ring:true,noLegs:true})")
rep("function bmNow(){","""function bmTenderHtml(g,rnd){g.tenderId=null;if(THEME!=='new')return '';var t=(g.chars||[]).filter(function(c){return c.grp==='staff'})[0];g.tenderId=t?t.id:null;
 return '<div class="bmTender">'+charSvg(t?t.spec:{skin:'#e0ac69',hair:1,hairC:'#2b1d14',beard:2,glasses:2,shirt:'#1d1d1d'},{apron:true,shaker:true,noLegs:true})+(t?'<div class="bmTag">'+esc(t.name)+'</div>':'')+'</div>'}
function bmNow(){""")
# 4 beat
rep("if(g.kind==='barman')song=loadChars().then(function(l){g.chars=l}).catch(function(){g.chars=[]}).then(function(){return null});",
    "var chp=loadChars().then(function(l){g.chars=l}).catch(function(){g.chars=[]});song=Promise.all([song,chp]).then(function(a){return a[0]});")
rep("h=Math.round(Math.min(window.innerHeight*.7,640,w*1.5))","h=Math.round(THEME==='new'?Math.min(window.innerHeight*.56,560,w*1.3):Math.min(window.innerHeight*.7,640,w*1.5))")
rep("""el.innerHTML='<div class="btStage\"""","""el.innerHTML=btBand(g)+'<div class="btStage\"""")
rep("function btLaneAt(x){","""/* La banda tocando en el escenario (diseño backstage): músicos de «Personajes» (grupo Músico) y, si faltan, inventados */
function btBand(g){if(THEME!=='new')return '';var r=seedRand('banda'+(g.o.game_id||'')),m=(g.chars||[]).filter(function(c){return c.grp==='musician'}).slice(0,3),ins=['guitar','mic','drums'],h='<div class="btBand"><b>★ EN DIRECTO ★</b>';
 for(var i=0;i<3;i++)h+=charSvg(m[i]?m[i].spec:chRandom(r),{inst:ins[i]});return h+'</div>'}
function btLaneAt(x){""")
old="""x.beginPath();x.arc(lx,ty,R*1.05,0,Math.PI*2);x.fillStyle=pr?hexA(LANE_COL[l],.45):'rgba(10,8,6,.75)';x.fill();x.lineWidth=3*dpr;x.strokeStyle=LANE_COL[l];x.stroke();
  x.beginPath();x.arc(lx,ty,R*.55,0,Math.PI*2);x.strokeStyle='rgba(255,255,255,.25)';x.lineWidth=1.5*dpr;x.stroke()}"""
new="""if(THEME==='new'){var C=LANE_COL[l],off=pr?3*dpr:0,TP=Math.PI*2;
  x.beginPath();x.arc(lx,ty+5*dpr,R*1.14,0,TP);x.fillStyle='#2a1e06';x.fill();
  var rg=x.createLinearGradient(0,ty-R,0,ty+R);rg.addColorStop(0,'#fff1c0');rg.addColorStop(.45,'#c7a84d');rg.addColorStop(1,'#6e5212');x.beginPath();x.arc(lx,ty+off*.6,R*1.14,0,TP);x.fillStyle=rg;x.fill();
  var dg=x.createRadialGradient(lx-R*.3,ty+off-R*.35,R*.08,lx,ty+off,R*.9);dg.addColorStop(0,'#ffffff');dg.addColorStop(.28,C);dg.addColorStop(1,shade(C,-.5));
  x.beginPath();x.arc(lx,ty+off,R*.86,0,TP);x.fillStyle=dg;if(pr){x.shadowColor=C;x.shadowBlur=22*dpr}x.fill();x.shadowBlur=0;if(!pr){x.fillStyle='rgba(0,0,0,.18)';x.fill()}
  x.beginPath();x.ellipse(lx-R*.2,ty+off-R*.42,R*.38,R*.16,-.3,0,TP);x.fillStyle='rgba(255,255,255,.55)';x.fill();continue}
  """+old
rep(old,new)
# 5 cupón: barra de progreso (solo se ve en backstage)
rep('<span class="cnt">0</span>/10 sellos</p>','<span class="cnt">0</span>/10 sellos</p><div class="stp" aria-hidden="true"><i id="stpBar"></i></div>')
rep("$('fullC').style.display=n>=10?'block':'none';","$('fullC').style.display=n>=10?'block':'none';if($('stpBar'))$('stpBar').style.width=Math.min(10,n)*10+'%';")
# 6 fuente y estilos
rep('<head>','<head><link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Oswald:wght@500;700&display=swap" rel="stylesheet">')
k=s.find('</style>');s=s[:k]+open('/home/claude/theme_scoped.css').read()+s[k:]
rep('2026.10.26-a','2026.10.31-a')
open(sys.argv[1],'w').write(s);print('ok',len(s))
