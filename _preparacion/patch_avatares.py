"""Avatares de los clientes (2026.11.11-a). Uso: python3 patch_avatares.py index.html"""
import sys
P = sys.argv[1]
s = open(P, encoding='utf-8').read()

def rep(old, new, count=1):
    global s
    n = s.count(old)
    if n != count:
        raise SystemExit('Esperaba %d de %r y hay %d' % (count, old[:80], n))
    s = s.replace(old, new)

# 0) versión
rep("2026.10.31-a", "2026.11.11-a", 2)

# 1) ropa nueva: jersey y camiseta de tirantes
rep("top:['Camiseta','Camisa','Sudadera']", "top:['Camiseta','Camisa','Sudadera','Jersey','Camiseta de tirantes']")

# 1a) estilo clásico
rep("""else if(tp===2)h+='<path d="M36 70 L35 82 M44 70 L45 82" stroke="#f4f1e6" stroke-width="1.3"/><path d="M26 98 Q40 104 54 98" fill="none" stroke="'+chShade(SH,-.3)+'" stroke-width="2"/>';
 else h+='<path d="M31 61 Q40 72 49 61" fill="none" stroke="rgba(0,0,0,.28)" stroke-width="3"/>';""",
"""else if(tp===2)h+='<path d="M36 70 L35 82 M44 70 L45 82" stroke="#f4f1e6" stroke-width="1.3"/><path d="M26 98 Q40 104 54 98" fill="none" stroke="'+chShade(SH,-.3)+'" stroke-width="2"/>';
 else if(tp===3){var JD=chShade(SH,-.3);h+='<path d="M30 62 Q40 73 50 62" fill="none" stroke="'+JD+'" stroke-width="5"/><path d="M30 62 Q40 73 50 62" fill="none" stroke="'+chShade(SH,.18)+'" stroke-width="1.4" stroke-dasharray="1.6 1.6"/><path d="M8 104 L72 104" stroke="'+JD+'" stroke-width="3"/><path d="M8 104 L72 104" stroke="'+chShade(SH,.18)+'" stroke-width="3" stroke-dasharray="1.4 2.2"/>';[28,40,52].forEach(function(x){h+='<path d="M'+x+' 76 l-3 4 3 4 -3 4 3 4 -3 4 3 4" fill="none" stroke="'+JD+'" stroke-width="1.3"/>'})}
 else if(tp===4)h+='<path d="M6 112 Q7 70 27 63.5 L30.5 70 Q19 80 18 112Z" fill="'+S+'"/><path d="M74 112 Q73 70 53 63.5 L49.5 70 Q61 80 62 112Z" fill="'+S+'"/><path d="M33 61.5 Q40 76 47 61.5Z" fill="'+S+'"/><path d="M30.5 70 Q19 80 18 112 M49.5 70 Q61 80 62 112" fill="none" stroke="rgba(0,0,0,.25)" stroke-width="1.4"/>';
 else h+='<path d="M31 61 Q40 72 49 61" fill="none" stroke="rgba(0,0,0,.28)" stroke-width="3"/>';""")

# 1b) estilo backstage (papel recortado)
rep("""else h+='<path d="M33 62 Q40 68 47 62" fill="none" stroke="'+SD+'" stroke-width="2.4"/>';
 if(o.apron)""",
"""else if(tp===3){h+='<path d="M30 63 Q40 74 50 63" fill="none" stroke="'+SD+'" stroke-width="5"/><path d="M30 63 Q40 74 50 63" fill="none" stroke="'+chShade(SH,.2)+'" stroke-width="1.5" stroke-dasharray="1.6 1.6"/><path d="M17.3 95 L62.7 95" stroke="'+SD+'" stroke-width="4"/><path d="M17.3 95 L62.7 95" stroke="'+chShade(SH,.2)+'" stroke-width="4" stroke-dasharray="1.4 2.2"/>';[31,40,49].forEach(function(x){h+='<path d="M'+x+' 74 l-2.5 3.5 2.5 3.5 -2.5 3.5 2.5 3.5" fill="none" stroke="'+SD+'" stroke-width="1.3"/>'})}
 else if(tp===4)h+='<path d="M17 100 Q15 70 29 63.5 L31.5 70 Q22 78 22.5 100Z" fill="'+S+'"'+sw+'/><path d="M63 100 Q65 70 51 63.5 L48.5 70 Q58 78 57.5 100Z" fill="'+S+'"'+sw+'/><path d="M33 62.5 Q40 75 47 62.5Z" fill="'+S+'"'+sw+'/>';
 else h+='<path d="M33 62 Q40 68 47 62" fill="none" stroke="'+SD+'" stroke-width="2.4"/>';
 if(o.apron)""")
# brazos del color de la piel con la camiseta de tirantes
i = s.find('function charSvgNew(')
j = s.find('/* cabeza */', i)
seg = s[i:j]
n = seg.count('stroke="\'+SH+\'" stroke-width="8"')
if n < 10:
    raise SystemExit('brazos: %d' % n)
