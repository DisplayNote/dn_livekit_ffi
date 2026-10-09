# Debugging with AI — log sanitisation (control 4.7)

> Generated from the `log-sanitise` template (displaynote-engineering plugin) by
> `docs-update`. The "Mandatory step" and "Rules" sections are kept verbatim.

## Where this repo's logs live

| Source | Location / command | Typical sensitive content |
|---|---|---|
| Application log | No log file is written by this library. Every Rust crate logs through the `log` crate (`log::error!` … `log::trace!`; no `tracing` macros in the shipped crates); the process-wide logger is `FfiLogger` (`livekit-ffi/src/server/logger.rs`), installed by `FfiServer::default()` with `log::set_max_level(Trace)` (`livekit-ffi/src/server/mod.rs:97-99`). The host chooses the sink with `livekit_ffi_initialize(cb, capture_logs, sdk, sdk_version)` (`livekit-ffi/src/cabi.rs:20`): with `capture_logs = false` (also before initialisation and after `livekit_ffi_dispose`) records go to an `env_logger` built from `RUST_LOG` (`logger.rs:34`) — with env_logger's defaults that is errors only, written to stderr; with `capture_logs = true` `enabled()` returns `true` for every level (`logger.rs:61`) and every record, debug and trace included, is sent to the host as an `FfiEvent` `logs` message (`LogBatch` of `LogRecord { level, target, module_path, file, line, message }`, `livekit-ffi/protocol/ffi.proto:323-342`) through the registered callback. The host (dnbroadcast-qt) decides which levels it keeps and where it writes them; whatever it writes ends up in its own logs, i.e. in Montage's logs when Montage runs the broadcast. Native libwebrtc `RTC_LOG` output — including the DN Android factories (`webrtc-sys/src/android/*.cpp`) and the x264 encoder (`webrtc-sys/src/x264/x264_video_encoder.cpp`) — is captured by a log sink registered at `LS_VERBOSE` (`webrtc-sys/src/webrtc.cpp:155`) and re-emitted as `log::debug!(target: "libwebrtc", …)` whatever its original severity (`libwebrtc/src/native/peer_connection_factory.rs:54-56`), once the first `PeerConnectionFactory` exists | Info: LiveKit server URL with the token masked as `access_token=...` (`livekit-api/src/signal_client/signal_stream.rs:106`), region fallback URLs (`livekit-api/src/signal_client/mod.rs:165`), the `HTTPS_PROXY`/`HTTP_PROXY` value including any `user:password@` (`signal_stream.rs:121`). Debug: full `JoinResponse` / `ReconnectResponse` (`livekit/src/rtc_engine/rtc_session.rs:357`, `:1375`) with room name and metadata, participant identities, names and metadata, and ICE servers with TURN `username`/`credential`; SDP offers/answers (`rtc_session.rs:839`, `:852`, `:981`) and local/remote ICE candidates with IP addresses (`:875`, `:942`); libwebrtc verbose output. Error/warn: whole `FfiRequest` `{:?}` dumps on a failed request (`livekit-ffi/src/cabi.rs:62`) and room/engine event dumps (`livekit-ffi/src/server/room.rs:968`, `:1378`; `livekit/src/room/mod.rs:788`; `livekit/src/rtc_engine/mod.rs:432`) — data packet payloads, chat text, metadata, attributes, RPC payloads, identities |
| Live stream | This repo has no logcat output of its own: no `android_logger` dependency, no `__android_log_*` calls and no logcat tag. On Android the Rust logs reach the host only through `capture_logs`; the `env_logger` fallback writes to stderr and `JNI_OnLoad` writes `println!("JNI_OnLoad, initializing LiveKit")` to stdout (`livekit-ffi/src/cabi.rs:122`), and Android does not normally show an app's stdout/stderr in logcat. libwebrtc's own debug output and the WebRTC Java classes in `libwebrtc.jar` (`livekit.org.webrtc.*`) follow upstream WebRTC defaults, which this repo does not configure. Use `adb logcat -d` for the host's lines (under the host's tags). Desktop/Windows: `env_logger` on the console's stderr (`RUST_LOG=debug` to widen); no `OutputDebugString` in this repo | Same content as the application log for whatever level is enabled; host lines carry what the host chooses to log |
| Crash reports | No crash reporter (no Sentry, Crashpad or Breakpad) in this repo. Rust panics inside `livekit_ffi_request` are caught (`catch_unwind`), logged at error level as `panic while handling request: {:?}` and reported to the host as an `FfiEvent` `Panic` with a generic message (`livekit-ffi/src/cabi.rs:80-87`); a panicked async task is logged as `task panicked: {:?}` (tokio's `JoinError`, which can carry the panic message), forwarded as `Panic` and then re-panics (`livekit-ffi/src/server/mod.rs:267-269`). A deadlock detector logs thread backtraces at error level every 10 s while a deadlock persists (`server/mod.rs:112-116`). Native crashes (libwebrtc, JNI, x264) kill the host process: Android `tombstone_*` files and `adb logcat -d -b crash`, Windows Error Reporting / the host's own crash handling; release builds are stripped (`livekit-ffi/.cargo/config.toml`: `strip = true`), so native frames are unsymbolised | Panic messages (may embed request values), backtrace file paths, device identifiers in tombstones |
| CI logs | Two CIs run on this fork: Azure Pipelines (`.azure/pipelines/`, `displaynote-devops`: WebRTC builds, version read, Conan packaging) and the upstream GitHub Actions workflows under `.github/workflows/` (Build, Test, Check Formatting, Release-plz) — see the repo-specific note for what the Test jobs print | internal paths, hostnames, test-server URLs |
| Customer bundles | Zendesk ticket attachments — download them to a file and sanitise before reading; the Zendesk MCP bypasses the Claude Code guard, so never read attachments through it (see `.agents/skills/log-sanitise/SKILL.md`) | **Protected**: end-user identifiers (1.3 §4.2) |

## Mandatory step — sanitise before any AI tool sees the log

Before a log file, a log excerpt or a live log stream reaches Claude Code, Codex,
Copilot, Cursor, ChatGPT, Claude (Cowork) or any custom OpenAI-API integration,
run it through `dn_logscrub`:

```bash
# Work OUTSIDE the repository: a raw log inside it blocks the searches that would read it
mkdir -p ~/dn-tickets/22416 && cd ~/dn-tickets/22416

# Claude Code (plugin installed) — one call, all files, shared placeholders
/log-sanitise montage.log launcher.log --map ticket-22416.dnmap

# Any agent / shell — the portable copy synced into the repo
python3 <repo>/.agents/skills/log-sanitise/scripts/dn_logscrub.py montage.log launcher.log --map ticket-22416.dnmap

# Inputs in a read-only folder, or elsewhere: write the copies into one directory
python3 <repo>/.agents/skills/log-sanitise/scripts/dn_logscrub.py /var/log/omni/*.log --out-dir ~/dn-tickets/22416

# Live streams — pipe, never paste; use a command that ends (`-d`), not a live tail
adb logcat -d | python3 <repo>/.agents/skills/log-sanitise/scripts/dn_logscrub.py - > logcat.scrubbed.txt

# Customer logs — add the customer's domain(s) so their hostnames are pseudonymised too
python3 <repo>/.agents/skills/log-sanitise/scripts/dn_logscrub.py bundle/*.log --domain acme-school.org
```

A run that is cut short (Ctrl-C, a tool timeout) still writes a trailer marked
`interrupted`: the copy is clean but incomplete. The sanitiser processes a few
MB per second; run very large bundles from your own terminal.

The tool writes `<name>.scrubbed.<ext>` next to each input, prints one summary
line per file (`dn_logscrub: montage.log: 41 redactions (EMAIL=3, ID=12, …)`) and
starts every output with a `# dn_logscrub v…` marker header and ends it with a
`# dn_logscrub end | redactions=…` trailer carrying the per-category counts
(output is written as it is produced, so a live stream appears immediately
instead of waiting for the end). Only files that start with that header and
end with that trailer may be opened by, pasted into, or attached to an AI tool.
A file with the header but no trailer as its last non-empty line is raw:
something was appended after scrubbing (`cat raw >> x.scrubbed.log`,
concatenated files, a process still writing). A trailer ending in
`| interrupted` is accepted — the copy is clean, only incomplete. A
`# dn_logscrub-partial` header does not count: it means rules were switched off
for that run.

## Rules

1. Only `*.scrubbed.*` files (marker header on the first line and the
   `# dn_logscrub end` trailer as the last non-empty line) go to an AI tool.
   Raw logs never do — the Claude Code hook blocks them; for other tools the
   rule is on you.
2. Placeholders are stable within a run: `<EMAIL_1>` is the same person in every
   file of that run. Keep placeholders in PR descriptions, ticket comments and
   Slack messages; never expand them there.
3. The `--map` file (`*.dnmap`) holds the originals for your own reverse lookup.
   It stays on your machine; never attach it, commit it or paste from it.
4. Customer logs are **Protected** data by default (AI Governance Policy 1.3 §4.2).
   Sanitised customer logs may go to Green-List tools with a corporate account.
   Raw customer logs may go to an AI tool only with AI Lead + CEO approval
   (1.3 §4.1) — signal an approved exception with `DN_LOGSCRUB_ALLOW_RAW=1`.
5. Residual check: skim the scrubbed file for anything the patterns missed
   (a person's name in free text, a customer hostname without `--domain`, an
   unusual token format). Fix with `--domain`, or open an issue on
   `displaynote-engineering` with the *category and shape* of the miss — never
   with the value itself.
6. Automated flows (Sentry fixer, Release Management Agent, n8n) call the same
   library (`Scrubber().scrub_text(...)`) before every external model call. A
   flow that writes its result to a file uses `Scrubber().finalize(text, name)`,
   which adds the header and trailer the Claude Code hook and `--check` require.

## What is redacted vs. kept

Redacted irreversibly: private keys, JWTs, auth headers, URL credentials,
cloud/API keys, any `password= / token= / secret= / *_key=` value, OAuth
`code=`/`state=`/`nonce=` in URLs.
Pseudonymised consistently: e-mails, quoted/keyed names (people, devices,
computers), keyed ids (serial, deviceId, session, meetingId, roomPin, tenantId,
licence…), Android `getprop` serials, Wi-Fi SSIDs, IPv4/IPv6, MACs, UUIDs, phone
numbers, the user-home part of any path (Windows with either slash, JSON-escaped,
`file:///`, WSL), Windows `DOMAIN\user` accounts and UNC servers, `DESKTOP-…`
machine names, `.local/.lan/.internal` hosts, `--domain` domains, long hex and
high-entropy strings.
Kept: timestamps, version numbers, stack traces, package/class/method names and
JNI symbols, the rest of the path, file hashes and git commit ids, loopback
addresses, and keys that only describe a secret (`token_expires_in=3600`).
Not caught: a person's name in free text, a customer hostname without `--domain`.

Repo-specific note: nothing is compiled out of release builds. No `Cargo.toml` in
the workspace enables the `log` crate's `max_level_*` / `release_max_level_*`
features and `FfiLogger` sets the maximum level to `Trace`
(`livekit-ffi/src/server/mod.rs:99`), so every `log::debug!` / `log::trace!` line is
present in the release `liblivekit_ffi`; what is emitted depends only on the sink.
With `capture_logs = true` all levels reach the host in release builds — the host's
own level filter is the only gate — and with the `env_logger` fallback `RUST_LOG`
decides. The libwebrtc build scripts (`webrtc-sys/libwebrtc/build_*.sh`,
`build_windows.cmd`) do not set `rtc_disable_logging`, so `RTC_LOG` lines remain in
the release libwebrtc as far as upstream GN defaults go, and the log sink installed in
`libwebrtc/src/native/peer_connection_factory.rs` forwards them all at debug level.
The residual risks, all files involved: (1) at debug level, `JoinResponse` and
`ReconnectResponse` dumps (`livekit/src/rtc_engine/rtc_session.rs:357`, `:1375`)
carry TURN `username` / `credential` values, room name and metadata and participant
identities, names and metadata, and SDP / ICE candidate lines (`rtc_session.rs:839`,
`:852`, `:875`, `:942`, `:981`) carry IP addresses; the credentials appear as Rust
`Debug` fields (`credential: "…"`), not as `password=`-style pairs, so check for
them explicitly in the residual pass. (2) At error/warn level, request and event
`{:?}` dumps (`livekit-ffi/src/cabi.rs:62`, `livekit-ffi/src/server/room.rs:968`,
`:1378`, `livekit/src/room/mod.rs:788`, `livekit/src/rtc_engine/mod.rs:432`) can hold
data-packet payloads, chat text, metadata, attributes, RPC payloads and identities —
free text that the patterns do not catch. (3) At info level, the `HTTPS_PROXY` /
`HTTP_PROXY` value is logged verbatim (`livekit-api/src/signal_client/signal_stream.rs:121`);
URL credentials in it are redacted by `dn_logscrub`, the proxy host is not unless
it matches a rule or `--domain`. (4) The LiveKit access token (a JWT) is not logged
by this repo's code: the signalling URL is logged with `access_token=...`
(`signal_stream.rs:89-106`), and the `ConnectRequest` that holds it is never dumped
because `on_connect` cannot fail synchronously (`livekit-ffi/src/server/requests.rs:54-59`);
should a JWT appear in a host log anyway, `dn_logscrub` redacts JWTs irreversibly.
(5) Server URLs and region fallback URLs (`signal_stream.rs:106`,
`livekit-api/src/signal_client/mod.rs:165`) name the LiveKit deployment; add
`--domain` for customer-hosted servers. Outside the shipped library, upstream
`.github/workflows/tests.yml` runs `cargo test … -- --nocapture` with `RUST_LOG`
set (`debug` job-wide, `info` on the test steps), so test logs — against a local
`livekit-server --dev` for E2E — go to the GitHub Actions run logs; the Azure
pipelines and the build scripts (`build_android.sh`, `generate_conan_build.sh`,
`webrtc-sys/build.rs`) print only build output (paths, patch results, `cargo:warning`
lines) to the run log or terminal and write no log files. No repo-specific sanitiser patterns have been shipped yet; raise any needed as an issue on `displaynote-engineering` and list them here once shipped.
