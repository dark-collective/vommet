// Keeps the Getting started tour's offer card (Vommet issue 758) out of the
// tests: it shows after the first sign-in and sits over the composer, so the
// send and edit flows can't reach it. The app's preferences live in
// localStorage ("flutter." + key, JSON values); marking the offer as already
// made means the sign-in never queues it. Users still get the offer.
//
// The same goes for the web app's "Turn on notifications?" dialog (Vommet
// issue 767): it shows after sign-in wherever the browser's permission is
// still "default" (Firefox here; Chromium reports "denied") and covers the
// room list. Marking it as asked keeps it away; users still get it.
export async function skipTour(context) {
  await context.addInitScript(() => {
    try {
      localStorage.setItem('flutter.vommet_getting_started_offered', 'true');
      localStorage.setItem('flutter.vommet_tour_offer_pending', 'false');
      localStorage.setItem('flutter.vommet_web_notifications_asked', 'true');
    } catch {}
  });
}
