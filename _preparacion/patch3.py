# Portada: cartel del concierto del día (desde las 00:00) en lugar de la cola, y botón QUIZ con hora de inicio
import sys
s = open(sys.argv[1]).read()
def rep(old, new, count=1):
    global s
    n = s.count(old); assert n == count, (old[:90], n); s = s.replace(old, new)

# 1) Portada: hueco para el botón del quiz encima de la cola / cartel
rep('<button class="secondary" onclick="go(\'customer\')">CERRAR CUPÓN</button><div id="fanQ"></div></section>',
    '<button class="secondary" onclick="go(\'customer\')">CERRAR CUPÓN</button><div id="quizToday"></div><div id="fanQ"></div></section>')

# 2) Menú JUEGOS del propietario: nueva entrada QUIZ
rep('<button onclick="gameMenu(\'barman\')">🍸 EL BARMAN EXPRÉS</button>',
    '<button onclick="gameMenu(\'barman\')">🍸 EL BARMAN EXPRÉS</button><p class="gsec">QUIZ EN EL LOCAL</p><button onclick="go(\'quizDays\')">🧠 QUIZ · DÍAS Y HORA DE INICIO</button>')

# 3) Pantalla de gestión del quiz
rep('<section id="gameList" class="screen card">',
    '''<section id="quizDays" class="screen card"><h2>QUIZ · DÍAS Y HORA</h2><p class="small" style="margin-top:0">El día del quiz, desde las 00:00, los clientes ven en la portada un botón QUIZ con la hora de inicio.</p>
<div class="g2"><div><label class="gl1" for="qzDate">Día</label><input id="qzDate" type="date"></div><div><label class="gl1" for="qzTime">Empieza a las</label><input id="qzTime" type="time" value="21:30"></div></div>
<label class="gl1" for="qzTitle">Nombre (opcional)</label><input id="qzTitle" maxlength="50" placeholder="Ej.: Quiz de La Burbuja · Jornada 3">
<label class="gl1" for="qzLink">Enlace del quiz (opcional)</label><input id="qzLink" type="url" inputmode="url" placeholder="https://… (la app del organizador)">
<button onclick="qzAdd()">＋ AÑADIR DÍA DE QUIZ</button><p class="small" id="qzMsg" style="min-height:16px;text-align:center"></p><div id="qzList"></div><button class="secondary" onclick="go('games')">VOLVER</button></section><section id="gameList" class="screen card">''')

# 4) Estilos
CSS = """
/* ---- Portada: cartel del concierto del día y botón del quiz ---- */
.tdC{margin:16px 0 6px;text-align:center}
.tdC .tdT{margin:0;font:900 18px/1.1 Arial,sans-serif;letter-spacing:1.5px;background:var(--foil);-webkit-background-clip:text;background-clip:text;color:transparent;filter:drop-shadow(0 1px 0 rgba(0,0,0,.7))}
.tdC .tdS{margin:3px 0 10px;color:#e9dcb2;font-size:14px;font-weight:700}
.tdC .tdP{display:block;width:100%;padding:0;border:0;background:none;cursor:pointer;box-shadow:none;margin:0 0 10px}
.tdC .tdP img{display:block;width:100%;max-height:70vh;object-fit:contain;border-radius:14px;background:#000;box-shadow:0 0 0 1px rgba(246,231,176,.5),0 0 0 4px #14120e,0 0 0 5px rgba(199,168,77,.4),0 16px 36px rgba(0,0,0,.65)}
.tdC .tdP:active{transform:none}
.qzBtn{display:flex;flex-direction:column;align-items:center;gap:2px;line-height:1.15}
.qzBtn small{font-size:12px;letter-spacing:.5px;text-transform:none;opacity:.9}
.qzRow{display:flex;align-items:center;gap:8px;padding:8px 10px;border:1px solid #d9c592;border-radius:10px;margin:6px 0;background:#fff}
.qzRow div{flex:1;min-width:0}.qzRow b{display:block}.qzRow span{font-size:12px;color:#6b5d3f;word-break:break-all}
.qzRow button{width:auto;margin:0;padding:6px 10px;min-height:0;font-size:12px}
.qzRow.past{opacity:.55}
"""
k = s.find('</style>'); s = s[:k] + CSS + s[k:]