seg = seg.replace('stroke="\'+SH+\'" stroke-width="8"', 'stroke="\'+ARM+\'" stroke-width="8"')
seg = seg.replace("PA='#2e3f63';", "PA='#2e3f63',ARM=tp===4?S:SH;", 1)
s = s[:i] + seg + s[j:]
# al azar también salen las prendas nuevas
rep("top:Math.floor(r()*3),expr:", "top:Math.floor(r()*5),expr:")

# 2) pantalla del cliente «MI AVATAR»
SCREEN = ('<section id="myAvatar" class="screen card"><h2>MI AVATAR</h2>'
 '<p class="small" style="margin-top:0">Así sales en los juegos de La Burbuja (como cliente en la barra de Barman Exprés) y en «La cola de La Burbuja».</p>'
 '<div class="chPrevBox"><div id="avPrev" class="chPrev"></div></div>'
 '<button type="button" class="secondary" onclick="avRandom()">🎲 AL AZAR</button>'
 '<label class="gl1">Piel</label><div class="chSw2" id="avSkinSw"></div>'
 '<div class="g2"><div><label class="gl1">Peinado</label><select id="av_hair" onchange="avSet(\'hair\',+this.value)"></select></div><div><label class="gl1">Barba</label><select id="av_beard" onchange="avSet(\'beard\',+this.value)"></select></div></div>'
 '<label class="gl1">Color del pelo y la barba</label><div class="chSw2" id="avHairSw"></div>'
 '<div class="g2"><div><label class="gl1">Gafas</label><select id="av_glasses" onchange="avSet(\'glasses\',+this.value)"></select></div><div><label class="gl1">Gorra o sombrero</label><select id="av_hat" onchange="avSet(\'hat\',+this.value)"></select></div></div>'
 '<div id="avHatRow"><label class="gl1">Color de la gorra o el sombrero</label><div class="chSw2" id="avHatSw"></div></div>'
 '<div class="g2"><div><label class="gl1">Ropa</label><select id="av_top" onchange="avSet(\'top\',+this.value)"></select></div><div><label class="gl1">Expresión</label><select id="av_expr" onchange="avSet(\'expr\',+this.value)"></select></div></div>'
 '<label class="gl1">Color de la ropa</label><div class="chSw2" id="avShirtSw"></div>'
 '<p id="avMsg" class="small" style="color:#b3261e;min-height:16px;margin:6px 0 0"></p>'
 '<button id="avSave" onclick="avSave()">GUARDAR MI AVATAR</button><button class="secondary" onclick="go(\'inside\')">VOLVER A MI CUPÓN</button></section>')
rep('<section id="prizes" class="screen card">', SCREEN + '<section id="prizes" class="screen card">')

# 3) botón debajo del cupón
rep("""h+=offerBtns()+'<button class="secondary" onclick="go(\\'prizes\\')">🏆 MIS PREMIOS</button>';""",
"""h+=offerBtns()+'<button class="secondary" onclick="go(\\'myAvatar\\')">'+(MYAV?'🎨 MI AVATAR':'🎨 CREA TU AVATAR')+'</button><button class="secondary" onclick="go(\\'prizes\\')">🏆 MIS PREMIOS</button>';""")
rep("""function syncGames(){if(MODE!=='customer'||!SESSION)return Promise.resolve();""",
"""function syncGames(){if(MODE!=='customer'||!SESSION)return Promise.resolve();avLoad();""")

