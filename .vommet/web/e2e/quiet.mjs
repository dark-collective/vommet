// matrix-js-sdk logs every crypto step at debug level; keep warnings and
// errors only. Imported before the SDK, which binds console methods early.
for (const k of ['log', 'debug', 'info', 'trace']) console[k] = () => {};
