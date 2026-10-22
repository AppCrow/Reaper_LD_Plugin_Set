/* Produktseiten: Hell/Dunkel, Sprachmenü, Galerie-Knöpfe, Kauffenster, Kontaktformular. Nur eigener Server, außer lemon.js beim Klick auf „Kaufen“; merkt sich nur die Hell/Dunkel-Wahl für diesen Besuch (sessionStorage, Tobi 2026-10-03). */
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
