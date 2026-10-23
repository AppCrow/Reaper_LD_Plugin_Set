/* Produktseiten: Hell/Dunkel, Sprachmenü, Galerie-Knöpfe, Großbild, Kauffenster, Kontaktformular. Nur eigener Server, außer lemon.js beim Klick auf „Kaufen“; merkt sich nur die Hell/Dunkel-Wahl für diesen Besuch (sessionStorage, Tobi 2026-10-03). */
(function () {
  var d = document.documentElement, skript = document.currentScript, b = document.getElementById('schalter-thema');
  function setze(t) { d.dataset.theme = t; if (b) b.setAttribute('aria-pressed', t === 'dunkel'); }
  setze(d.dataset.theme || 'dunkel');
  if (b) b.onclick = function () { var n = d.dataset.theme === 'hell' ? 'dunkel' : 'hell'; setze(n); try { sessionStorage.setItem('thema', n); } catch (e) {} };

  /* Sprachmenü (<details>, geht auch ohne Skript): schließt bei Klick daneben, mit Esc und
     wenn der Tastaturfokus das Menü verlässt (relatedTarget leer = Maus/Touch: das regelt der Klick) */
  var m = document.querySelector('.sprachwahl');
  if (m) {
    document.addEventListener('click', function (e) { if (m.open && !m.contains(e.target)) m.open = false; });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && m.open) { m.open = false; m.querySelector('summary').focus(); } });
    m.addEventListener('focusout', function (e) { if (m.open && e.relatedTarget && !m.contains(e.relatedTarget)) m.open = false; });
  }

  /* „Bewegung reduzieren“: kein weiches Scrollen, Video startet nicht von selbst */
  var ruhig = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;
  if (!ruhig) document.querySelectorAll('video[data-autoplay]').forEach(function (v) { var p = v.play(); if (p && p.catch) p.catch(function () {}); });

  /* Galerie: Zurück/Weiter blättern; am Anfang bzw. Ende deaktiviert (aria-disabled, damit der Fokus bleibt) */
  var g = document.getElementById('galerie-liste'), kn = document.querySelectorAll('[data-richtung]');
  function stand() {
    var max = g.scrollWidth - g.clientWidth;
    kn.forEach(function (k) { var aus = +k.dataset.richtung < 0 ? g.scrollLeft <= 1 : g.scrollLeft >= max - 1; k.setAttribute('aria-disabled', aus ? 'true' : 'false'); });
  }
  if (g) {
    kn.forEach(function (k) {
      k.onclick = function () { if (k.getAttribute('aria-disabled') === 'true') return; var f = g.querySelector('figure'), gap = parseFloat(getComputedStyle(g).columnGap) || 0; g.scrollBy({ left: (+k.dataset.richtung) * (f.offsetWidth + gap), behavior: ruhig ? 'auto' : 'smooth' }); };
    });
    g.addEventListener('scroll', stand, { passive: true });
    window.addEventListener('resize', stand);
    stand();
  }

  /* Nur Vorschau, greift nie auf *.appcrow.at: Links auf appcrow.at und die Produktseiten
     zeigen auf die Ordner der Lieferung (seite/, produkte/…), damit man lokal durchklicken kann. */
  if (skript && !/(^|\.)appcrow\.at$/.test(location.hostname)) {
    var L = new URL('../../../', skript.src).href, Z = { 'appcrow.at': 'seite/', 'binderdock.appcrow.at': 'produkte/binderdock/', 'mobula.appcrow.at': 'produkte/mobula/' };
    document.querySelectorAll('a[href^="https://"]').forEach(function (a) {
      var u = new URL(a.href), ziel = Z[u.hostname]; if (!ziel) return;
      var p = u.pathname.slice(1); if (!/\.[a-z0-9]+$/i.test(p)) p += (p && p.slice(-1) !== '/' ? '/' : '') + 'index.html';
      a.href = L + ziel + p + u.search + u.hash;
    });
  }

  /* Kaufen (Binderdock, Links mit data-kauffenster): Kauffenster von Lemon Squeezy über der Seite.
     lemon.js lädt erst beim Klick, vorher keine Verbindung zu Lemon. Neuer Tab (Cmd/Strg/Mittelklick),
     ohne Skript, wenn lemon.js nicht lädt oder das Fenster nach 15 s nicht steht: der normale Link. */
  var lemon, wache, zuletzt;
  function oeffne(a) {
    zuletzt = a; clearTimeout(wache);
    wache = setTimeout(function () { LemonSqueezy.Url.Close(); LemonSqueezy.Loader.Hide(); location.href = a.href; }, 15000);
    LemonSqueezy.Url.Open(a.href);
  }
  document.querySelectorAll('a[data-kauffenster]').forEach(function (a) {
    a.addEventListener('click', function (e) {
      if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button) return;
      e.preventDefault();
      if (window.LemonSqueezy) return oeffne(a);
      if (lemon) return;  // lädt schon
      lemon = document.createElement('script');
      lemon.src = 'https://assets.lemonsqueezy.com/lemon.js';
      lemon.onload = function () {
        if (!window.createLemonSqueezy) { location.href = a.href; return; }
        createLemonSqueezy();
        LemonSqueezy.Setup({ eventHandler: function (m) {  // nur Nachrichten aus dem Kauffenster
          if (m === 'mounted') { clearTimeout(wache); var i = document.querySelector('body > iframe[allow="payment"]'); if (i) i.focus(); }
          if (m === 'close') { clearTimeout(wache); if (zuletzt) zuletzt.focus(); }
        } });
        oeffne(a);
      };
      lemon.onerror = function () { lemon = null; location.href = a.href; };
      document.head.appendChild(lemon);
    });
  });

  /* Großbild (Tobi 2026-10-23): Klick, Tippen, Enter oder Leertaste auf ein Galerie-Bild zeigt es groß
     in einem <dialog> (Fokus bleibt darin, Esc schließt). Pfeiltasten, Knöpfe und Wischen blättern, X oder
     Klick daneben schließt, danach steht der Fokus auf dem zuletzt gezeigten Bild. Ohne Skript: keine Änderung. */
  var bilder = [];
  if (g) g.querySelectorAll('figure').forEach(function (fig) { var e = fig.querySelector('.geraet') || fig.querySelector('img.bild'); if (e) bilder.push(e); });
  function sichtbar(e) {  // Mobula: im Gerät liegen ein helles und ein dunkles Bild, gezeigt wird eins
    if (e.tagName === 'IMG') return e;
    var alle = e.querySelectorAll('img');
    for (var i = 0; i < alle.length; i++) if (getComputedStyle(alle[i]).display !== 'none') return alle[i];
    return alle[0];
  }
  function titel(e) { var h = e.closest('figure').querySelector('h3'); return h ? h.textContent : ''; }
  if (bilder.length && window.HTMLDialogElement) {
    var pfeil = kn.length ? kn[0].innerHTML : '', jetzt = 0, start = null, gewischt = false;
    var dlg = document.createElement('dialog');
    dlg.className = 'grossbild';
    dlg.setAttribute('aria-labelledby', 'grossbild-titel');
    dlg.innerHTML = '<button type="button" class="grossbild-zu"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg></button>'
      + '<figure><img alt=""><figcaption id="grossbild-titel" aria-live="polite"></figcaption></figure>'
      + '<button type="button" data-schritt="-1">' + pfeil + '</button><button type="button" data-schritt="1">' + pfeil + '</button>';
    var zu = dlg.querySelector('.grossbild-zu'), bildG = dlg.querySelector('img'), unter = dlg.querySelector('figcaption'), schritte = dlg.querySelectorAll('[data-schritt]');
    bildG.draggable = false;  // sonst zieht die Maus das Bild selbst (pointercancel), statt zu blättern
    zu.setAttribute('aria-label', g.dataset.schliessen || '×');
    schritte.forEach(function (k, i) {
      if (kn[i]) k.setAttribute('aria-label', kn[i].getAttribute('aria-label'));
      if (bilder.length < 2) k.hidden = true;
      k.onclick = function () { blaettern(+k.dataset.schritt); };
    });
    document.body.appendChild(dlg);
    function zeige(i) {
      var q = sichtbar(bilder[i]);
      jetzt = i;
      bildG.src = q.dataset.gross || q.currentSrc || q.src; bildG.alt = q.alt;
      unter.textContent = titel(bilder[i]);
      schritte[0].setAttribute('aria-disabled', i === 0 ? 'true' : 'false');
      schritte[1].setAttribute('aria-disabled', i === bilder.length - 1 ? 'true' : 'false');
    }
    function blaettern(s) { var n = jetzt + s; if (n >= 0 && n < bilder.length) zeige(n); }
    function auf(i) { zeige(i); d.classList.add('grossbild-offen'); dlg.showModal(); }
    bilder.forEach(function (e, i) {
      e.setAttribute('role', 'button'); e.tabIndex = 0; e.setAttribute('aria-haspopup', 'dialog');
      if (!sichtbar(e).alt) e.setAttribute('aria-label', titel(e));
      e.addEventListener('click', function () { auf(i); });
      e.addEventListener('keydown', function (ev) { if (ev.key === 'Enter' || ev.key === ' ') { ev.preventDefault(); auf(i); } });
    });
    zu.onclick = function () { dlg.close(); };
    dlg.addEventListener('close', function () { d.classList.remove('grossbild-offen'); bilder[jetzt].focus(); });
    dlg.addEventListener('keydown', function (ev) {
      if (ev.key === 'ArrowLeft') blaettern(-1); else if (ev.key === 'ArrowRight') blaettern(1); else return;
      ev.preventDefault();
    });
    // Wischen: waagrecht mehr als 50 px; der Klick, der danach noch kommen kann, schließt nicht
    dlg.addEventListener('pointerdown', function (ev) { start = ev.isPrimary ? [ev.clientX, ev.clientY] : null; });
    dlg.addEventListener('pointercancel', function () { start = null; });
    dlg.addEventListener('pointerup', function (ev) {
      if (!start) return;
      var dx = ev.clientX - start[0], dy = ev.clientY - start[1];
      start = null; gewischt = Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy);
      if (gewischt) blaettern(dx < 0 ? 1 : -1);
    });
    dlg.addEventListener('click', function (ev) {
      if (gewischt) { gewischt = false; return; }
      if (ev.target === dlg || ev.target === bildG.parentNode) dlg.close();
    });
  }

  var f = document.getElementById('formular');
  if (!f) return;
  /* Zeitnachweis: check = (elapsed * 7 + 13) % 9973, mindestens 4000 ms.
     Muss zu ZEIT_* im Kontakt-Kern passen (pruefen/kontakt-formel.js). */
  var T = JSON.parse(skript.dataset.texte || '{}');
  var t0 = Date.now(), st = document.getElementById('status'), btn = f.querySelector('button');
  function fill() { var e = Date.now() - t0; f.elements.elapsed.value = e; f.elements.check.value = (e * 7 + 13) % 9973; return e; }
  f.addEventListener('submit', function (ev) {
    ev.preventDefault();
    if (fill() < 4000) { st.textContent = T.warte; return; }
    btn.disabled = true; st.textContent = T.sendet;
    fetch(f.action, { method: 'POST', body: new FormData(f) }).then(function (r) {
      if (r.ok) { f.hidden = true; var x = document.getElementById('danke'); x.hidden = false; x.focus(); return; }
      return r.json().catch(function () { return {}; }).then(function (j) {
        st.textContent = r.status === 429 ? T.viele : j.error === 'keine_nachricht' ? T.leer : j.error === 'ungueltige_mail' ? T.mail : T.fehler;
      });
    }).catch(function () { st.textContent = T.fehler; }).then(function () { btn.disabled = false; });
  });
})();