# 4) lógica del avatar del cliente
JS = r"""
/* ============ MI AVATAR (cliente): solo opciones cerradas y colores de la paleta ============ */
var MYAV=null,MYAV_OK=false,AVED=null;
function avLoad(force){if(MODE!=='customer'||!SESSION||(MYAV_OK&&!force))return Promise.resolve(MYAV);
 return rpc('my_avatar').then(function(v){MYAV=v&&typeof v==='object'?v:null;MYAV_OK=true;renderGameBtns();return MYAV}).catch(function(){return MYAV})}
function avSwatches(id,list,key){$(id).innerHTML=list.map(function(c){return '<button type="button" class="sw" style="background:'+c+'" data-k="'+key+'" data-c="'+c+'" aria-label="'+c+'"></button>'}).join('')}
HOOKS.myAvatar=function(){setMsg('avMsg','');
 ['hair','beard','glasses','hat','top','expr'].forEach(function(k){$('av_'+k).innerHTML=CH_OPTS[k].map(function(t,i){return '<option value="'+i+'">'+t+'</option>'}).join('')});
 avSwatches('avSkinSw',CH_SKIN,'skin');avSwatches('avHairSw',CH_HAIRC,'hairC');avSwatches('avShirtSw',CH_SHIRT,'shirt');avSwatches('avHatSw',CH_SHIRT,'hatC');
 AVED=Object.assign(chDefault(),MYAV||{});avSync();
 avLoad().then(function(v){if(CUR==='myAvatar'&&v){AVED=Object.assign(chDefault(),v);avSync()}})};
function avSync(){['hair','beard','glasses','hat','top','expr'].forEach(function(k){$('av_'+k).value=String(AVED[k]||0)});$('avHatRow').style.display=+AVED.hat?'':'none';
 ['skin','hairC','shirt','hatC'].forEach(function(k){document.querySelectorAll('#myAvatar .sw[data-k="'+k+'"]').forEach(function(b){b.classList.toggle('on',b.dataset.c.toLowerCase()===String(AVED[k]).toLowerCase())})});
 $('avPrev').innerHTML=charSvg(AVED)}
function avSet(k,v){AVED[k]=v;avSync()}
function avRandom(){AVED=chRandom(Math.random);avSync()}
document.addEventListener('click',function(e){var b=e.target.closest&&e.target.closest('#myAvatar .sw');if(b)avSet(b.dataset.k,b.dataset.c)});
function avSave(){var b=$('avSave');b.disabled=true;setMsg('avMsg','Guardando…',true);
 rpc('set_my_avatar',{p_spec:AVED}).then(function(v){MYAV=v;MYAV_OK=true;FANS=null;toast('¡Avatar guardado! Ya sales así en los juegos.');go('inside')})
 .catch(function(e){setMsg('avMsg',friendly(e))}).then(function(){b.disabled=false})}
/* Juegos: personajes del local + avatares de los clientes (el tuyo sale con «Tú») */
function gameChars(){return Promise.all([loadChars().catch(function(){return[]}),rpc('game_avatars').catch(function(){return null})]).then(function(a){var l=a[0]||[],v=a[1]||{};
 (v.others||[]).forEach(function(sp,i){if(sp&&typeof sp==='object')l.push({id:'av'+i,name:'',grp:'regular',spec:sp})});
 if(v.me&&typeof v.me==='object')l.push({id:'me',name:'Tú',grp:'regular',spec:v.me,me:true});return l})}
"""
rep("\n/* ============ LA COLA DE LA BURBUJA (portada)", JS + "\n/* ============ LA COLA DE LA BURBUJA (portada)")

# 5) Barman: usa también los avatares; el tuyo sale más a menudo
rep("var chp=loadChars().then(function(l){g.chars=l}).catch(function(){g.chars=[]});",
    "var chp=gameChars().then(function(l){g.chars=l}).catch(function(){g.chars=[]});")
rep("""var free2=g.chars.filter(function(c){return!g.onBar[c.id]&&c.id!==g.tenderId}),who=free2.length&&g.crnd()<.7?free2[Math.floor(g.crnd()*free2.length)]:null;""",
    """var free2=g.chars.filter(function(c){return!g.onBar[c.id]&&c.id!==g.tenderId}),mine=free2.filter(function(c){return c.me})[0],who=mine&&g.crnd()<.18?mine:(free2.length&&g.crnd()<.7?free2[Math.floor(g.crnd()*free2.length)]:null);""")
rep("""charSvg(who?who.spec:chRandom(g.crnd),{ring:true,noLegs:true})+(who?'<div class="bmTag">'+esc(who.name)+'</div>':'')""",
    """charSvg(who?who.spec:chRandom(g.crnd),{ring:true,noLegs:true})+(who&&who.name?'<div class="bmTag'+(who.me?' me':'')+'">'+esc(who.name)+'</div>':'')""")

# 6) La cola: cada uno con su avatar
rep("charSvg(chRandom(seedRand(p.seed)))", "charSvg(p.av&&typeof p.av==='object'?p.av:chRandom(seedRand(p.seed)))")

# 7) copia de seguridad y restauración
rep("fetchAll('characters','id')]).then(function(r){", "fetchAll('characters','id'),fetchAll('avatars','email').catch(function(){return[]})]).then(function(r){")
rep("ticket_orders:r[14],characters:r[15]}})}", "ticket_orders:r[14],characters:r[15],avatars:r[16]}})}")
rep("ticket_orders:d.ticket_orders,characters:d.characters,files:{}", "ticket_orders:d.ticket_orders,characters:d.characters,avatars:d.avatars,files:{}")
rep("return chunked('characters',B.characters||[],500)})", "return chunked('characters',B.characters||[],500)}).then(function(){var A=B.avatars||[],k=0;function nx(){if(k>=A.length)return;var part=A.slice(k,k+500);k+=500;return rpc('restore_avatars',{p_rows:part}).then(nx)}return nx()})")

# 8) mensajes y estilos
rep("if(l.indexOf('char_name_required')>-1)return 'Escribe el nombre del personaje.';",
    "if(l.indexOf('char_name_required')>-1)return 'Escribe el nombre del personaje.';\n if(l.indexOf('bad_avatar')>-1)return 'Ese avatar no es válido.';")
rep(".chSw2 .swc{", ".bmTag.me{background:linear-gradient(180deg,#f6e7b0,#b38f32);color:#1d1606;border-color:#fff4d1}\n#myAvatar .chPrev{width:170px;height:236px}\n.chSw2 .swc{")

open(P, 'w', encoding='utf-8').write(s)
print('OK', len(s))
