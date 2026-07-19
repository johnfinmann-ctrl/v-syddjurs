/* ============================================================
   NORDIC MEDIA ENGINE — konfiguration for Venstre Syddjurs
   ============================================================
   Denne udgave kører kun med ÉN organisation (Venstre Syddjurs).
   Branding (navn/farver) hentes fra organizations-tabellen i
   Supabase — værdierne under "fallback" bruges kun hvis appen
   er offline ved allerførste besøg.
   ============================================================ */
window.NORDIC_CONFIG = {

  ORG_SLUG: "venstre-syddjurs",

  supabase: {
    url: "https://DIT-PROJEKT.supabase.co",
    anonKey: "DIN-ANON-KEY",
    vapidPublicKey: ""
  },

  fallback: {
    brand: { name: "Venstre Syddjurs", tagline: "Din fremtid. Dine valg." },
    colors: {
      primary: "#1D4ED8", primaryDeep: "#254264", secondary: "#FFFFFF",
      accent: "#17B26A", accent2: "#8B5CF6", accent3: "#F5487F", accent4: "#F5A524",
      mist: "#F3F5FA"
    }
  },

  nav: [
    { id: "home",     label: "Hjem",     icon: "home" },
    { id: "nyt",      label: "Nyt",      icon: "doc" },
    { id: "kalender", label: "Kalender", icon: "calendar" },
    { id: "video",    label: "Video",    icon: "play" },
    { id: "mere",     label: "Mere",     icon: "menu" }
  ],

  contact: {
    email: "syddjurs@venstre.dk",
    about: "Venstre Syddjurs — nyheder, holdninger og arrangementer op mod KV29."
  },

  features: {
    comments: true,
    likes: true,
    favorites: true,
    push: true,
    search: true,
    darkMode: true,
    realtime: true
  }
};
