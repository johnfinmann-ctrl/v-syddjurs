/* Venstre Syddjurs – minimal service worker (RC48.47)
   Formål: gør appen installerbar som selvstændig app (PWA).
   Bevidst INGEN caching af appens filer: indhold og versionsopdatering hentes altid direkte fra serveren,
   så den installerede app aldrig viser forældet indhold. Appens eget versionstjek (meta app-version)
   står for automatisk opdatering. */
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (event) {
  event.waitUntil(
    caches.keys()
      .then(function (keys) { return Promise.all(keys.map(function (k) { return caches.delete(k); })); }) // ryd gamle caches fra tidligere forsøg
      .then(function () { return self.clients.claim(); })
  );
});
// Handler findes (krav hos nogle browsere), men forespørgsler går uændret videre til netværket.
self.addEventListener('fetch', function () {});
