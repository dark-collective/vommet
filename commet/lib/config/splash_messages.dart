import 'dart:math';

// Vommet: one of these is shown under the logo on the splash screen while the
// app loads. Plain strings on purpose: the splash is drawn before translations
// are loaded.
const List<String> splashMessages = [
  "Did you remember to enable telemetry?",
  "The Singularity is here, it's just distributed unevenly",
  "I'll finish Heyokë one of these days...",
  "A proud product of Nether!",
  "Did you know that in terms of male human and female Pokémon breeding, Vaporeon is the most--",
  "The cake is a lie",
  "The quieter you become the more you are able to hear",
  "Consent is a lie",
  "All programs are source available if you know assembly",
  "Somebody please hire me. No this is not a joke. My savings are almost dry...",
  "Still proudly plagiarizing our features from Discord!",
  "Help! They have me locked in a room and they're forcing me to write splash screen messages!",
  "If you can read this our app still isn't loading fast enough",
  "Wait for it...",
  "All your hard work will eventually pay off!",
  "You are not valid",
  "Everything lies in silence",
  "If anything just cannot go wrong, it will anyway",
  "Nature always sides with the hidden flaw",
  "Rest is good, but idleness is its brother",
  "Your luck is about to change",
  "Rice and beans are pretty much all you need",
  "Given enough eyeballs, all bugs are shallow",
  "[INSERT MEANINGLESS SPLASH SCREEN MESSAGE HERE]",
  "I wish AI wasn't destroying my job security",
  "Treat people as you'd like to be treated",
  "No Claude, I don't have a problem",
  "Be kind to strangers",
  "Humanity isn't something you can forfeit",
  "Art needs no justification",
  "Have you considered donating to the Commet developers?",
  "Matrix 2.0 will be here any day now...you'll see!",
  "I'd love to get some actual Dart developers to review our codebase",
  "Ask not what your country can do for you, but what you can do for your country",
  "I may not agree with what you say, but I'll die for your right to misquote Voltaire",
  "Surely OP will deliver, let's just wait...",
  "The Land Before Time V is the Citizen Kane of children's entertainment",
  "YOU'RE TEARING ME APART, LISA!",
  "If you haven't started listening to SomaFM yet, start",
  "Proudly made by clankers",
  "The Thing is the greatest horror film ever made. Fight me.",
  "Nicotine is a horrible drug, do better",
  "In a democracy people get the leaders they deserve, I think people deserve better than that",
  "Don't you like our post-human future? We have everything we ever wanted except a purpose.",
  "Tom Fox is my role model",
  "Anyone up for a game of Deadlock?",
  "You realize you can voice call with your Discord friends on this thing, right?",
  "Stop using matrix.org as your homeserver!",
  "\u2022 0:00 - \"Violent and illicit lifestyle\"\n"
      "\u2022 1:19 - \"No morals or spirituality\"\n"
      "\u2022 2:22 - \"Drug induced hallucinations\"\n"
      "\u2022 3:33 - \"Graphic sexual narratives\"",
];

String randomSplashMessage([Random? random]) =>
    splashMessages[(random ?? Random()).nextInt(splashMessages.length)];
