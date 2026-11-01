// Vommet integration tests: another device of the same Matrix account, on
// matrix-js-sdk with its Rust crypto (the stack of Element Web and Element
// Desktop). The Flutter test starts it as a process and reads its stdout:
// one JSON object per line, {"peer": "<event>", ...}. Everything else on
// stdout/stderr is log noise.
//
//   node peer.mjs --hs https://localhost --user NAME --password PW
//        [--create-identity] [--accept] [--start DEVICE_ID]
//
// --create-identity  make the account's cross-signing identity, secret
//                    storage and key backup here (like setting up in
//                    Element first); prints {"peer":"identity","recovery_key"}.
// --accept           accept the next verification request and confirm the
//                    emoji (after printing them as {"peer":"sas","emoji"}).
// --start DEVICE_ID  request verification of our device DEVICE_ID and do the
//                    same once it is accepted.
//
// Afterwards it reads commands from stdin, one JSON object per line, and
// answers each with one line (or {"peer":"error"}):
//   {"cmd":"verify","device":ID}          as --start, for a device signed in later
//   {"cmd":"create_room","visibility":"shared"|"joined"|...}  encrypted room
//                                          -> {"peer":"room","room_id"}
//   {"cmd":"set_visibility","room":R,"visibility":V} -> {"peer":"ok"}
//   {"cmd":"send","room":R,"body":B}      -> {"peer":"sent","event_id","session_id"}
//   {"cmd":"invite","room":R,"user":U}    MSC4268: shares the room's history
//                                          when the visibility allows -> {"peer":"ok"}
//   {"cmd":"join","room":R}               waits for the invite, joins and takes
//                                          the inviter's key bundle -> {"peer":"joined"}
//   {"cmd":"room_keys","room":R}          -> {"peer":"room_keys","session_ids":[...]}
//   {"cmd":"read","room":R,"event_ids":[...]}  decrypted where we can ->
//       {"peer":"messages","events":[{"event_id", "body"|"failure"|"not_visible"}]}
// The process keeps syncing afterwards (it has to answer the new device's
// requests for the secrets) until stdin closes or it is killed.

import * as sdk from "matrix-js-sdk";
import {
  CryptoEvent,
  VerificationPhase,
  VerificationRequestEvent,
  VerifierEvent,
} from "matrix-js-sdk/lib/crypto-api/index.js";
import { logger } from "matrix-js-sdk/lib/logger.js";

const args = process.argv.slice(2);
const opt = (name) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
};
const flag = (name) => args.includes(name);

const out = (event, fields = {}) =>
  process.stdout.write(JSON.stringify({ peer: event, ...fields }) + "\n");
const fail = (where, e) => {
  out("error", { where, message: String(e?.stack ?? e) });
  process.exit(1);
};
process.on("unhandledRejection", (e) => fail("unhandled", e));
logger.setLevel(process.env.PEER_LOG ?? "warn");

const hs = opt("--hs") ?? "https://localhost";
const user = opt("--user");
const password = opt("--password");
if (!user || !password) fail("args", "--user and --password are required");

const authDict = (session) => ({
  type: "m.login.password",
  identifier: { type: "m.id.user", user },
  password,
  ...(session ? { session } : {}),
});

/** Runs a user-interactive-auth request, answering with the password. */
async function withPassword(makeRequest) {
  try {
    return await makeRequest(null);
  } catch (e) {
    const session = e?.data?.session;
    if (e?.httpStatus !== 401 || !session) throw e;
    return await makeRequest(authDict(session));
  }
}

