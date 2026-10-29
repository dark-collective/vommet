// Keeps the Getting started tour's offer card (Vommet issue 758) out of the
// tests: it shows after the first sign-in and sits over the composer, so the
// send and edit flows can't reach it. The app's preferences live in
// localStorage ("flutter." + key, JSON values); marking the offer as already
// made means the sign-in never queues it. Users still get the offer.
export async function skipTour(context) {
  await context.addInitScript(() => {
    try {
      localStorage.setItem('flutter.vommet_getting_started_offered', 'true');
      localStorage.setItem('flutter.vommet_tour_offer_pending', 'false');
    } catch {}
  });
}
