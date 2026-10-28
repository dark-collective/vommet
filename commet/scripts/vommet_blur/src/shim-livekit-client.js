// The processors only take getLogger from livekit-client; a no-op logger keeps
// the whole LiveKit JS SDK out of the bundle (Vommet's LiveKit is the Dart SDK).
const noop = () => {};
const logger = { trace: noop, debug: noop, info: noop, warn: console.warn, error: console.error, setLevel: noop, getLevel: () => 3 };
export function getLogger() { return logger; }