async function main() {
  const login = await sdk
    .createClient({ baseUrl: hs })
    .loginRequest({
      ...authDict(),
      initial_device_display_name: opt("--name") ?? "Element Web (IT peer)",
    });
  out("logged_in", { user_id: login.user_id, device_id: login.device_id });

  // Secret storage keys we made or were given, by key id.
  const ssssKeys = new Map();
  const client = sdk.createClient({
    baseUrl: hs,
    userId: login.user_id,
    deviceId: login.device_id,
    accessToken: login.access_token,
    verificationMethods: ["m.sas.v1"],
    cryptoCallbacks: {
      getSecretStorageKey: async ({ keys }) => {
        for (const id of Object.keys(keys)) {
          if (ssssKeys.has(id)) return [id, ssssKeys.get(id)];
        }
        return null;
      },
      cacheSecretStorageKey: (keyId, _info, key) => ssssKeys.set(keyId, key),
    },
  });
  await client.initRustCrypto({ useIndexedDB: false });
  const crypto = client.getCrypto();

  const synced = new Promise((resolve) =>
    client.on(sdk.ClientEvent.Sync, (state) => {
      if (state === "PREPARED" || state === "SYNCING") resolve();
    }),
  );
  await client.startClient({ initialSyncLimit: 1 });
  await synced;
  out("synced");

  if (flag("--create-identity")) {
    await crypto.bootstrapCrossSigning({
      setupNewCrossSigning: true,
      authUploadDeviceSigningKeys: withPassword,
    });
    let recoveryKey;
    await crypto.bootstrapSecretStorage({
      setupNewSecretStorage: true,
      setupNewKeyBackup: true,
      createSecretStorageKey: async () => {
        const key = await crypto.createRecoveryKeyFromPassphrase();
        recoveryKey = key.encodedPrivateKey;
        return key;
      },
    });
    out("identity", {
      recovery_key: recoveryKey,
      cross_signing_ready: await crypto.isCrossSigningReady(),
      secret_storage_ready: await crypto.isSecretStorageReady(),
      backup_version: (await crypto.getActiveSessionBackupVersion()) ?? null,
    });
  }

  /** Drives one verification request through SAS to done. */
  async function drive(request) {
    const verifier = await new Promise((resolve, reject) => {
      const check = () => {
        if (request.verifier) return resolve(request.verifier);
        if (request.phase === VerificationPhase.Cancelled) {
          return reject(new Error(`cancelled: ${request.cancellationCode}`));
        }
        if (request.phase === VerificationPhase.Ready && request.initiatedByMe) {
          request.startVerification("m.sas.v1").then(resolve, reject);
          request.off(VerificationRequestEvent.Change, check);
        }
      };
      request.on(VerificationRequestEvent.Change, check);
      check();
    });
    verifier.on(VerifierEvent.ShowSas, (sas) => {
      out("sas", { emoji: (sas.sas.emoji ?? []).map(([e]) => e) });
      sas.confirm().catch((e) => fail("confirm", e));
    });
    verifier.on(VerifierEvent.Cancel, (e) =>
      out("cancelled", { reason: String(e?.message ?? e?.getContent?.()?.code ?? e) }),
    );
    await verifier.verify();
    out("done", { other_device: request.otherDeviceId ?? null });
  }

  if (flag("--accept")) {
    client.on(CryptoEvent.VerificationRequestReceived, (request) => {
      out("request_received", {
        from_device: request.otherDeviceId ?? null,
      });
      request
        .accept()
        .then(() => drive(request))
        .catch((e) => out("cancelled", { reason: String(e?.message ?? e) }));
    });
    out("waiting");
  }

  async function start(target, extra = {}) {
    // Our list must include the new device before we can ask it.
    for (let i = 0; i < 60; i++) {
      const devices = await crypto.getUserDeviceInfo([login.user_id], true);
      if (devices.get(login.user_id)?.has(target)) break;
      await new Promise((r) => setTimeout(r, 1000));
    }
    const request = await crypto.requestDeviceVerification(login.user_id, target);
    out("request_sent", { to_device: target, ...extra });
    await drive(request).catch((e) =>
      out("cancelled", { reason: String(e?.message ?? e) }),
    );
  }
  if (opt("--start")) await start(opt("--start"));

  const roomOf = async (roomId) => {
    for (let i = 0; i < 100; i++) {
      const room = client.getRoom(roomId);
      if (room) return room;
      await new Promise((r) => setTimeout(r, 200));
    }
    throw new Error(`room ${roomId} never showed up`);
  };
  const commands = {
    verify: async (c) => {
      // Not awaited: the verification runs on while other commands come
      // in. start() prints its own events; request_sent carries cmd.
      start(c.device, { cmd: c.cmd }).catch((e) =>
        out("error", { cmd: c.cmd, message: String(e?.stack ?? e) }),
      );
      return null;
    },
    create_room: async (c) => {
      const { room_id } = await client.createRoom({
        initial_state: [
          { type: "m.room.encryption", state_key: "", content: { algorithm: "m.megolm.v1.aes-sha2" } },
          { type: "m.room.history_visibility", state_key: "", content: { history_visibility: c.visibility ?? "shared" } },
        ],
      });
      await roomOf(room_id);
      return { peer: "room", room_id };
    },
    set_visibility: async (c) => {
      await client.sendStateEvent(c.room, "m.room.history_visibility", { history_visibility: c.visibility }, "");
      const room = await roomOf(c.room);
      for (let i = 0; i < 100 && room.getHistoryVisibility() !== c.visibility; i++) {
        await new Promise((r) => setTimeout(r, 100));
      }
      return { peer: "ok" };
    },
    send: async (c) => {
      const room = await roomOf(c.room);
      const { event_id } = await client.sendTextMessage(c.room, c.body);
      // The megolm session, so a test can check what a key bundle said about it.
      const session_id = room.findEventById(event_id)?.getWireContent()?.session_id ?? null;
      return { peer: "sent", event_id, session_id };
    },
    invite: async (c) => {
      await roomOf(c.room);
      await client.invite(c.room, c.user);
      return { peer: "ok" };
    },
    join: async (c) => {
      for (let i = 0; i < 150; i++) {
        const room = client.getRoom(c.room);
        if (room?.getMyMembership() === "invite") break;
        await new Promise((r) => setTimeout(r, 200));
      }
      await client.joinRoom(c.room);
      return { peer: "joined" };
    },
    room_keys: async (c) => {
      // The megolm sessions we hold for a room (e.g. from a history bundle).
      const keys = await crypto.exportRoomKeys();
      return {
        peer: "room_keys",
        session_ids: keys.filter((k) => k.room_id === c.room).map((k) => k.session_id),
      };
    },
    read: async (c) => {
      // By event id: fetched from the server like a timeline would, then
      // decrypted where we can. Bundles and backups arrive in the
      // background, so failures get a few retries.
      const room = await roomOf(c.room);
      const events = new Map();
      for (const id of c.event_ids) {
        const known = room.findEventById(id);
        if (known) {
          events.set(id, known);
          continue;
        }
        try {
          const raw = await client.fetchRoomEvent(c.room, id);
          events.set(id, new sdk.MatrixEvent(raw));
        } catch (e) {
          events.set(id, { notVisible: e?.errcode ?? String(e) });
        }
      }
      const pending = () =>
        [...events.values()].filter((e) => e instanceof sdk.MatrixEvent && (e.isEncrypted() && (e.isDecryptionFailure() || !e.getClearContent())));
      for (let i = 0; i < (c.retries ?? 20); i++) {
        for (const e of pending()) {
          await e.attemptDecryption(crypto, { isRetry: i > 0 }).catch(() => {});
        }
        if (pending().length === 0) break;
        await new Promise((r) => setTimeout(r, 500));
      }
      return {
        peer: "messages",
        events: c.event_ids.map((id) => {
          const e = events.get(id);
          if (!(e instanceof sdk.MatrixEvent)) return { event_id: id, not_visible: e.notVisible };
          if (e.isDecryptionFailure()) return { event_id: id, failure: e.decryptionFailureReason ?? "unknown" };
          return { event_id: id, body: e.getContent().body ?? null };
        }),
      };
    },
  };
  let buf = "";
  let queue = Promise.resolve();
  process.stdin.on("data", (d) => {
    buf += d;
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      queue = queue.then(async () => {
        let c;
        try {
          c = JSON.parse(line);
          const run = commands[c.cmd];
          if (!run) throw new Error(`unknown command ${c.cmd}`);
          const answer = await run(c);
          if (answer) {
            const { peer, ...fields } = answer;
            out(peer, { cmd: c.cmd, ...fields });
          }
        } catch (e) {
          out("error", { cmd: c?.cmd ?? null, message: String(e?.stack ?? e) });
        }
      });
    }
  });

  // Keep syncing: the new device asks us for the secrets after approval.
  process.stdin.on("end", () => process.exit(0));
  process.stdin.resume();
}

main().catch((e) => fail("main", e));
