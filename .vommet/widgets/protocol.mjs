// Vommet: the host side of the Matrix widget API, as Vommet's Dart host
// speaks it (commet/lib/client/matrix/components/widgets/
// matrix_widget_message_handler.dart + matrix_widget_capabilities_manager.dart
// + capabilities/mx_capability_oidc.dart), for the widget checks in this
// directory. Keep it in step with those files: a widget passing here should
// mean it gets as far in the app.
//
// The host waits for the widget's supported_api_versions, answers it, then
// asks the widget for its capabilities; whatever comes back is granted (as a
// "privileged" runner would, plus the default set incl. m.oidc) and confirmed
// with notify_capabilities. get_openid answers {state: "request"} and then
// sends openid_credentials, as the app does after the user allows it.
//
// Every step reached is recorded in `steps`, so a check can say exactly where
// a widget stopped.

export const SUPPORTED_VERSIONS = [
  "0.0.1",
  "0.0.2",
  "org.matrix.msc2762",
  "org.matrix.msc2762_update_state",
  "org.matrix.msc2871",
  "org.matrix.msc2974",
  "org.matrix.msc4039",
  "town.robin.msc3846",
  "org.matrix.msc3819",
  "org.matrix.msc3869",
];

// MatrixWidgetCapabilitiesManager.defaultCapabilities
export const DEFAULT_CAPABILITIES = [
  "org.matrix.msc3869.read_relations",
  "org.matrix.msc4039.get_media_config",
  "org.matrix.msc2873.client_theme",
  "m.oidc",
];

// Capability prefixes the app can create (capabilityBuilders); anything else
// is rejected, as canCreateCapability does.
const KNOWN_PREFIXES = [
  "org.matrix.msc2762.receive.event",
  "org.matrix.msc2762.send.event",
  "org.matrix.msc4039.upload_file",
  "org.matrix.msc4039.download_file",
  "org.matrix.msc2762.send.state_event",
  "org.matrix.msc2762.receive.state_event",
  "org.matrix.msc3819.send.to_device",
  "org.matrix.msc3819.receive.to_device",
  "town.robin.msc3846.turn_servers",
  "org.matrix.msc4039.get_media_config",
  "m.oidc",
  "org.matrix.msc3869.read_relations",
  "org.matrix.msc2762.timeline",
  "org.matrix.msc2873.client_theme",
  "org.matrix.msc4157.update_delayed_event",
  "org.matrix.msc4157.send.delayed_event",
  "m.always_on_screen",
];

function known(cap) {
  const base = cap.split(":")[0].split("#")[0];
  return KNOWN_PREFIXES.includes(base);
}

export class FakeHost {
  /**
   * @param {object} o
   * @param {string} o.widgetId
   * @param {(msg: object) => void} o.send  delivers a message to the widget
   * @param {object} [o.openid]  the token get_openid hands out
   * @param {(s: string) => void} [o.log]
   */
  constructor({ widgetId, send, openid, log }) {
    this.widgetId = widgetId;
    this._send = send;
    this.openid = openid || {
      access_token: "nightly-fake-token",
      token_type: "Bearer",
      matrix_server_name: "example.org",
      expires_in: 3600,
    };
    this.log = log || (() => {});
    this.steps = new Set();
    this.granted = new Set();
    this.requested = [];
    this.fromWidget = [];
    this.waiters = new Map();
    this.stepWaiters = [];
    this.n = 0;
  }

  reach(step) {
    if (this.steps.has(step)) return;
    this.steps.add(step);
    this.log(`step: ${step}`);
    for (const w of this.stepWaiters.filter((w) => w.step === step)) w.resolve();
    this.stepWaiters = this.stepWaiters.filter((w) => w.step !== step);
  }