# 5) Lógica
JS = r"""
/* ============ PORTADA: CARTEL DEL CONCIERTO DE HOY · BOTÓN DEL QUIZ ============ */
/* El día de concierto (hora de Madrid, desde las 00:00) la portada enseña el cartel en lugar de la cola */
function todayConcerts(){var t=mdDay(Date.now());return (CONCERTS||[]).filter(function(x){return mdDay(x.starts_at)===t}).sort(function(a,b){return new Date(a.starts_at)-new Date(b.starts_at)})}
function hhmm(t){var d=new Date(t);try{return d.toLocaleTimeString('es-ES',{timeZone:'Europe/Madrid',hour:'2-digit',minute:'2-digit'})}catch(e){return p2(d.getHours())+':'+p2(d.getMinutes())}}
function renderTodayConcert(){var box=$('fanQ'),l=todayConcerts();if(!box||!l.length)return false;var h='';
 l.forEach(function(x){h+='<div class="tdC"><p class="tdT">HOY HAY CONCIERTO</p><p class="tdS">'+esc(x.title)+' · a las '+hhmm(x.starts_at)+'</p><button type="button" class="tdP" onclick="ccOpen(\''+esc(x.id)+'\')" aria-label="Ver el cartel de '+esc(x.title)+'"><img src="'+esc(pub(x.poster_path))+'" alt="Cartel del concierto de hoy: '+esc(x.title)+'"></button></div>'});
 box.innerHTML=h;return true}
var _renderFans=renderFans;
renderFans=function(f){if(renderTodayConcert())return;_renderFans(f)};

/* Días de quiz: los guarda el propietario en el almacenamiento (assets/games/quiz-days.json) */
var QZ_PATH='games/quiz-days.json',QZ=null,QZ_T=0;
function qzLoad(force){if(!sb)return Promise.resolve([]);if(!force&&QZ&&Date.now()-QZ_T<60000)return Promise.resolve(QZ);
 return fetch(pub(QZ_PATH)+'?t='+Date.now(),{cache:'no-store'}).then(function(r){return r.ok?r.json():{days:[]}}).catch(function(){return {days:[]}})
 .then(function(j){QZ=(j&&j.days)||[];QZ_T=Date.now();return QZ})}
function qzToday(){var t=mdDay(Date.now());return (QZ||[]).filter(function(q){return q.date===t}).sort(function(a,b){return a.time<b.time?-1:1})}
function qzStarted(q){var n=new Date();try{n=new Date(new Date().toLocaleString('en-US',{timeZone:'Europe/Madrid'}))}catch(e){}return p2(n.getHours())+':'+p2(n.getMinutes())>=q.time}
function renderQuizToday(){var box=$('quizToday');if(!box)return;var l=qzToday();
 box.innerHTML=l.map(function(q,i){var on=qzStarted(q);return '<button class="qzBtn" onclick="qzOpen('+i+')"><span>🧠 '+(on?'QUIZ EN MARCHA':'QUIZ HOY')+'</span><small>'+esc(q.title||'Quiz de La Burbuja')+' · '+(on?'desde las ':'empieza a las ')+esc(q.time)+'</small></button>'}).join('')}
function qzOpen(i){var q=qzToday()[i];if(!q)return;
 if(q.link&&/^https:\/\//i.test(q.link)){window.open(q.link,'_blank','noopener');return}
 toast((qzStarted(q)?'El quiz ya ha empezado (desde las ':'El quiz empieza a las ')+q.time+(qzStarted(q)?')':'')+' en La Burbuja. ¡Ven con tu equipo!',5000)}

/* Al abrir la portada: conciertos de hoy y quiz de hoy. Si la app sigue abierta al pasar las 00:00, se actualiza sola */
(function(){var hc=HOOKS.cover;HOOKS.cover=function(){if(hc)hc();
 loadConcerts(true).then(function(){if(CUR==='cover'&&!renderTodayConcert()&&FANS)_renderFans(FANS)});
 qzLoad().then(function(){if(CUR==='cover')renderQuizToday()})}})();
var TD_DAY=mdDay(Date.now());
setInterval(function(){var d=mdDay(Date.now());if(CUR!=='cover')return;if(d!==TD_DAY){TD_DAY=d;HOOKS.cover()}else renderQuizToday()},60000);
document.addEventListener('visibilitychange',function(){if(!document.hidden&&CUR==='cover'){TD_DAY=mdDay(Date.now());HOOKS.cover()}});

/* ---- PROPIETARIO: días de quiz ---- */
HOOKS.quizDays=function(){setMsg('qzMsg','');if(!$('qzDate').value)$('qzDate').value=mdDay(Date.now());$('qzList').innerHTML='<p class="small">Cargando…</p>';qzLoad(true).then(qzList)};
function qzList(){var t=mdDay(Date.now()),l=(QZ||[]).slice().sort(function(a,b){return (a.date+a.time)<(b.date+b.time)?-1:1});
 if(!l.length){$('qzList').innerHTML='<p class="small">Todavía no hay días de quiz.</p>';return}
 $('qzList').innerHTML=l.map(function(q){var past=q.date<t,dd=new Date(q.date+'T12:00:00');var f;try{f=dd.toLocaleDateString('es-ES',{weekday:'long',day:'numeric',month:'long'})}catch(e){f=q.date}
  return '<div class="qzRow'+(past?' past':'')+'"><div><b>'+esc(f)+' · '+esc(q.time)+(q.date===t?' · HOY':'')+'</b><span>'+esc(q.title||'Quiz de La Burbuja')+(q.link?' · '+esc(q.link):'')+'</span></div><button class="secondary" onclick="qzDel(\''+esc(q.id)+'\')">QUITAR</button></div>'}).join('')}
function qzSave(list,okMsg){setMsg('qzMsg','Guardando…',true);var t=mdDay(Date.now()-90*86400000);
 list=list.filter(function(q){return q.date>=t});
 var body=JSON.stringify({days:list,at:new Date().toISOString()});
 function put(type){return sb.storage.from('assets').upload(QZ_PATH,new Blob([body],{type:type}),{contentType:type,upsert:true}).then(function(r){if(r.error)throw r.error})}
 return put('application/json').catch(function(){return put('text/plain')}).catch(function(){return put('image/png')})
 .then(function(){QZ=list;QZ_T=Date.now();qzList();setMsg('qzMsg',okMsg,true)})
 .catch(function(e){setMsg('qzMsg','No se ha podido guardar: '+friendly(e))})}
function qzAdd(){var d=$('qzDate').value,h=$('qzTime').value,ti=$('qzTitle').value.trim(),ln=$('qzLink').value.trim();
 if(!/^\d{4}-\d{2}-\d{2}$/.test(d))return setMsg('qzMsg','Elige el día.');
 if(!/^\d{2}:\d{2}$/.test(h))return setMsg('qzMsg','Indica la hora de inicio.');
 if(d<mdDay(Date.now()))return setMsg('qzMsg','Ese día ya ha pasado.');
 if(ln&&!/^https:\/\/\S+$/i.test(ln))return setMsg('qzMsg','El enlace debe empezar por https://');
 qzLoad(true).then(function(l){l=l.slice();l.push({id:Date.now().toString(36)+Math.random().toString(36).slice(2,6),date:d,time:h,title:ti,link:ln});
  return qzSave(l,'Día de quiz añadido.')}).then(function(){$('qzTitle').value='';$('qzLink').value=''})}
function qzDel(id){qzLoad(true).then(function(l){return qzSave(l.filter(function(q){return q.id!==id}),'Día de quiz quitado.')})}
"""
k = s.rfind('</script>'); s = s[:k] + JS + s[k:]

rep("var OWNER_ONLY=['doorBg',", "var OWNER_ONLY=['quizDays','doorBg',")
rep('2026.10.31-a', '2026.11.26-a', 2)
open(sys.argv[1], 'w').write(s); print('ok', len(s))
