/* Dibujo de un personaje: estilo papel recortado (cabeza grande y redonda, ojos ovalados juntos, colores planos) */
function charSvg(sp,o){sp=sp||{};o=o||{};var d=chDefault();var S=chColor(sp.skin,d.skin),HC=chColor(sp.hairC,d.hairC),SH=chColor(sp.shirt,d.shirt),HT=chColor(sp.hatC,d.hatC),hv=+sp.hair||0,bd=+sp.beard||0,gl=+sp.glasses||0,ht=+sp.hat||0,tp=+sp.top||0,ex=+sp.expr||0;
 var K='#1b1410',sw=' stroke="'+K+'" stroke-width="1.4" stroke-linejoin="round"',SD=chShade(SH,-.28),PA='#2e3f63';
 var h='<svg viewBox="'+(o.crop?'6 0 68 66':'0 0 80 112')+'" class="cust ppr'+(o.cls?' '+o.cls:'')+'" aria-hidden="true">';
 /* pelo de detrás */
 if(hv===2)h+='<path d="M14 34 Q10 8 40 7 Q70 8 66 34 L70 76 Q40 84 10 76Z" fill="'+HC+'"'+sw+'/>';
 if(hv===7)h+='<path d="M14 34 Q11 8 40 7 Q69 8 66 34 L68 56 Q40 62 12 56Z" fill="'+HC+'"'+sw+'/>';
 if(hv===3)h+='<path d="M62 22 Q80 26 74 58 Q70 44 60 36Z" fill="'+HC+'"'+sw+'/>';
 /* piernas y pies */
 if(!o.noLegs)h+='<rect x="25" y="97" width="30" height="9" rx="2" fill="'+PA+'"'+sw+'/><ellipse cx="31" cy="107.5" rx="9" ry="4" fill="'+K+'"/><ellipse cx="49" cy="107.5" rx="9" ry="4" fill="'+K+'"/>';
 /* cuerpo */
 var body='M17 100 Q15 68 40 61 Q65 68 63 100Z';
 h+='<path d="'+body+'" fill="'+SH+'"'+sw+'/>';
 if(tp===1)h+='<path d="M32 62 L40 72 L48 62Z" fill="#f4f1e6"'+sw+'/><path d="M40 72 L40 99" stroke="'+K+'" stroke-width="1.1"/><circle cx="40" cy="80" r="1.3" fill="'+K+'"/><circle cx="40" cy="89" r="1.3" fill="'+K+'"/>';
 else if(tp===2)h+='<path d="M27 66 Q40 76 53 66" fill="none" stroke="'+SD+'" stroke-width="3"/><path d="M36 70 L35 80 M44 70 L45 80" stroke="#f4f1e6" stroke-width="1.4"/><path d="M28 92 Q40 96 52 92" fill="none" stroke="'+SD+'" stroke-width="2"/>';
 else h+='<path d="M33 62 Q40 68 47 62" fill="none" stroke="'+SD+'" stroke-width="2.4"/>';
 if(o.apron)h+='<path d="M28 70 L52 70 L55 100 L25 100Z" fill="#c7a84d"'+sw+'/><path d="M30 70 L36 63 M50 70 L44 63" stroke="#7d5f17" stroke-width="2"/><circle cx="40" cy="84" r="5" fill="#1d1606"/><text x="40" y="86" text-anchor="middle" font-size="4.4" font-weight="700" fill="#f6e7b0" font-family="Arial">LB</text>';
 /* brazos y manos (mitones) */
 if(o.shaker){h+='<path d="M20 74 Q24 66 33 60" stroke="'+SH+'" stroke-width="8" stroke-linecap="round" fill="none"/><path d="M60 74 Q57 66 47 60" stroke="'+SH+'" stroke-width="8" stroke-linecap="round" fill="none"/>'+
  '<g class="shk"><rect x="34" y="38" width="12" height="22" rx="4" fill="#d5dae1"'+sw+'/><rect x="36" y="33" width="8" height="6" rx="2" fill="#a7afba"'+sw+'/><path d="M36 44 L44 44" stroke="#fff" stroke-width="1.4" opacity=".8"/></g>'+
  '<circle cx="34" cy="58" r="5" fill="'+S+'"'+sw+'/><circle cx="46" cy="58" r="5" fill="'+S+'"'+sw+'/>'}
 else if(o.inst==='mic')h+='<path d="M19 76 L15 92" stroke="'+SH+'" stroke-width="8" stroke-linecap="round"/><circle cx="15" cy="94" r="5" fill="'+S+'"'+sw+'/><path d="M61 76 Q62 66 54 58" stroke="'+SH+'" stroke-width="8" stroke-linecap="round" fill="none"/><path d="M50 56 L58 112" stroke="#2b2b2b" stroke-width="2.2"/><ellipse cx="49" cy="53" rx="4" ry="5" fill="#555"'+sw+'/><circle cx="54" cy="58" r="5" fill="'+S+'"'+sw+'/>';
 else if(o.inst==='guitar')h+='<g transform="rotate(-24 40 84)"><rect x="40" y="81" width="34" height="5" fill="#6b4a2a"'+sw+'/><rect x="72" y="79.5" width="6" height="8" rx="1" fill="#3a2a1a"/><path d="M20 76 Q30 72 40 78 Q46 82 40 88 Q30 96 20 92 Q12 84 20 76Z" fill="#c0392b"'+sw+'/><circle cx="31" cy="83" r="3" fill="'+K+'"/></g><circle cx="25" cy="88" r="5" fill="'+S+'"'+sw+'/><circle cx="58" cy="74" r="5" fill="'+S+'"'+sw+'/>';
 else if(o.inst==='drums')h+='<path d="M20 74 L10 62" stroke="'+SH+'" stroke-width="8" stroke-linecap="round"/><path d="M60 74 L70 62" stroke="'+SH+'" stroke-width="8" stroke-linecap="round"/><circle cx="10" cy="60" r="5" fill="'+S+'"'+sw+'/><circle cx="70" cy="60" r="5" fill="'+S+'"'+sw+'/><path d="M10 60 L2 46 M70 60 L78 46" stroke="#d9b98a" stroke-width="2.4" stroke-linecap="round"/>';
 else if(o.wave)h+='<path d="M19 76 L15 92" stroke="'+SH+'" stroke-width="8" stroke-linecap="round"/><circle cx="15" cy="94" r="5" fill="'+S+'"'+sw+'/><path d="M61 74 L72 56" stroke="'+SH+'" stroke-width="8" stroke-linecap="round"/><circle cx="73" cy="53" r="5" fill="'+S+'"'+sw+'/>';
 else h+='<path d="M19 76 L15 92" stroke="'+SH+'" stroke-width="8" stroke-linecap="round"/><path d="M61 76 L65 92" stroke="'+SH+'" stroke-width="8" stroke-linecap="round"/><circle cx="15" cy="94" r="5" fill="'+S+'"'+sw+'/><circle cx="65" cy="94" r="5" fill="'+S+'"'+sw+'/>';
 /* cabeza */
 h+='<ellipse cx="40" cy="35" rx="27" ry="24" fill="'+S+'"'+sw+'/>';
 /* barba (debajo de la boca) */
 if(bd===1)h+='<path d="M15 38 Q17 58 40 59 Q63 58 65 38 Q60 50 40 51 Q20 50 15 38Z" fill="'+HC+'" opacity=".35"/>';
 if(bd===2)h+='<path d="M14.5 36 Q15 59 40 59.5 Q65 59 65.5 36 Q62 46 54 46 Q48 42 40 43 Q32 42 26 46 Q18 46 14.5 36Z" fill="'+HC+'"'+sw+'/>';
 /* ojos grandes y juntos */
 var ty=ex===1?33:32;
 h+='<ellipse cx="32" cy="'+ty+'" rx="8.6" ry="'+(ex===1?7.6:9.6)+'" fill="#fff"'+sw+' transform="rotate(-8 32 '+ty+')"/><ellipse cx="48" cy="'+ty+'" rx="8.6" ry="'+(ex===1?7.6:9.6)+'" fill="#fff"'+sw+' transform="rotate(8 48 '+ty+')"/>';
 h+='<circle cx="34.6" cy="'+(ty+1)+'" r="1.9" fill="'+K+'"/><circle cx="45.4" cy="'+(ty+1)+'" r="1.9" fill="'+K+'"/>';
 if(ex===1)h+='<path d="M24 24.5 L37 27 M56 24.5 L43 27" stroke="'+K+'" stroke-width="1.6" stroke-linecap="round"/>';
 /* boca */
 var my=bd===2?49.5:48;
 if(ex===2)h+='<path d="M34 '+(my-1)+' Q40 '+(my+9)+' 46 '+(my-1)+'Z" fill="#5a1414"'+sw+'/><path d="M35.6 '+(my-.4)+' L44.4 '+(my-.4)+'" stroke="#fff" stroke-width="1.3"/>';
 else if(ex===1)h+='<path d="M36 '+(my+.5)+' L44 '+(my+.5)+'" stroke="'+K+'" stroke-width="1.6" stroke-linecap="round"/>';
 else h+='<path d="M35 '+my+' Q40 '+(my+4.5)+' 45 '+my+'" fill="none" stroke="'+K+'" stroke-width="1.6" stroke-linecap="round"/>';
 if(bd===3)h+='<path d="M31 '+(my-3)+' Q36 '+(my-6.5)+' 40 '+(my-4)+' Q44 '+(my-6.5)+' 49 '+(my-3)+' Q44 '+(my-1.5)+' 40 '+(my-2.5)+' Q36 '+(my-1.5)+' 31 '+(my-3)+'Z" fill="'+HC+'"'+sw+'/>';
 if(bd===4)h+='<path d="M35.5 54 Q40 63 44.5 54 Q40 56 35.5 54Z" fill="'+HC+'"'+sw+'/>';
 /* pelo de delante */
 if(hv===1||hv===3||hv===5)h+='<path d="M13.5 31 Q13 9 40 9 Q67 9 66.5 31 Q60 18 50 18 Q46 22 40 19 Q30 21 22 19 Q16 22 13.5 31Z" fill="'+HC+'"'+sw+'/>';
 if(hv===2||hv===7)h+='<path d="M13.5 36 Q11 9 40 9 Q69 9 66.5 36 Q63 21 50 19 Q40 25 28 20 Q17 23 13.5 36Z" fill="'+HC+'"'+sw+'/>';
 if(hv===4){[[16,27],[20,17],[28,11],[37,8],[46,8],[54,11],[61,17],[65,27],[24,21],[33,15],[47,15],[57,21]].forEach(function(p){h+='<circle cx="'+p[0]+'" cy="'+p[1]+'" r="7" fill="'+HC+'"'+sw+'/>'});h+='<path d="M14 30 Q40 14 66 30 Q60 20 40 17 Q20 20 14 30Z" fill="'+HC+'"/>'}
 if(hv===5)h+='<circle cx="40" cy="6.5" r="7" fill="'+HC+'"'+sw+'/>';
 if(hv===6)h+='<path d="M31 16 L33 0 L37 11 L40 -1 L43 11 L47 0 L49 16 Q40 12 31 16Z" fill="'+HC+'"'+sw+'/>';
 if(hv===0&&!ht)h+='<path d="M28 15 Q34 12 39 13" stroke="#fff" stroke-width="2" opacity=".35" fill="none" stroke-linecap="round"/>';
 /* gafas */
 if(gl===1)h+='<g fill="none" stroke="'+K+'" stroke-width="2.2"><circle cx="32" cy="'+ty+'" r="10.2"/><circle cx="48" cy="'+ty+'" r="10.2"/></g>';
 if(gl===2)h+='<g fill="none" stroke="'+K+'" stroke-width="2.8"><rect x="21" y="'+(ty-9)+'" width="19" height="17" rx="3.5"/><rect x="40" y="'+(ty-9)+'" width="19" height="17" rx="3.5"/></g><path d="M21 '+(ty-4)+' L14 '+(ty-6)+' M59 '+(ty-4)+' L66 '+(ty-6)+'" stroke="'+K+'" stroke-width="2.4"/>';
 if(gl===3)h+='<g fill="#111" stroke="'+K+'" stroke-width="1.4"><rect x="21" y="'+(ty-8)+'" width="19" height="14" rx="5"/><rect x="40" y="'+(ty-8)+'" width="19" height="14" rx="5"/></g><path d="M24 '+(ty-4)+' L30 '+(ty-4)+' M43 '+(ty-4)+' L49 '+(ty-4)+'" stroke="rgba(255,255,255,.5)" stroke-width="1.4"/>';
 /* gorra / gorro / sombrero */
 if(ht===1)h+='<path d="M13 26 Q13 6 40 6 Q67 6 67 26Z" fill="'+HT+'"'+sw+'/><path d="M40 22 L74 23 Q77 27 72 28 L40 27Z" fill="'+chShade(HT,-.25)+'"'+sw+'/><circle cx="40" cy="7" r="2" fill="'+chShade(HT,-.3)+'"/>';
 if(ht===2)h+='<path d="M13.5 25 Q13 2 40 2 Q67 2 66.5 25Z" fill="'+HT+'"'+sw+'/><rect x="11.5" y="20" width="57" height="9" rx="4.5" fill="'+chShade(HT,-.22)+'"'+sw+'/><circle cx="40" cy="1.5" r="5" fill="'+chShade(HT,.3)+'"'+sw+'/>';
 if(ht===3)h+='<ellipse cx="40" cy="20" rx="33" ry="5.5" fill="'+chShade(HT,-.2)+'"'+sw+'/><path d="M24 19 Q23 0 40 0 Q57 0 56 19Z" fill="'+HT+'"'+sw+'/><rect x="24" y="13" width="32" height="4" fill="'+chShade(HT,-.45)+'"/>';
 if(o.ring)h+='<circle class="pat" cx="40" cy="35" r="21" transform="translate(40 35) scale(1.42) translate(-40 -35) rotate(-90 40 35)"/>';
 return h+'</svg>'}