  /** Resolves once `step` is reached; rejects after `ms`. */
  waitFor(step, ms) {
    if (this.steps.has(step)) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const w = { step, resolve };
      this.stepWaiters.push(w);
      setTimeout(() => {
        if (!this.steps.has(step)) reject(new Error(`timed out waiting for ${step}`));
      }, ms);
    });
  }

  send(msg) {
    this.log(`host -> widget ${msg.api} ${msg.action}${msg.response ? " (response)" : ""}`);
    this._send(msg);
  }

  toWidget(action, data) {
    this.n += 1;
    const requestId = `widgetapi-${this.n}`;
    const msg = { api: "toWidget", widgetId: this.widgetId, requestId, action, data };
    const answered = new Promise((resolve) => this.waiters.set(requestId, resolve));
    this.send(msg);
    return answered;
  }

  respond(req, response, data) {
    // MatrixWidgetMessage.createResponse
    this.send({
      api: "fromWidget",
      widgetId: this.widgetId,
      requestId: req.requestId,
      action: req.action,
      data: data && Object.keys(data).length ? data : req.data,
      response: response || {},
    });
  }

  error(req, message) {
    this.respond(req, { error: { message } });
  }

  grant(caps) {
    const asked = Array.isArray(caps) ? caps.filter((c) => typeof c === "string") : [];
    this.requested.push(...asked);
    const allowed = [...DEFAULT_CAPABILITIES, ...asked.filter(known)];
    for (const c of allowed) this.granted.add(c);
    const approved = [...this.granted];
    if (!approved.includes("io.element.requires_client")) approved.push("io.element.requires_client");
    this.toWidget("notify_capabilities", { requested: asked, approved }).then(() =>
      this.reach("notify_capabilities answered"),
    );
    return allowed;
  }

  /** One message from the widget (already parsed). */
  async receive(msg) {
    if (!msg || typeof msg !== "object" || !msg.requestId || !msg.action) return;
    if (msg.api === "toWidget") {
      const w = this.waiters.get(msg.requestId);
      if (w) {
        this.waiters.delete(msg.requestId);
        w(msg);
      }
      return;
    }
    if (msg.api !== "fromWidget") return;
    if (msg.response !== undefined) return; // our own message echoed back
    this.fromWidget.push(msg.action);
    this.log(`widget -> host ${msg.action}`);
    this.reach(`asked ${msg.action}`);

    switch (msg.action) {
      case "supported_api_versions": {
        this.respond(msg, { supported_versions: SUPPORTED_VERSIONS });
        const r = await this.toWidget("capabilities", {});
        this.reach("capabilities answered");
        const caps = r && r.response && r.response.capabilities;
        this.grant(caps || []);
        return;
      }
      case "org.matrix.msc2974.request_capabilities": {
        const caps = (msg.data && msg.data.capabilities) || [];
        this.respond(msg, {}, { capabilities: this.grant(caps) });
        return;
      }
      case "get_openid": {
        if (!this.granted.has("m.oidc")) {
          this.error(msg, `Unhandled widget request ${msg.action}`);
          return;
        }
        this.respond(msg, { state: "request" });
        const r = await this.toWidget("openid_credentials", {
          state: "allowed",
          original_request_id: msg.requestId,
          ...this.openid,
        });
        if (r) this.reach("openid_credentials answered");
        return;
      }
      case "org.matrix.msc2876.read_events":
        // An empty room: the widget's own start-up, not room history, is checked.
        if (this.canRead(msg.data && msg.data.type)) this.respond(msg, { events: [] });
        else this.error(msg, "Rejected");
        return;
      case "send_event":
        this.respond(msg, { room_id: "!nightly:example.org", event_id: `$nightly-${Date.now()}` });
        return;
      default:
        // content_loaded and anything else nobody handles: the Dart host
        // answers "Unhandled widget request".
        this.error(msg, `Unhandled widget request ${msg.action}`);
    }
  }

  canRead(type) {
    return [...this.granted].some(
      (c) => c === `org.matrix.msc2762.receive.event:${type}` || c === `org.matrix.msc2762.receive.state_event:${type}`,
    );
  }
}

/**
 * The URL the app opens for a widget (matrix_widget_component.dart
 * openWidget): its replacements, then parentUrl and widgetId on the query.
 */
export function widgetUrl(template, { widgetId, userId, roomId, displayName, deviceId, baseUrl, theme }) {
  let url = encodeURI(template);
  const replacements = {
    $matrix_user_id: userId,
    $matrix_room_id: roomId,
    $matrix_display_name: displayName,
    "$org.matrix.msc3819.matrix_device_id": deviceId,
    "$org.matrix.msc4039.matrix_base_url": baseUrl,
    "$chat.commet.color_scheme": encodeURIComponent("{}"),
    "$org.matrix.msc2873.client_theme": theme,
    // AddWidgetDialog fills these when the widget is added.
    "$vommet.new_id": "nightly" + Math.random().toString(36).slice(2, 10),
    "$vommet.new_secret": Math.random().toString(36).slice(2, 14),
  };
  // Longest first, as no key may be a prefix of a longer one's match.
  for (const k of Object.keys(replacements).sort((a, b) => b.length - a.length)) url = url.split(k).join(replacements[k]);
  const u = new URL(url);
  u.searchParams.set("parentUrl", "commet://widget");
  u.searchParams.set("widgetId", widgetId);
  return u.toString();
}
