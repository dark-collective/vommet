// A second device of the test user, as a plain Matrix client in Node
// (matrix-js-sdk with its Rust crypto, in memory). It sets up the account's
// cross-signing, recovery key and key backup the way another app would, sends
// and reads encrypted messages, and reports how the server sees the web
// device. Nothing here touches the app under test.
import './quiet.mjs';
import * as sdk from 'matrix-js-sdk';
import { CryptoEvent, VerifierEvent, VerificationPhase } from 'matrix-js-sdk/lib/crypto-api/index.js';

export async function register(hs, username, password) {
  const r = await fetch(`${hs}/_matrix/client/v3/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password, auth: { type: 'm.login.dummy' }, inhibit_login: true }),
  });
  if (!r.ok) throw new Error(`register ${username}: ${r.status} ${await r.text()}`);
  return (await r.json()).user_id;
}

const waitFor = async (what, fn, ms = 60000) => {
  const end = Date.now() + ms;
  for (;;) {
    const v = await fn();
    if (v) return v;
    if (Date.now() > end) throw new Error(`timed out waiting for ${what}`);
    await new Promise((r) => setTimeout(r, 250));
  }
};

export class OtherDevice {
  static async login(hs, user, password, name = 'E2E other device') {
    const tmp = sdk.createClient({ baseUrl: hs });
    const res = await tmp.loginRequest({
      type: 'm.login.password',
      identifier: { type: 'm.id.user', user },
      password,
      initial_device_display_name: name,
    });
    const d = new OtherDevice(hs, res, password);
    await d.start();
    return d;
  }

  constructor(hs, login, password) {
    this.hs = hs;
    this.userId = login.user_id;
    this.deviceId = login.device_id;
    this.token = login.access_token;
    this.password = password;
    this.secretKey = null;
    this.client = sdk.createClient({
      baseUrl: hs,
      userId: this.userId,
      deviceId: this.deviceId,
      accessToken: this.token,
      // Emoji only: the web app is approved the way a person would do it.
      verificationMethods: ['m.sas.v1'],
      cryptoCallbacks: {
        getSecretStorageKey: async ({ keys }) => {
          const id = Object.keys(keys)[0];
          return this.secretKey ? [id, this.secretKey] : null;
        },
        cacheSecretStorageKey: (_id, _info, key) => { this.secretKey = key; },
      },
    });
  }

  async start() {
    await this.client.initRustCrypto({ useIndexedDB: false });
    const ready = new Promise((resolve) => {
      this.client.on(sdk.ClientEvent.Sync, (state) => { if (state === 'PREPARED') resolve(); });
    });
    await this.client.startClient({ initialSyncLimit: 20 });
    await ready;
  }

  get crypto() { return this.client.getCrypto(); }

  async api(method, path, body) {
    const r = await fetch(`${this.hs}/_matrix/client/v3${path}`, {
      method,
      headers: { Authorization: `Bearer ${this.token}`, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await r.text();
    if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${text}`);
    return text ? JSON.parse(text) : {};
  }

  /// Cross-signing + secret storage + a new key backup; returns the recovery
  /// key as a user would type it.
  async setUpSecureMessaging() {
    const key = await this.crypto.createRecoveryKeyFromPassphrase();
    this.secretKey = key.privateKey;
    await this.crypto.bootstrapCrossSigning({
      setupNewCrossSigning: true,
      authUploadDeviceSigningKeys: async (makeRequest) => {
        try {
          await makeRequest(null);
        } catch (e) {
          const session = e?.data?.session;
          if (!session) throw e;
          await makeRequest({
            type: 'm.login.password',
            identifier: { type: 'm.id.user', user: this.userId },
            password: this.password,
            session,
          });
        }
      },
    });
    await this.crypto.bootstrapSecretStorage({
      createSecretStorageKey: async () => key,
      setupNewSecretStorage: true,
      setupNewKeyBackup: true,
    });
    await waitFor('key backup', async () => (await this.crypto.getActiveSessionBackupVersion()) != null);
    return key.encodedPrivateKey;
  }

  async createEncryptedRoom(name) {
    const { room_id: roomId } = await this.client.createRoom({
      name,
      initial_state: [{ type: 'm.room.encryption', state_key: '', content: { algorithm: 'm.megolm.v1.aes-sha2' } }],
    });
    await waitFor('room in sync', async () => this.client.getRoom(roomId)?.hasEncryptionStateEvent());
    return roomId;
  }

  async send(roomId, body) {
    const { event_id: eventId } = await this.client.sendTextMessage(roomId, body);
    return eventId;
  }

  /// Waits until every megolm session this device made is in the backup.
  async waitBackedUp() {
    await waitFor('keys in backup', async () => {
      const v = await this.crypto.getActiveSessionBackupVersion();
      if (!v) return false;
      const keys = await this.api('GET', `/room_keys/keys?version=${encodeURIComponent(v)}`);
      const sessions = Object.values(keys.rooms ?? {}).reduce((n, r) => n + Object.keys(r.sessions ?? {}).length, 0);
      return sessions > 0 && (await this.crypto.getKeyBackupInfo()) != null;
    }, 90000);
  }

  /// A decrypted message with [body] in [roomId], sent by another device.
  async waitMessage(roomId, body, ms = 90000) {
    const events = () => this.client.getRoom(roomId)?.getLiveTimeline().getEvents() ?? [];
    try {
      return await waitFor(`message "${body}"`, async () =>
        events().find((ev) => !ev.isBeingDecrypted() && !ev.isDecryptionFailure() && ev.getContent()?.body === body),
      ms);
    } catch (e) {
      const failed = events().filter((ev) => ev.isDecryptionFailure())
        .map((ev) => `${ev.getId()}: ${ev.decryptionFailureReason}`);
      throw new Error(`${e.message}; undecryptable here: ${failed.join(', ') || 'none'}`);
    }
  }

  /// The server's device list for this user: { deviceId: {ed25519, curve25519, crossSigned} }.
  async devices() {
    await this.client.downloadKeysForUsers?.([this.userId]);
    const q = await this.api('POST', '/keys/query', { device_keys: { [this.userId]: [] } });
    const ssk = Object.values(q.self_signing_keys?.[this.userId]?.keys ?? {})[0];
    const out = {};
    for (const [id, k] of Object.entries(q.device_keys?.[this.userId] ?? {})) {
      const sigs = k.signatures?.[this.userId] ?? {};
      out[id] = {
        ed25519: k.keys?.[`ed25519:${id}`],
        curve25519: k.keys?.[`curve25519:${id}`],
        signedBySelfSigningKey: ssk ? Object.prototype.hasOwnProperty.call(sigs, `ed25519:${ssk}`) : false,
      };
    }
    return out;
  }

  async verification(deviceId) {
    const s = await this.crypto.getDeviceVerificationStatus(this.userId, deviceId);
    return s ? { crossSigningVerified: s.crossSigningVerified, signedByOwner: s.signedByOwner } : null;
  }

  /// Approves the next device that asks to be verified ("Approve from another
  /// device" in the web app): accepts, compares the emoji (always "they
  /// match" here) and waits until both sides are done.
  async approveNextVerification(ms = 120000) {
    const request = await new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error('no verification request')), ms);
      this.client.once(CryptoEvent.VerificationRequestReceived, (r) => { clearTimeout(t); resolve(r); });
    });
    await request.accept();
    // Either side may start the emoji comparison; start it ourselves if the
    // web app doesn't.
    const end = Date.now() + 5000;
    while (!request.verifier && request.phase !== VerificationPhase.Cancelled && Date.now() < end) {
      await new Promise((r) => setTimeout(r, 250));
    }
    const verifier = request.verifier ?? (await request.startVerification('m.sas.v1'));
    verifier.on(VerifierEvent.ShowSas, (sas) => sas.confirm());
    await verifier.verify();
    await waitFor('verification done', async () => request.phase === VerificationPhase.Done ||
      (request.phase === VerificationPhase.Cancelled && Promise.reject(new Error(`verification cancelled: ${request.cancellationCode}`))), ms);
  }

  stop() { this.client.stopClient(); }
}
