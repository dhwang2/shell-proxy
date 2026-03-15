# shell-proxy Repository Execution Records

## 0.0 Archiving Guidelines

1. The tasks in the checklist and the execution records in the workflow must map to each other one-to-one. When writing, you must add: section mapping title, mapping sequence number, and mapping date to ensure tasks and execution records are synchronized.
2. Prioritize checklist tasks as the first priority. If a task has not been executed, the workflow execution record should retain the task sequence number; if an execution record is an impromptu, extra execution and not recorded in the task, the task must first be added to the checklist.
3. Archive separately according to the level of records. When archiving, there is no need to add "Main Modified Files" and "Version Information" descriptions; archiving must include the mapped date, sequence number, and title.
4. **English Only:** All writings, logs, and workflow updates must strictly use English to facilitate agent read/write operations.
5. **Writing Principle:** Adhere to the principle of being concise and comprehensive when writing.

## 1.0 proxy Repository Overall Planning Tasks
### u-1-1 Architecture Refactoring: Self-built proxy repository (2026-02-10)
> **Goal**: Break free from dependency on the third-party VLESS All-in-One script, establishing an autonomous and controllable Sing-box + Snell v5 deployment system.

- **Repository Reconstruction**:
  - Create a new GitHub private repository `proxy`, forked from the original `sing-box` repository, stripping away historical baggage.
  - Add `public` repository bootstrap script `install-proxy.sh`, pointing to the new `proxy` repository (the original `install-singbox.sh` reverts to pointing to the `sing-box` repository, achieving decoupling).
  - Shortcut command change: `sb` -> `proxy`.
- Repository Merge and Structure Reorganization:
  - **Surge Migration**: Migrate the `surge` repository contents into `proxy/clients/surge`.
  - Directory Refactoring: **Clients**: Establish `surge` (base/standard/gateway) and `sing-box` (mobile/desktop/router) classifications. **Server**: Separate `install` scripts and `templates` configuration templates.
  - **Documentation Consolidation**: Merge `START.md` and `AGENTS.md`.

### u-1-2 Repository Convergence: Migrate sing-box configs and locally deprecate legacy repo (2026-02-16)
> **Goal**: Enter the "`proxy` single-repo maintenance" state: fully migrate the client/server configurations that still hold value from the `sing-box` repository to `proxy`, and remove the legacy repository directory locally.

- **Migration Results (moved as-is, undemaskified)**:
  - Client Configurations:
    - `sing-box/configs/client/macos.json` -> `proxy/clients/sing-box/desktop/macos.json`
    - `sing-box/configs/client/android.json` -> `proxy/clients/sing-box/mobile/android.json`
  - Server Configurations:
    - `sing-box/configs/server/sfali.json` -> `shell-proxy/templates/sing-box/sfali.json`
    - `sing-box/configs/server/sfgcp.json` -> `shell-proxy/templates/sing-box/sfgcp.json`

- **Version Record**:
  - `proxy` has committed the migration changes: `850c5d9` (`chore: migrate sing-box configs into proxy`)

- **Local Environment Changes**:
  - Deleted local directory: `/Users/dhwang/github/sing-box`
  - Note: This operation only affects the local workspace, and does not include remote GitHub repository deletion actions.

### u-1-3 Checklist/Workflow Deep Decoupling (Client Configs and Server Install Scripts) (2026-02-25)
> **Goal**: Clarify the boundaries of documentation responsibilities, avoid confusing task tracking with execution records, and decouple the document structure along the two main threads of "server installation" and "client configuration".

- **Document Structure Refactoring**:
  - **Checklist**: Solely serves as a task status tracking board (To-Do List), clarifying "what to do" and "whether it is done".
  - **Workflow**: Solely serves as an execution record pipeline (Log), detailing "how it was done" and "execution results".
- **Process Split**:
  - **Server Thread**: Focuses on the iteration of the `server/shell-proxy` script tree (installation/configuration/operation/verification), independent of client adaptation.
  - **Client Thread**: Split into three independent adaptation flows for `sing-box` / `mihomo` / `surge`, separately recording the configuration generation and compatibility verification of each platform.
- **Current Status**:
  - Document directories and sections are physically isolated according to the above logic.
  - Subsequent tasks (u-1-x / u-2-x / u-4-x) will all be archived following this structure.

## 2.0 shell-proxy
### v0.0.0

##### u-2-1 Script enhancement, Snell v5 integration (2026-02-10)
Integrated Snell v5, implemented dynamic version management, and optimized configuration options.

##### u-2-2 Script interactive experience optimization (UX) (2026-02-10)
Optimized management and installation menus to loop and auto-guide instead of directly exiting.

##### u-2-3 ShadowTLS and security enhancements (2026-02-10)
Independently integrated ShadowTLS, optimized v3 installation parameters, and added port conflict detection.

##### u-2-4 Transparent uninstallation logic (2026-02-10)
Listed all paths during uninstallation and provided real-time deletion feedback.

##### u-2-5 Sing-box interactive config upgrade & randomization (2026-02-11)
Added interactive modifications, randomized UUID/ShadowTLS/Reality elements, and Reality key pairs.

##### u-2-6 Dual-stack support and fake domain optimization (2026-02-11)
Researched IPv4/IPv6 dual stack capabilities, streamlined inbound configurations, and improved Shadow-TLS domains.

##### u-2-7 Subscription and protocol links (2026-02-11)
Implemented dual-endpoint JSON and Surge format subscriptions.

##### u-2-8 Architecture structural refactoring (First principles) (2026-02-12)
Decoupled code modules, introduced systemd templates, enforced strict error handling, and fixed public installer.

##### u-2-9 Menu hierarchy and routing UX (2026-02-12)
Adjusted main menus based on opensource alternatives to prioritize setup logic.

##### u-2-10 Server path convergence (2026-02-16)
Centralized all outputs to `/etc/shell-proxy/` and fixed Windows dual-stack details.

##### u-2-11 Subscription availability & UX fixes (2026-02-16)
Handled Reality/TUIC URI generation failures, added port override dialogues, and improved menu UI colors.

##### u-2-12 Operational Logs menu rebuilding (2026-02-17)
Categorized live logs into internal scripts, daemon watchdogs, and protocol states.

##### u-2-13 Main menu and dynamic routing integration (2026-02-17)
Streamlined settings, deployed dual-stack adaptable routing, and matched proxy exit IPs with DNS resolutions.

##### u-2-14 Chain-proxy enhancements and config readability (2026-02-17)
Addressed chain proxy input types, removed dead ACME routing strings, and used formatting for easy config reading.

##### u-2-15 ShadowTLS multi-binding and interface fixes (2026-02-17)
Supported ShadowTLS binding on single-protocol levels, enhanced interface logging.

##### u-2-16 Anytls protocol coverage & naming bounds (2026-02-17)
Addressed the `anytls` protocol workflow integrations securely, checking Apple guidelines natively.

##### u-2-17 Atomic DNS and route linkage (2026-02-18)
Synced routing/DNS tables simultaneously preventing silent removal of critical baseline routes.

##### u-2-18 Geosite/Geoip catalogs and server integrations (2026-02-18)
Mapped Netflix/TikTok databases natively providing accurate content filtering over 1-9 UI interactions.

##### u-2-19 Trace logs removal (2026-02-18)
Trimmed broken interactive realtime logging systems.

##### u-2-20 Trojan fixes (2026-02-18)
Bridged ALPN and configuration generation anomalies over HTTPS links.

##### u-2-21 SS 2022 unified cryptography (2026-02-18)
Pushed 2022-blake3 default configurations with matching Surge template outputs.


##### u-2-22 DMIT server deployments & firewall logic (2026-02-19)
Rolled out server installation capabilities coupled strictly with native firewall port policies.

##### u-2-23 DNS strategies & subscription exports (2026-02-19)
Enforced `prefer_ipv4` on generic dual-stack targets, unified public DNS tags, and streamlined subscription formats.

##### u-2-24 Sing-box v1.14 compatibility (2026-02-19)
Adapted core network generations securely to `domain_resolver.strategy` resolving flows.

##### u-2-25 Network optimization module (2026-02-20)
Added the main menu "Network Optimization" providing end-to-end OS BBR deployments, regression tested continuously on DMIT.

##### u-2-26 Reminder sync optimizations (2026-02-21)
Handled subscription format validations, tuned Surge parameter specs, audited ShadowTLS UI variables, and filtered proxy domains accurately.

##### u-2-27 AI telemetry & geosite filtering (2026-02-21)
Paired unified `geoip-ai` mapping directly alongside foundational AI rulesets natively.

##### u-2-28 Subscription reload guard (2026-02-22)
Prevented UI prompt cyclic auto-restarts by enforcing configuration timestamp comparisons and deduplicated general Surge node footprints.

##### u-2-29 Shadow-TLS V3 patches (2026-02-22)
Standardized local proxy linkages strictly adhering to `shadow-tls-version=3` averting generic TLS handshake degradation against Surge clients.

##### u-2-30 Surge link format convergence (2026-02-23)
Conformed remote UI template links perfectly overlapping the mapped local iOS `dmit.conf` standard metrics.

##### u-2-31 Terminal UI enhancements (2026-02-23)
Compressed visual occupied port tracking data intelligently and pushed complex parameter design guides into local documentation nodes.

##### u-2-32 IPv4 public address correction (2026-02-23)
Discarded generalized IPv4 polling metrics mapping Surge nodes exclusively relying on global public IPs.

##### u-2-33 Complete uninstallation sequences (2026-02-23)
Embedded comprehensive "Uninstall All Protocols" functionality providing fully-clean teardown capabilities spanning overlapping configurations securely.

##### u-2-34 Caddy version mechanisms (2026-02-28)
Resolved legacy hardcoded tags enforcing systematic dynamic API fetches consistent with master update pipelines.

##### u-2-35 Account-level routing frameworks (2026-02-28)
Structured granular routing profiles mapping standalone upstreams and unique rule definitions selectively based on individual user contexts.

##### u-2-36 Shadow-TLS subscription formats (2026-03-01)
Merged linked subscriptions preventing raw protocol exports directly underneath assigned Shadow-TLS entry bindings.

##### u-2-37 Link target diagnostics (2026-03-01)
Remedied internal `::ffff:...` map collisions alongside high latency UI freezes by offloading complex rendering cycles strictly into cached contexts.

##### u-2-38 User structural overhaul (2026-03-01)
Inverted general management trees focusing operations directly via explicit User identifiers rather than indexing shared protocols.

##### u-2-39 Locked protocol manipulation scopes (2026-03-01)
Mandated all component installations/uninstallations specifically within selected Username confines matching grouped user subscriptions.

##### u-2-40 De-coupled initialization routines (2026-03-01)
Dropped automatic protocol bindings across basic Username setups, permitting hollow accounts lacking prior rule parameters conditionally.

##### u-2-41 Interactive flow standardization (2026-03-01)
Directed overarching UI workflows linearly defining sequential selections: Protocol Identification -> Target Username Assignment.

##### u-2-42 Legacy UI speedups (2026-03-01)
Rebuilt backend execution polling chains migrating massive repetitive file scans into streamlined in-memory multi-tiered caching modules reducing layout latency.

##### u-2-43 Management hierarchy simplifications (2026-03-02)
Abstracted explicit user routing behaviors out of standard general management menus, pushing them into separate routing portals conditionally mapped against target parameters.

##### u-2-44 Network firewall integrations (2026-03-02)
Expanded the internal BBR optimizations layout appending comprehensive automated nftables/iptables synchronizations tightly monitoring standard protocol ports.

##### u-2-45 proxy script v1.0.0 refactoring and optimization (2026-03-03)
Identified 6 major structural risks in the monolithic `config_ops.sh`; extracted 66 focused modules by domain (common, routing, user, protocol, subscription, service, network, etc.); introduced base preloading + menu lazy-loading; converged managed-file manifests into `env.sh`; cleaned up all confirmed dead functions and aliases.

##### u-2-46 server/install module grouping list convergence (2026-03-03)
Unified module lists into a single source of truth in `env.sh`; promoted grouped `modules/core|protocol|routing|subscription|user/` directories from mirrors to true implementations; demoted flat `modules/*.sh` to compatibility shells; hardened self-update bootstrap; fixed regressions on `gcp-hk`.

##### u-2-47 GCP-HK installation and IPv6 repair, TLS domain-check parallelization (2026-03-04)
Completed fresh install on `gcp-hk`; fixed IPv6 detection false positives; parallelized TLS domain-availability checks to cut certificate wait time.

##### u-2-48 Certificate wait animation and script-update parallelization (2026-03-04)
Added live spinner during certificate issuance; parallelized script-update download and verification steps.

##### u-2-49 Script update chain and Surge display corrections (2026-03-04)
Fixed update-chain source-ref tracking; corrected Surge link display format mismatches after update.

##### u-2-50 Main menu network stack display (2026-03-04)
Added IPv4/IPv6 dual-stack indicator to the main menu status block.

##### u-2-51 User management removed "User Control" (2026-03-04)
Removed the deprecated "User Control" sub-menu entry; simplified user management page.

##### u-2-52 server/install subscription cache, DNS sync, and management entry convergence (2026-03-04)
Merged subscription cache paths and DNS-sync triggers; tightened management entry module boundaries.

##### u-2-53 bugfix: tuic domain override update and certificate entry default domain repair (2026-03-05)
Fixed TUIC domain-override not persisting across restarts; corrected certificate entry defaulting to wrong domain.

##### u-2-54 perf: subscription bucketized per-user + routing rules sessionized submissions (2026-03-05)
Partitioned subscription render cache per user; deferred routing-rule writes into session batches to eliminate redundant reloads.

##### u-2-55 perf: routing submission chain second-round hotspot convergence (2026-03-05)
Eliminated remaining O(n) hotspots in the routing submission path; further compressed per-write overhead.

##### u-2-56 stability fixes and resource health archiving (2026-03-05)
Applied a batch of stability patches; archived resource-health baseline metrics for reference.

##### u-2-57 bugfix: DNS strategy and chained-node IP-family linkage fix (2026-03-05)
Corrected DNS strategy not propagating correctly to chain-proxy node IP-family selection.

##### u-2-58 perf: protocol menu snapshot-only stale rebuilds + main menu dashboard static caches (2026-03-05)
Protocol menu now rebuilds its snapshot only on stale fingerprints; main menu dashboard values are statically cached between renders.

##### u-2-59 perf: startup chain deduplication and auto-config process-level short-circuiting (2026-03-05)
Eliminated duplicate `source` calls in the startup chain; `auto-config` exits early when configuration is already up to date.

##### u-2-60 perf: startup first-round stale background re-synchronization (2026-03-05)
Moved stale-state re-sync off the critical startup path into a background job.

##### u-2-61 perf: user template routing sync persistent short-circuits and compilation caches (2026-03-05)
Added persistent fingerprint short-circuits and on-disk compilation caches to skip redundant template-route syncs.

##### u-2-62 perf: routing sync warm path further compressed (2026-03-05)
Reduced warm-path overhead for routing synchronization.

##### u-2-63 perf: routing sync warm path fixed overhead further converged (2026-03-05)
Eliminated remaining fixed costs (file reads, `jq` invocations) from the routing sync warm path.

##### u-2-64 perf: startup fingerprint hot-path caching + stale verification offloaded to background (2026-03-05)
Cached fingerprint comparisons in memory; moved stale-verification work to a background process.

##### u-2-65 perf: DNS sync hot-path deduplication and parent-shell cache reuse (2026-03-06)
Deduplicated redundant DNS sync calls within a single shell session; reused parent-shell cache across sub-shell invocations.

##### u-2-66 perf: user template routing sync cross-process cache offloading (2026-03-06)
Persisted routing-sync intermediate results to disk so child processes can reuse them without recomputing.

##### u-2-67 perf: user template routing sync input-fingerprint short-circuit (2026-03-06)
Added an input-side fingerprint check so unchanged template inputs skip all sync work immediately.

##### u-2-68 perf: routing status view-cache and config display single-jq rendering (2026-03-06)
Consolidated routing status and config display into a single `jq` call per render pass.

##### u-2-69 perf: menu status fingerprint lightening and background warmup after startup (2026-03-06)
Simplified the status fingerprint to cheaper fields; kicked off menu warmup in the background after startup completes.

##### u-2-70 perf: routing status cache pre-pushed to write time, pre-build scope narrowed (2026-03-06)
Pushed routing status cache generation forward to write time; narrowed the pre-build scope to avoid unnecessary work.

##### u-2-71 perf: main startup chain slimmed, menu warmup disabled by default, config-view header merged (2026-03-06)
Removed non-essential loads from the startup critical path; disabled eager menu warmup by default; merged config-view header rendering.

##### u-2-72 perf: subscription menu dependency autonomy fix and target-detection cross-process caches (2026-03-06)
Fixed subscription menu accidentally depending on routing state at load time; added cross-process caches for target-detection results.

##### u-2-73 perf: subscription rendering context cross-process caches and dashboard cold-rebuild frequency lowering (2026-03-06)
Persisted subscription render context across processes; reduced cold-rebuild frequency for the main menu dashboard.

##### u-2-74 perf: main menu full-page static cache, base unloading, and routing-source pollution fixes (2026-03-06)
Cached the full main menu page statically; unloaded base modules after startup; fixed routing-source variable pollution.

##### u-2-75 perf: subscription freshness-check deduplication and routing top-level lazy loading (2026-03-06)
Deduplicated redundant freshness checks in the subscription path; made top-level routing module loading lazy.

##### u-2-76 perf: share light-entry + host cache + routing sub-function tiered lazy loading (2026-03-06)
Added a fast empty-install path for share; cached host detection results; tiered lazy loading for routing sub-functions.

##### u-2-77 perf: rule menu first screen lazily fetches state and reuses user-state cache (2026-03-06)
Routing rule list page now lazily fetches routing state and reuses the already-loaded user state.

##### u-2-78 perf: routing-status freshness-check chain cross-process cache (2026-03-06)
Added a cross-process fingerprint cache for the routing-status freshness check chain.

##### u-2-79 perf: routing session-state loading chain slimmed (2026-03-06)
Removed redundant loads from the routing session-state initialization path.

##### u-2-80 perf: test-routing-effect switched to cache-prioritization + background refresh (2026-03-06)
"Test Routing Effect" now shows cached results immediately and refreshes in the background.

##### u-2-81 perf: compress write path for user routing-rule submissions (2026-03-06)
Merged multiple per-rule writes into a single batched write; eliminated repeated `jq` re-parsing per submission.

##### u-2-82 perf: meta-level fast short-circuits for user template routing sync (2026-03-06)
Skips full routing sync when the user has no template or the template rules are empty.

##### u-2-83 perf: routing submission chain skips irrelevant inbound username sanitize (2026-03-06)
Bypassed the costly username-sanitize pass for inbounds unrelated to the current submission.

##### u-2-84 fix: menu regression fixes after reinstallation (2026-03-06)
Fixed several menu interaction regressions that appeared after a clean reinstall from the public entry script.

##### u-2-85 UX/perf: install protocol changed to delayed restart within menu session (2026-03-08, merged into u-2-88)
Buffered `sing-box` restarts until exiting the install-protocol session instead of restarting after each individual protocol.

##### u-2-86 UX: stay in install-protocol menu after installing a single protocol (2026-03-08, merged into u-2-88)
After installing a protocol the menu loops back to the protocol selector instead of jumping to the main menu.

##### u-2-87 perf: squeeze user-management entry first-screen stutters (2026-03-08, merged into u-2-88)
Reduced first-screen stutter in user management by deferring membership cache loads.

##### u-2-88 refactor: refactor menu and loading architecture from first principles (2026-03-08)
Major refactor: introduced per-group bundle pre-build system in `env.sh`; deferred `sing-box` restart to session exit; unified menu headers/spinners; parallelized subscription target probing; narrowed compatibility boundary to `v1.0.0+`; deleted 14 shim files and orphan helpers; converged public/private bootstrap entry; 13-phase execution with full `gcp-oregon` regression verification.

##### u-2-89 refactor: remove public install entry script, retaining only private repo bootstrap (2026-03-08)
Deleted `public/install-proxy.sh`; unified installation entry to `server/install/bootstrap.sh` in the private repo; updated docs.

##### u-2-90 refactor backlog: existing architecture approaching upper limits -- refactor menu & architecture (2026-03-08)
Defined 5 architectural targets (silky UX, simpler code, merged files, concise interface, phased design-first refactor); executed 13 phases covering bundle scope, TTY detection, subscription convergence, orphan cleanup, compat-boundary narrowing, Snell stale-binding removal, reinstallation regression, and bootstrap convergence.

#### v1.1.0

##### u-2-91 refactor: high-ceiling architecture as baseline -- advance ultimate performance and silky menu interactions (2026-03-09)
Took the new architecture from u-2-88 as baseline; executed 5 phases: bleeding-control for install/update chains, basic-layer split (`release_ops`, `bootstrap_ops`, `runtime_shadowtls_ops`), hot-path load reduction (read-only menu no longer invalidates main-menu cache, routing/share short TTL caches), subscription-chain modularization (`share_meta_ops`, merged dual-probe, display-name cache fast path, eliminated cross-process disk render context); `gcp-oregon` metrics: `proxy status` 0.851s -> 0.240s, main-menu blackbox 0.561s -> 0.236~0.557s, share cold render 3.293s. Phase 5: async config-apply, bundle-build heredoc extracted to `bundle_build_ops.sh`, module total realigned to 38.

##### u-2-92 cleanup: dead/legacy/redundant code removal and regression re-verification (2026-03-10)
Low-risk first pass deleted 8 confirmed zero-call functions across `config_ops`, `protocol_port_ops`, `routing_ops`, `routing_res_socks_ops`, `subscription_ops`; minimal machine regression on `gcp-oregon` (subscription management, test routing, routing management, install protocol) passed; continued protocol-add-chain convergence: per-user `compiled-rules` cache, atomic `user-management.json` write, gating on route-state change; warm metrics: `proxy status` 0.169s, main-menu 0.257s, subscription 1.757s, routing 0.616s.

##### u-2-93 regression: real menu interaction verification (2026-03-10)
Measured 6-protocol real-menu install for user `u193x1` -- before fix: `proto_5(anytls)` 39s, `proto_6(snell)` 34s, `exit_install_apply` 30s; after fix: all <=7s, `exit_install_apply` 11.755s. Remaining targets (10 routing rules, 5-user full run, Workflow archiving) are pending.

##### u-2-94 gcp-oregon remote script update and basic function re-verification (2026-03-10)
> **Target**: Execute one round of real script update on `gcp-oregon`, and verify the basic availability of the current "install/update/bundle/fallback" main chain with minimal menu samples.

- **Execution Log**:
  1. **Remote status check**:
     - Checked the target machine's state via SSH beforehand, confirming it was an "empty environment":
       - `/etc/shell-proxy` did not exist
       - `/usr/bin/proxy` did not exist
       - `self_update.sh` did not exist
     - Therefore this round could not directly enter `self_update` from an "already installed environment"; a current script installation had to be restored first before continuing update verification.
  2. **Installation restore (local script copy)**:
     - Synced the latest local `shell-proxy/` copy to the remote temporary directory.
     - Executed `sudo bash install.sh` via a real TTY; installation completed successfully:
       - `sing-box / snell-v5 / shadow-tls-v3 / caddy` all completed installation
       - `/usr/bin/proxy` was created
       - `proxy-watchdog` was `enabled + active`
       - The first main menu after installation opened normally; the default generated `sing-box` minimal config could start
  3. **Update chain verification (real TTY)**:
     - After writing `.pat` for the restored remote installation, executed:
       - `sudo bash /etc/shell-proxy/self_update.sh repo`
     - The updater completed the full chain normally:
       - Successfully downloaded `env.sh / self_update.sh`
       - Successfully fetched the remote manifest
       - Successfully compared `48` managed files
       - Returned "Already up to date (48 files all matched)"
     - Post-update confirmation:
       - `/etc/shell-proxy/.script_source_ref` was recorded as `repo:97303b13...`
  4. **Basic function re-verification (minimal sample)**:
     - `proxy status`:
       - `sing-box.service` was `active`
       - `proxy-watchdog.service` was `active`
       - `shadow-tls-v3` prompted to skip as expected when unconfigured
     - Main menu first screen:
       - `printf "0\n" | sudo proxy` normally displayed version `97303b13`, system/arch/network stack, menu items and return entry
       - No missing modules, bundle fallback errors, or source failures
     - `11) Script Update` entry:
       - `11 -> 2(repo)` could normally enter the "Script Update" submenu
       - Returned "Already up to date"
     - Read-only menu chain:
       - `7) View Config` could normally enter and return to the main menu
  5. **On-site cleanup**:
     - Remote temporary install directory was cleaned; `~/proxy-install` was not retained.

- **Conclusions**:
  1. The current code baseline can restore installation from an empty environment on `gcp-oregon` and successfully enter the real `self_update` chain.
  2. The `install -> self_update -> main menu -> read-only menu` minimal main chain did not reveal any missing modules, bundle fallback anomalies, or basic interaction regressions in this round.
  3. This round was closer to "restore installation + update verification" rather than "incremental update on an existing production environment"; for future pure incremental verification, `self_update.sh repo` can be re-executed directly on the currently restored remote installation, or re-verified after the next real code change.

##### u-2-95 Multi-user scenario triple-issue fix (2026-03-11)
> **Target**: Investigate and fix three related issues found in multi-user environments: slow membership cache rebuilding during protocol install sessions, lack of step-by-step progress visibility during the flush phase, and subscription management only showing user1's links.

- **Problem Background**: When managing multiple users simultaneously in production (user1 + user2 + user3), the following appeared after adding/modifying protocols: (1) noticeable slowdown during installation; (2) "Applying installation changes..." displayed for a long time with no sub-step output; (3) `7) Subscription Management` menu only showed user1's links, other users' links were missing.

- **Root Cause Analysis & Fixes**:

  - **Problem 1 -- Membership cache repeatedly rebuilt during install session (`user_membership_ops.sh`)**:
    - **Root Cause**: Each time an inbound was written to the conf file, `proxy_user_derived_cache_refresh` triggered `proxy_user_membership_cache_refresh`, which performed a full O(inbounds) jq scan on all inbounds. In multi-user scenarios, inbound count multiplied, and the install session wrote multiple times, causing this scan to be called repeatedly during the session.
    - **Fix** (`modules/user/user_membership_ops.sh`, beginning of `proxy_user_derived_cache_refresh`): When `PROTOCOL_INSTALL_SESSION_ACTIVE == 1` and `PROXY_USER_DERIVED_CACHE_FP` already has a value, directly `return 0` to skip rebuilding, retaining the existing cache from session start. The first call after session end will still perform a full refresh.
    ```bash
    if [[ "${PROTOCOL_INSTALL_SESSION_ACTIVE:-0}" == "1" \
        && -n "${PROXY_USER_DERIVED_CACHE_FP:-}" ]]; then
        return 0
    fi
    ```

  - **Problem 2 -- Single outer spinner swallowed all sub-step output during flush phase (`protocol_install_singbox_ops.sh`)**:
    - **Root Cause**: `protocol_install_session_flush` wrapped the entire `flush_now` inside a `proxy_run_with_spinner`. `proxy_run_with_spinner` runs the command as a background subprocess with stdin/stdout redirected to temp files, causing `proxy_prompt_tty_available` to return false inside the subprocess, suppressing all nested progress messages (routing rule sync, `config_apply_sync`'s own "sing-box restarting..." spinner) -- users could only see the outer spinner spinning until completion.
    - **Fix 1** (`protocol_install_session_flush`): Removed the outer spinner wrapper; directly calls `protocol_install_session_flush_now`, letting each sub-step's native output print directly to the terminal.
    - **Fix 2** (`protocol_install_session_apply_pending_metadata`): Added `yellow "Syncing routing rules..."` prompt before calling `sync_user_template_route_rules`, making the routing sync step visible to users.

  - **Problem 3 -- Subscription management only showed user1's links (`share_ops.sh`)**:
    - **Root Cause**: `manage_share()` read the old `cached_render_fp` from `.render-cache.fp` and passed it directly as `render_fp_override` into `subscription_share_view_cache_is_fresh`. `subscription_share_view_state_fingerprint` used the override value as-is to construct the state hash, skipping real-time reading of the current render cache (`.render-user-sing.map` / `.render-user-surge.map` / `.render-users`), causing the state hash to still match the old `.share-view.fp` after new users joined, and the text view cache was falsely judged as fresh, returning the old subscription list containing only user1.
    - **Fix** (`modules/subscription/share_ops.sh`, `manage_share` function, before the freshness check): Call `calc_subscription_render_fingerprint` to compute the real-time `live_render_fp` before the freshness judgment, using it to replace `cached_render_fp` as the override, ensuring the state hash reflects the actual render cache content.
    ```bash
    local live_render_fp=""
    live_render_fp="$(calc_subscription_render_fingerprint "$share_host" "$conf_file" 2>/dev/null || true)"
    if ! subscription_share_view_cache_is_fresh "$share_host" "$conf_file" "${live_render_fp:-$cached_render_fp}"; then
    ```

- **Files Involved**:
  - `modules/user/user_membership_ops.sh` -- Problem 1 fix
  - `modules/protocol/protocol_install_singbox_ops.sh` -- Problem 2 fix
  - `modules/subscription/share_ops.sh` -- Problem 3 fix
  - `proxy/docs/dev/checklist.md` -- u-2-95 marked as `[x]`, with complete root cause analysis and minimal repro sample

- **Conclusions**:
  1. All three issues are cache/visibility defects under multi-user scenarios, not easily triggered in single-user scenarios.
  2. All fixes are minimal local changes that do not affect single-user paths or existing test cases.
  3. Problem 1 fix leverages the existing `PROTOCOL_INSTALL_SESSION_ACTIVE` lifecycle flag, introducing no new global state.
  4. Problem 2 fix retains `config_apply_sync` and each sub-function's own spinner, only removing the incorrect outer wrapper.
  5. Problem 3 fix completely eliminates the override bypass misjudgment path by computing the fingerprint in real-time at the judgment point.


##### u-2-96 perf: protocol install latency, routing-management stalls, and subscription-refresh decoupling (2026-03-11)
> **Target**: Locate and fix three remaining performance bottlenecks in multi-user / multi-protocol environments: (1) CPU spike during protocol install flush, (2) routing management menu stalls on entry and after rule changes, (3) subscription cache incorrectly invalidated by routing-rule commits.

- **Root Cause Analysis**:

  - **Issue 1 -- Route sync cache invalidated by route-only conf_file changes (`user_route_ops.sh`)**:
    - **Root Cause**: `routing_user_template_route_sync_input_fingerprint` used `calc_file_fingerprint "$conf_file"` (sha256 of full conf_file) in its cache key. Every time `routing_apply_rules_change` or `sync_user_template_route_rules` wrote to conf_file (modifying route.rules/dns sections), the sha256 changed, invalidating the sync cache even though inbounds (the only input route sync actually depends on) were unchanged. This forced expensive recompilation: O(users) jq calls for rule building, conf_file jq rewrite, and `restart_singbox_if_present`.
    - **Fix**: Replaced `calc_file_fingerprint "$conf_file"` with `jq -c '.inbounds // []' "$conf_file" | cksum` in the cache key. Bumped schema `user-route-sync-v3` -> `user-route-sync-v4`. Route-only conf_file writes no longer trigger sync recompilation.

  - **Issue 2a -- Routing menu entry stall (`routing_menu_support_ops.sh`)**:
    - **Root Cause**: When selecting "Configure Routing" (option 2), `routing_prepare_target_user_selection_context_with_spinner` blocked on `proxy_user_derived_cache_refresh`, which performed an O(inbounds) jq membership scan when conf_file mtime was stale. After protocol installs or routing changes, the cache was always stale.
    - **Fix**: Added background pre-warming of `routing_prepare_target_user_selection_context` at each `manage_routing_menu` loop iteration start. While the user reads the menu, the background process warms the disk membership cache. When option 2/4 is selected, the foreground call hits warm caches.

  - **Issue 2b -- Post-commit routing apply stall (`routing_core_ops.sh`)**:
    - **Root Cause**: `routing_commit_state_change` called `routing_status_refresh_all_contexts_sync` (synchronous) after committing routing changes, preferring sync over async. This added blocking wait on top of the already-expensive `sync_user_template_route_rules` + sing-box restart chain.
    - **Fix**: Reversed the preference order: now calls `routing_status_schedule_refresh_all_contexts` (async) when available, falling back to sync only if the async variant is not declared. The status refresh runs in the background while the user returns to the menu.

  - **Issue 3 -- Subscription cache invalidated by routing changes (`subscription_ops.sh`)**:
    - **Root Cause**: `calc_subscription_render_fingerprint` used `calc_file_meta_signature "$conf_file"` (mtime+size of full conf_file) and `calc_file_meta_signature "$USER_META_DB_FILE"` (mtime+size of full user-meta). Routing commits changed both files: conf_file via `routing_apply_rules_change` (route.rules/dns rewrite), USER_META_DB via `sync_user_template_route_rules` (template binding pruning). This invalidated the subscription render cache even though subscription links only depend on inbound protocol state and usernames, not routing rules or template bindings.
    - **Fix**: Replaced `conf_fp` with `jq -c '.inbounds // []' "$conf_file" | cksum` (inbounds-only fingerprint). Replaced `user_meta_fp` with `jq -c 'del(.template)' "$USER_META_DB_FILE" | cksum` (excludes routing template bindings). Bumped schema `subscription-render-v2` -> `subscription-render-v3`. Subscription cache is now fully decoupled from routing state.

- **Files Modified**:
  - `modules/subscription/subscription_ops.sh` -- Issue 3 fix
  - `modules/user/user_route_ops.sh` -- Issue 1 fix
  - `modules/routing/routing_core_ops.sh` -- Issue 2b fix
  - `modules/routing/routing_menu_support_ops.sh` -- Issue 2a fix
  - `proxy/docs/dev/checklist.md` -- u-2-96 marked as `[x]`
  - `proxy/docs/dev/workflow.md` -- execution record archived

- **Conclusions**:
  1. All four fixes target cache invalidation precision -- narrowing fingerprint scope so unrelated changes no longer trigger expensive rebuilds.
  2. Issue 3 fix is the highest-impact change: subscription management no longer triggers cold renders after routing-rule edits.
  3. Issue 1 fix eliminates redundant route sync recompilation when only routing rules changed (not inbounds), reducing CPU load during protocol install flush.
  4. Issue 2a/2b fixes are complementary: pre-warming moves blocking work off the critical path, async status refresh removes post-commit wait.
  5. All fixes are backward-compatible: schema version bumps ensure stale caches are invalidated on first run after update.

##### u-2-97 perf: user management menu loading delay and rename double-restart elimination (2026-03-11)
> **Target**: Fix two performance issues in User Management: (1) long loading time after selecting sub-options, (2) excessive wait when renaming a username due to double sing-box restart.

- **Root Cause Analysis**:

  - **Issue 1 -- User menu sub-option loading delay (`user_ops.sh`)**:
    - **Root Cause**: `manage_users()` had no background pre-warming. When any sub-option (list/rename/delete) is selected, `user_menu_prepare_action` calls `proxy_user_group_sync_from_memberships "$conf_file"` which performs a full O(inbounds) jq membership scan when the fingerprint is stale. This blocked the user on every menu action selection.
    - **Fix**: Added `proxy_user_group_sync_from_memberships "$conf_file" >/dev/null 2>&1 &` at the top of the `manage_users` while-loop, before `ui_clear`. While the user reads the menu, the background process warms the disk membership cache. When a sub-option is selected, the foreground call hits warm caches. This mirrors the routing menu pre-warming pattern from u-2-96.

  - **Issue 2 -- Rename wait caused by double sing-box restart (`user_batch_ops.sh`)**:
    - **Root Cause**: `finalize_user_group_batch()` called `restart_singbox_if_present` first (2-8s), then when `sync_routes=1`, called `sync_user_route_rules` which internally triggers another `restart_singbox_if_present` inside `sync_user_template_route_rules` (`user_route_ops.sh:1003`) when conf_file changes. This caused two sequential sing-box restarts totaling 4-16s. The rename flow calls `finalize_user_group_batch(1)`, always hitting this double restart path.
    - **Fix**: Reordered `finalize_user_group_batch` to run `sync_user_route_rules` BEFORE the explicit restart when both `sync_routes=1` and `BATCH_CONF_CHANGED=1`. Uses `calc_file_meta_signature` before/after the sync to detect whether the sync already restarted sing-box (conf_file changed = sync wrote new conf and restarted). If so, skips the explicit `restart_singbox_if_present`. When `sync_routes=0` or `BATCH_CONF_CHANGED=0`, behavior is unchanged.

- **Files Modified**:
  - `modules/user/user_ops.sh` -- Issue 1 fix (background pre-warming)
  - `modules/user/user_batch_ops.sh` -- Issue 2 fix (double restart elimination)
  - `proxy/docs/dev/checklist.md` -- u-2-97 marked as `[x]`
  - `proxy/docs/dev/workflow.md` -- execution record archived

- **Conclusions**:
  1. Issue 1 fix applies the same background pre-warming pattern proven in u-2-96 (routing menu). Membership cache is warmed while the user reads the menu, eliminating blocking jq scans on action selection.
  2. Issue 2 fix eliminates a redundant 2-8s sing-box restart by reordering operations: route sync runs first (which may restart sing-box internally if conf changes), then the explicit restart is skipped if the sync already restarted. This halves the rename wait time from 4-16s to 2-8s.
  3. Both fixes are backward-compatible and require no schema version changes.

##### u-2-98 bugfix: DNS auth_user not synced with route auth_user after username changes (2026-03-11)
> **Target**: Fix DNS rules retaining stale numeric `auth_user` values (e.g., `"1"`, `"2"`, `"3"`) while route rules have correct usernames (e.g., `"user1"`, `"user2"`, `"user4"`).

- **Root Cause Analysis**:
  - `routing_managed_rules_dns_shape_fingerprint` (`user_route_ops.sh:327`) computes a fingerprint of compiled route rules to decide whether DNS re-sync is needed. The fingerprint normalized rules to `{action, outbound, rule_set, domain, ...}` but **excluded `auth_user`**. When `sanitize_singbox_inbound_user_names_if_needed` updated inbound user names (changing `auth_user` in route rules from numeric IDs to proper display names), the DNS shape fingerprint was unchanged. This caused `need_dns_sync=0` at line 949-950, skipping `sync_dns_with_route`. DNS rules retained the old numeric `auth_user` values.

- **Fix**:
  - Added `auth_user` to the normalized shape map and sort key in `routing_managed_rules_dns_shape_fingerprint`. Username changes now produce a different DNS shape fingerprint, triggering DNS rule re-sync.

- **Files Modified**:
  - `modules/user/user_route_ops.sh` -- added `auth_user` to DNS shape fingerprint
  - `proxy/docs/dev/checklist.md` -- u-2-98 marked as `[x]`
  - `proxy/docs/dev/workflow.md` -- execution record archived

- **Conclusions**:
  1. The bug manifested after username sanitization (rename or inbound user-name normalization) changed `auth_user` in route rules without triggering DNS re-sync.
  2. The fix ensures any change to `auth_user` in route rules is detected by the DNS shape fingerprint, forcing DNS rules to be rebuilt with matching usernames.

##### u-2-99 perf: background-job accumulation causing transient CPU spikes and menu lag (2026-03-11)
> **Target**: Identify which background job families stack during menu usage, quantify CPU cost, and add concurrency control so transient bursts do not degrade interactive menu responsiveness.

- **Investigation**:
  - Audited all 12 background job launch sites across 7 files in `server/install/modules/`.
  - Categorized by concurrency control: **locked** (flock/mkdir guard) vs **unlocked** (bare `&`).
  - Found 2 unlocked per-loop-iteration warmup jobs that accumulate without bound:
    1. `user_ops.sh:75` — `proxy_user_group_sync_from_memberships "$conf_file" &` in `manage_users` while-loop
    2. `routing_menu_support_ops.sh:362` — `routing_prepare_target_user_selection_context "$conf_file" &` in `manage_routing_menu` while-loop
  - Both run in subshells (backgrounded with `&`), so parent shell cache variables are never updated by the child. The fingerprint guard inside each function (`PROXY_USER_GROUP_SYNC_FP`, `PROXY_USER_DERIVED_CACHE_FP`) only protects within a single process — each new background subshell starts with a stale fingerprint and performs full work.
  - All other background job sites already have proper locks:
    - `routing_status_schedule_refresh_all_contexts` — flock/mkdir
    - `protocol_menu_cache_schedule_rebuild` → `protocol_menu_cache_rebuild_with_lock` — mkdir
    - `routing_test_effect_schedule_refresh` — mkdir
    - `config_apply_async_init` — lock file
    - `singbox_autoconfig_schedule_reconcile_if_stale` — defined but never called
    - `proxy_run_with_spinner` / `proxy_run_with_spinner_compact` — single-use, self-limiting

- **Fix**:
  - Wrapped both unlocked warmup jobs in mkdir-based lock subshells:
    - `user_ops.sh`: `mkdir "${CACHE_DIR}/.user_menu_warmup.lock.d" || exit 0` before work, `rmdir` after
    - `routing_menu_support_ops.sh`: `mkdir "${CACHE_DIR}/.routing_menu_warmup.lock.d" || exit 0` before work, `rmdir` after
  - If a previous background instance is still running (lock dir exists), the new spawn exits immediately. This caps concurrent instances to 1 per warmup family.

- **Files Modified**:
  - `modules/user/user_ops.sh` — user menu warmup lock
  - `modules/routing/routing_menu_support_ops.sh` — routing menu warmup lock
  - `proxy/docs/dev/checklist.md` — u-2-99 marked as `[x]`
  - `proxy/docs/dev/workflow.md` — execution record archived

- **Conclusions**:
  1. The accumulation was caused by two unlocked per-iteration background jobs in menu loops. Each loop iteration spawned a new subshell that couldn't benefit from the parent's in-memory cache (subshell isolation), so every instance did full O(inbounds) jq work.
  2. The mkdir lock pattern is lightweight (single syscall), consistent with existing codebase conventions, and caps concurrent warmup instances to 1.
  3. No other background job families were found to lack concurrency control.

##### u-2-100 release: publish GitHub release v1.1.0 from the latest tagged baseline (2026-03-11)
> **Target**: Cut the formal `v1.1.0` release from commit `c462c3e66fd7ce0d45361cb34f4b1f0cc921c5e9`, publish the GitHub release page, and sync repository version metadata.

- **Execution Log**:
  1. Confirmed the latest existing formal tag was still `v1.0.0`, and no `v1.1.0` GitHub release existed.
  2. Chose `c462c3e66fd7ce0d45361cb34f4b1f0cc921c5e9` as the `v1.1.0` release baseline because it already included the full `u-2-91` to `u-2-99` workset.
  3. Updated `README.md` and `AGENTS.md` so the repository now declares `v1.1.0` as the current formal release baseline and treats `main` as post-`v1.1.0` continuous development.
  4. Created and pushed annotated tag `v1.1.0`, then published the matching GitHub release page with a concise release summary.

- **Release Highlights**:
  - High-ceiling menu/loading architecture refactor became the `v1.1.0` baseline.
  - Routing and subscription hot paths were further decoupled and shortened in multi-user scenarios.
  - User management and DNS synchronization regressions were fixed.
  - Background warmup jobs now have explicit concurrency guards, preventing transient CPU spikes and menu lag.

- **Files Modified**:
  - `proxy/README.md` -- updated formal release baseline to `v1.1.0`
  - `proxy/AGENTS.md` -- updated formal release baseline to `v1.1.0`
  - `proxy/docs/dev/checklist.md` -- archived `u-2-100`
  - `proxy/docs/dev/workflow.md` -- archived release execution record

##### u-2-101 regression: gcp-oregon clean install and interactive menu verification with issue archiving (2026-03-14)
> **Target**: Execute a clean remote install/verification cycle on `gcp-oregon`, traverse the main interactive menu chains end-to-end, and archive any blockers or regressions found.

- **Execution Log**:
  1. Started from an existing install, entered `12) Uninstall Service` through a real TTY, and confirmed the machine was clean after removal (`/etc/shell-proxy` and `/usr/bin/proxy` absent).
  2. Attempted the documented private bootstrap with the provided PAT. The documented raw bootstrap URL for `app/bootstrap.sh` returned `HTTP 404`, so the private-bootstrap entry did not run.
  3. Copied the local `app/` tree to `/tmp/shell-proxy-app` on `gcp-oregon` and ran `install.sh` with the same PAT. Dependency/core installation advanced normally, but `install_control_script()` failed at `解析仓库提交失败: dhwang2/shell-proxy@main`.
  4. Verified the PAT transport at HTTP level on `gcp-oregon`: both the raw bootstrap URL and the GitHub API `repos/dhwang2/shell-proxy/commits/main` endpoint returned `404`, confirming a private-repo auth/access problem rather than a local quoting error.
  5. Re-ran `install.sh` without PAT using the local script-copy fallback. This completed successfully and restored `/etc/shell-proxy`, `/usr/bin/proxy`, and a working `proxy` menu.
  6. Interactive menu verification passed for these paths:
     - `3) User Management -> 2) Add User`
     - `1) Install Protocol -> 4) ss`
     - `4) Routing Management -> 2) Configure Routing -> 1) Add Rule`
     - `6) Subscription Management`
     - `7) View Configuration -> 1) sing-box`
     - `2) Uninstall Protocol`
     - read-only checks for `5) Protocol Management`, `8) Runtime Logs`, `9) Core Management`, and `10) Network Management`
  7. Cleaned up the verification artifacts after the run. The test protocol and test user were removed via menu actions. One orphan user-bound route rule remained in `sing-box.json`, so it was removed manually from `route.rules` and `dns.rules`, and routing/view caches were cleared to restore a clean `0-rule` state.

- **Findings**:
  1. **Blocking install issue -- PAT-based private install path unavailable**:
     - The documented raw bootstrap URL returned `404` even with the provided PAT.
     - The GitHub API `commits/main` endpoint also returned `404` with the same PAT.
     - Result: both the documented bootstrap path and the PAT-based repo-fetch branch inside `install_control_script()` are currently blocked.
  2. **Menu regression -- default `ss` password path fails**:
     - In `Install Protocol -> ss`, leaving the password prompt empty should accept the internally generated default key.
     - Actual result: the flow failed with `密码格式无效：需要 Base64 编码的有效 ss 2022 密钥。`
     - Workaround used for the run: supplied a known-valid Base64 key manually.
  3. **Menu/data regression -- orphan routing rule after last protocol/user removal**:
     - After uninstalling the only protocol and then deleting the empty test user, the dashboard still reported `1` rule and `sing-box.json` still contained `route.rules` / `dns.rules` entries bound to the deleted username.
     - The top-level routing summary still displayed the rule, but `Configure Routing` for that username no longer exposed it for deletion.
     - Result: this path cannot fully clean or recover the leftover rule through the current menu flow; manual config cleanup was required.

- **Cleanup State**:
  - Final remote state restored to: installed `shell-proxy`, no verification users, no active protocols, `0` routing rules, and `sing-box` running.
  - Final `user-management.json` state is empty for `groups`, `route`, `template`, and `name`.

- **Conclusions**:
  1. The main interactive menu flows are runnable on `gcp-oregon` once the scripts are present locally.
  2. The private-repo install chain is currently blocked by PAT/repository access failure and must be fixed before the documented bootstrap path can be considered valid.
  3. The `ss` default-password path and the orphan routing-rule cleanup path both require code fixes before this scenario can be considered regression-free.

##### u-2-102 fix: repair private install/update paths, correct bootstrap entry, and re-verify remote flows (2026-03-14)
> **Target**: Re-verify the PAT after the permission update, ship the install/update path fixes to `shell-proxy/main`, and execute another remote validation round on `gcp-oregon` covering bootstrap, script update, and the previously reported menu issues.

- **Execution Log**:
  1. Re-checked the provided PAT on both the local machine and `gcp-oregon`. The GitHub API `commits/main` endpoint returned `200`, the private raw bootstrap endpoint returned `200`, and the tarball endpoint returned the expected `302` redirect. This confirmed the PAT/auth problem from `u-2-101` had been resolved.
  2. Confirmed that the install/update path fixes already existed in the local `shell-proxy` worktree but had not yet been pushed to GitHub. Committed and pushed them as `64c8a2ac2ca3d429ae994469586a1a931cc1206d` (`fix: repair private install/update paths and user-route cleanup`).
  3. Found a new bootstrap-entry issue unrelated to PAT: `raw.githubusercontent.com/.../main/app/bootstrap.sh` still served stale branch content during the validation window, while the commit-pinned raw URL already served the new script. To avoid relying on branch-cache freshness, updated the documented bootstrap entry to use the GitHub Contents API with `Accept: application/vnd.github.raw`.
  4. Re-ran the remote install on `gcp-oregon` using the GitHub Contents API bootstrap entry. The install completed, `/etc/shell-proxy` and `/usr/bin/proxy` were restored, and the main menu version now reported the pushed source ref short SHA `64c8a2ac`.
  5. Executed a real TTY menu validation for `11) Script Update -> 2. repo` through `ssh -tt`. The update chain completed with `已是最新版本 (48 文件均一致)`, and `/etc/shell-proxy/.script_source_ref` was written as `repo:64c8a2ac2ca3d429ae994469586a1a931cc1206d`.
  6. Re-ran `Install Protocol -> ss` with the password prompt intentionally left blank. The installation succeeded normally, confirming that the `u-2-101` “default ss password invalid” finding was caused by an earlier automation input shift, not by a code regression.
  7. Re-validated orphan `auth_user` cleanup on the remote machine in two layers:
     - The runtime sync path (`sync_user_template_route_rules`) now removed orphan `auth_user` route and DNS rules from `sing-box.json`.
     - The user-delete path now explicitly calls `proxy_user_route_purge_deleted_name_state`, ensuring empty-user deletion can purge leftover username-bound route state.

- **Fixes Shipped**:
  1. Private install/update archive extraction now resolves the real install source under `app/` instead of assuming repo-root `install.sh` / `env.sh` paths.
  2. `self_update` bootstrap and managed-file download logic now resolves remote files under `app/`, including Tree API diff lookups.
  3. Deleted-user cleanup now purges username-bound route/DNS state instead of leaving orphan `auth_user` rules behind.
  4. The public-facing private bootstrap command in `README.md` and the inline example in `app/bootstrap.sh` now use the GitHub Contents API raw response, avoiding stale `raw .../main/...` branch-cache reads.

- **Corrected Findings**:
  1. The PAT failure reported in `u-2-101` is no longer valid after the permission update; current PAT access is healthy.
  2. The `ss` blank-password install path is working; the earlier failure was an automation artifact, not a product bug.
  3. The remaining meaningful issue from `u-2-101` was the orphan routing-state cleanup path, which has now been fixed and re-validated at the remote runtime/config layer.

- **Conclusions**:
  1. PAT-gated private access is restored, and the remote install/update chain is working again once the bootstrap entry avoids stale branch-cache content.
  2. `11) Script Update -> 2. repo` now works correctly against the pushed `64c8a2ac` baseline and records the expected script source ref on disk.
  3. The original `ss` password finding should be treated as superseded by this re-verification round; the true code fixes in this cycle are the `app/` path convergence and orphan route cleanup.

##### u-2-103 bugfix: ghost "user" group appearing in user list with no protocols (2026-03-14)
> **Target**: Identify the root cause of the spurious "user" entry in the user list (`[Protocols: -]`) and eliminate both the server-side data corruption and the code paths that produced it.

- **Investigation**:
  1. SSHed to `gcp-oregon` and inspected `/etc/shell-proxy/user-management.json`. Found a `groups["user"]` entry (`created_at: 2026-03-14T02:07:15Z`) with no corresponding `.name[key]` entries — confirming the ghost was not linked to any active or disabled protocol.
  2. Confirmed the sing-box config had no users named "user"; all six inbound user objects mapped to `user1` or `user2`.
  3. Traced `proxy_user_group_add` in `user_meta_ops.sh`: the function normalizes its input before the empty guard, so `proxy_user_group_add ""` executes `normalize_proxy_user_name("") → "user"` and then writes `groups["user"]` without any protocol binding.
  4. Found two eager `proxy_user_group_add` calls in `protocol_install_singbox_ops.sh` (line 107 in `modify_singbox_inbounds_logic`, line 1225 in `modify_snell_config`) that fire immediately after user selection — before any protocol is installed. If the user cancels the install after this point, the group entry is left orphaned.

- **Fixes**:
  1. `user_meta_ops.sh / proxy_user_group_add`: added `[[ -n "${name//[[:space:]]/}" ]] || return 1` before the `normalize_proxy_user_name` call to reject empty/whitespace raw input.
  2. `protocol_install_singbox_ops.sh`: removed the eager `proxy_user_group_add` calls from both `modify_singbox_inbounds_logic` and `modify_snell_config`; `proxy_user_meta_apply_protocol_membership` already creates the group atomically on successful install, making these calls redundant and dangerous.
  3. `gcp-oregon / user-management.json`: removed the orphaned `groups["user"]` entry with `jq del`; backed up the original file first.
  4. Rebuilt all bundles on `gcp-oregon` by sourcing `bundle_build_ops.sh` directly; verified `proxy_user_group_add` guard and removal of eager calls in the rebuilt `protocol-menu.bundle.sh` and `user-menu.bundle.sh`.

- **Verification**:
  - `jq '.groups | keys' /etc/shell-proxy/user-management.json` returns `["user1","user2"]` only.
  - Protocol-menu bundle no longer contains an eager `proxy_user_group_add` call after user selection in either the singbox or snell install paths.
  - `proxy_user_group_add` function in both `user-menu.bundle.sh` and `protocol-menu.bundle.sh` now rejects empty input before normalization.

- **Commit**: `b3847ae` — `fix: prevent ghost user group creation`

##### u-2-104 fix: routing menu freeze caused by subprocess spinner discarding variable state (2026-03-14)
> **Target**: Eliminate intermittent freezes in the routing menu "配置分流" flow on low-memory servers by fixing the spinner subprocess pattern that silently discarded variable results.

- **Investigation**:
  1. User reported intermittent freezes when accessing "4) 分流管理 → 2. 配置分流" on `gcp-oregon` (1GB RAM, no swap).
  2. Traced the flow: `routing_prepare_target_user_selection_context_with_spinner` calls `proxy_run_with_spinner_compact`, which runs the work function in a background subprocess (`"$@" &`). The work function sets `ROUTING_TARGET_USER_SELECTION_NAMES_TEXT` — but since it runs in a subprocess, the variable assignment is lost in the parent shell.
  3. `routing_select_target_user_name` finds the variable empty, falls back to `proxy_user_collect_names` which re-executes the full `proxy_user_derived_cache_refresh` (jq parsing of `sing-box.json`, group sync, membership cache rebuild) in the foreground — without any spinner feedback. On a 1GB machine, this silent re-execution plus potential concurrent background warmup creates visible freezes.
  4. Same issue affects `routing_prepare_full_support_with_spinner` — module loading flags set in subprocess are lost.

- **Fixes**:
  1. `common_ops.sh`: added `proxy_run_with_spinner_fg` — runs the spinner animation in a background process and the actual work in the foreground. Variable assignments, cache state, and module loading flags all persist in the parent shell.
  2. `routing_menu_support_ops.sh`: switched both `routing_prepare_target_user_selection_context_with_spinner` and `routing_prepare_full_support_with_spinner` from `proxy_run_with_spinner_compact` to `proxy_run_with_spinner_fg`.

- **Verification**:
  - Rebuilt bundles on `gcp-oregon`; confirmed `proxy_run_with_spinner_fg` function present in `base.bundle.sh` and routing menu bundle references updated.
  - Ran `4) 分流管理 → 2. 配置分流 → user1` flow: spinner displayed during loading, user list appeared immediately after spinner completed with no freeze.

- **Commit**: `cf5319c` — `fix: use foreground spinner for routing menu variable-setting operations`

##### u-2-105 ux: remove redundant prompts during option configuration (2026-03-14)
> **Target**: Trim verbose, repetitive, or unnecessary prompts across all interactive menu flows to make the UI concise and to the point.

- **Changes**:
  1. `config_ops.sh / prompt_select_index`: shortened "按回车返回......" to "回车返回" — this function is used by 4 callers across routing, user, and membership modules.
  2. `protocol_install_singbox_ops.sh`: shortened "选择要为 X 安装的用户名" → "选择用户名 (X)"; shortened "检测到已有...默认复用" → "复用已有..."; shortened "选择要复用的" → "选择"; collapsed two-line pending-changes warning to single line; shortened "请先进入用户管理，添加用户名后再安装协议" → "请先添加用户名"; removed duplicate reuse success message; deleted "待生效" banner; changed flush message to "正在应用新配置文件(...)".
  3. `protocol_ops.sh`: shortened "选择要卸载 X 的用户名" → "选择用户名 (卸载 X)".
  4. `routing_menu_support_ops.sh`: shortened "选择要配置分流规则的用户名" → "选择用户名 (配置分流)"; shortened "选择要测试分流效果的用户名" → "选择用户名 (测试分流)".
  5. `user_ops.sh`: shortened "选择要删除的用户名" → "选择用户名 (删除)"; shortened "选择要重命名的用户名" → "选择用户名 (重命名)"; fixed display bug in `add_user_group` — stray "按回车返回......" before username input prompt.
  6. `share_ops.sh`: removed "说明：" header and numbered list format from subscription notes; rendered as dim gray inline text instead; removed verbose empty-state explanation block.
  7. Removed verbose subtitles from 10 menu headers: 用户管理, 订阅管理, 内核管理, 运行日志, 配置详情, sing-box 配置, 协议服务状态, 网络管理, BBR 网络优化, 分流管理. Shortened 添加协议 subtitle to "退出时统一生效".
  8. Standardized all remaining "按回车返回......" → "回车返回" across all modules: `common_ops.sh` (pause function), `bootstrap_ops.sh`, `routing_ops.sh`, `routing_rule_menu_ops.sh` (4 instances), `routing_res_socks_ops.sh`, `log_ops.sh`, `network_ops.sh`, `network_firewall_ops.sh`.
  9. Updated `.claude/rules/archive.md` with mandatory real-world menu verification constraint — requires interactive testing on target server after any UI-affecting `app/` changes.

- **Verification**:
  - Validated `bash -n` on all 16 modified files.
  - Deployed to `gcp-oregon`, rebuilt bundles, and performed real-world menu interaction verification:
    - Main menu renders correctly with all 12 options.
    - User management: header without subtitle, "回车返回上一层" hint, user list shows "回车返回".
    - Add user: no stray "按回车返回......" before username input (display bug fixed).
    - Routing menu: loads instantly (no freeze), displays routing rules and "回车返回" prompt.

- **Commit**: `cd16caf` — `ux: trim redundant prompts and verbose menu text`

##### u-2-106 ux: keep inbound-reuse success message on a single line (2026-03-14)
> **Target**: Make the "reuse existing inbound" success feedback render as a stable single-line message instead of fragmenting across multiple visual lines.

- **Execution Log**:
  1. Located the reuse-success output in `app/modules/protocol/protocol_install_singbox_ops.sh` immediately after `proxy_append_user_to_existing_inbound` completes.
  2. Replaced the custom `printf`-based colored output with a standard `green` call using the same message text: `已为用户名 ${target_name} 复用 ${proto_label} 入站: 端口 ${target_port:--}`.
  3. Removed the non-ASCII curly quotes that had slipped into that block and normalized the variable naming to `proto_label`.
  4. Re-validated the file with `bash -n` and checked whitespace/patch hygiene with `git diff --check`.

- **Files Modified**:
  - `app/modules/protocol/protocol_install_singbox_ops.sh` -- reuse-success message now emitted as a single-line `green` status line
  - `docs/dev/checklist.md` -- archived `u-2-106`
  - `docs/dev/workflow.md` -- archived execution record

- **Conclusions**:
  1. The message content is unchanged; only the rendering path was simplified.
  2. Using the shared `green` helper avoids formatting drift and prevents accidental multi-line splitting from the previous custom output implementation.

##### u-2-107 fix: self_update repo changed-file download must honor app/ source prefix (2026-03-14)
> **Target**: Fix the remaining `self_update repo` failure where the updater successfully resolved the latest commit and diffed managed files, but failed during the final changed-file download phase with `部分文件下载失败，请检查网络后重试。`

- **Root Cause Analysis**:
  1. `self_update.sh` had already been updated to use `repo_source_file_rel_path()` for the bootstrap files (`env.sh`, `self_update.sh`) and to use the `app/` tree prefix when querying the Git Trees API.
  2. However, the final parallel changed-file download loop still fetched `rel` directly from `${_DL_BASE_URL}/${rel}`.
  3. For managed files such as `management.sh` or `modules/protocol/protocol_install_singbox_ops.sh`, the real remote path is `app/<rel>`. As a result, the updater diff phase correctly detected changed managed files, but the actual file download hit `404` and only surfaced the generic `部分文件下载失败` message.

- **Fix**:
  1. `app/self_update.sh`: changed the parallel changed-file download list from a single `rel` column to `rel + source_rel`, where `source_rel` is produced by `repo_source_file_rel_path`.
  2. The worker now downloads from `${_DL_BASE_URL}/${source_rel}?v=${_DL_TS}` instead of `${_DL_BASE_URL}/${rel}?v=${_DL_TS}`.
  3. Added `_download_fail_list.txt` and print the failed relative file names before returning, so future remote failures point at the exact managed file instead of a generic network hint.

- **Remote Verification**:
  1. Pushed the fix as commit `8838746537ad909c35c06da31d98412f20c0b395`.
  2. Reinstalled the target machine from the latest bootstrap entry so the remote `self_update.sh` itself was upgraded to the fixed version baseline.
  3. Forced a real update scenario on the remote machine by:
     - writing `/etc/shell-proxy/.script_source_ref` back to `repo:28d0cfa...`
     - appending a local stale marker to `/etc/shell-proxy/management.sh`
  4. Ran the real menu chain via a pseudo-TTY: `11) Script Update -> 2. repo -> y`.
  5. The updater now completed successfully:
     - detected `management.sh` as the single changed managed file
     - downloaded and installed it successfully
     - switched into the new menu automatically
     - remote menu version changed from `28d0cfa2` to `88387465`
  6. Post-checks confirmed:
     - `/etc/shell-proxy/.script_source_ref` = `repo:8838746537ad909c35c06da31d98412f20c0b395`
     - the injected `# stale-local-marker` line was removed from `/etc/shell-proxy/management.sh`

- **Files Modified**:
  - `app/self_update.sh` -- fixed changed-file download source path and added failed-file reporting
  - `docs/dev/checklist.md` -- archived `u-2-107`
  - `docs/dev/workflow.md` -- archived execution record

- **Conclusions**:
  1. The remaining updater failure was not network instability; it was a path-resolution bug in the final changed-file fetch stage.
  2. `self_update repo` is now validated end-to-end through the real interactive menu path, including an actual stale-file repair, not just an “already up to date” no-op check.

##### u-2-108 refactor: prepare repository for public release (2026-03-15)
> **Target**: Remove all private-repository authentication dependencies so the repo can be made public without requiring a GitHub PAT for installation or updates.

- **Changes**:
  1. `app/bootstrap.sh`: rewrote as a public bootstrap script — removed PAT parameter, PAT prompt, and authenticated API calls; uses unauthenticated GitHub API for commit resolution and tarball download.
  2. `app/env.sh`: removed `TOKEN_FILE` constant and `get_auth_header()` function; renamed `PRIVATE_REPO` → `REPO_NAME`.
  3. `app/install.sh`: removed `PAT` parameter, `save_token()`, `download_private_repo_archive()`, `extract_private_install_tree()`; simplified `install_control_script()` to always use the local copy from the bootstrap extraction layer instead of branching on PAT presence.
  4. `app/self_update.sh`: removed all `auth_header` logic from `main()`, tree API call, and parallel download worker; renamed `PRIVATE_REPO` → `REPO_NAME`.
  5. `app/modules/core/release_ops.sh`: removed `get_auth_header` calls and auth-header branching from `github_api_branch_commit_sha()` and `github_api_latest_release_tag()`.
  6. `app/modules/core/bootstrap_ops.sh`: removed `auth_header` from `ensure_self_update_bootstrap()`; renamed `PRIVATE_REPO` → `REPO_NAME`.
  7. `app/modules/protocol/protocol_tls_ops.sh`: replaced placeholder `admin@gmail.com` → `user@example.com`.
  8. `AGENTS.md`: updated “private repository” → “public repository”; removed `with pat` from Tier 3 verification description.
  9. `.claude/rules/verification.md`: removed `with pat` from installation flow step.
  10. `README.md`: simplified installation command to `curl -fsSL ... | bash` (no PAT).
  11. `.gitignore`: added `/docs/`, `/.claude/`, `/AGENTS.md` to local-only exclusions.
  12. Git history: squashed all 27 commits into a single initial commit `719b584`; deleted tag `v0.0.0` and its GitHub release.

- **Verification**:
  - `bash -n` passed on all 7 modified `.sh` files.
  - No remaining references to `PRIVATE_REPO`, `get_auth_header`, `TOKEN_FILE`, or `auth_header` in `app/`.

- **Commits**: `5c49179`, `50921a6`, `42bda5a` → squashed to `719b584` — `Initialize shell-proxy public repository`

##### u-2-109 feat: add shell-proxy-verify skill and restructure verification tiers (2026-03-15)
> **Target**: Create a structured verification skill with modular, tagged procedures for every main menu option, replacing ad-hoc Tier 2/3 verification with dependency-aware module resolution.

- **Changes**:
  1. `.claude/skills/shell-proxy-verify/SKILL.md`: created skill with invocation interface (tier + changed-files), pre-flight steps (deploy, rebuild bundles, validate JSON), and 12 verification modules (VM-01 through VM-12) each defining handler, bundle group, source files, tags, dependencies, and step-by-step procedures with expected state checks.
  2. `.claude/skills/shell-proxy-verify/references/file-module-map.md`: maps all 37 module files from `proxy_all_module_rel_paths()`, 5 entry scripts, and 5 systemd templates to their affected VM modules; includes bundle group cross-reference table.
  3. `.claude/skills/shell-proxy-verify/references/dependency-graph.md`: formal dependency graph with weights (VM-03=10 down to VM-12=0), direct dependents lookup table, topological sort order, and weight rationale.
  4. `.claude/rules/verification.md`: replaced Tier 2/3 prose procedures with skill invocation references; replaced "How to verify" manual steps with skill-based workflow.
  5. `AGENTS.md`: added skill directory tree to directory structure; updated verification table Tier 2/3 columns to reference skill invocation.

- **Verification** (Tier 3 regression on `gcp-oregon`):
  - Pre-flight: bundles rebuilt, `sing-box.json` validated.
  - VM-03 (用户管理): `user-management.json` valid, groups intact.
  - VM-01 (安装协议): SS installed on port 8388; `systemctl is-active sing-box` = active; port listening (TCP+UDP); inbound in `sing-box.json`.
  - VM-05 (协议管理): protocol overview rendered, 4 service operations listed.
  - VM-04 (分流管理): routing menu rendered, exit status displayed, 4 routing options.
  - VM-06 (订阅管理): SS URI + Surge format subscription links rendered for user1.
  - VM-07 (查看配置): config view menu rendered, 3 config types listed.
  - VM-08 (运行日志): log menu rendered, 3 log types listed.
  - VM-02 (卸载协议): SS uninstalled; inbounds empty; port 8388 freed.
  - VM-09 (内核管理): core management rendered, 3 options available.
  - VM-10 (网络管理): network management rendered, 2 options available.
  - VM-11 (脚本更新): `.script_source_ref` = `719b584` confirmed.
  - VM-12 (卸载服务): skipped (destructive, not requested).
  - Result: 11/11 modules passed.

- **Commit**: `7811f45` — `Add shell-proxy-verify skill and restructure verification tiers`

##### u-2-110 ux: unify main menu separator lines to double-line light red style (2026-03-15)
> **Target**: Make all 5 separator lines in the main menu and protocol status display consistent in style and color.

- **Changes**:
  1. `app/management.sh`: replaced 3 separator lines (lines 349, 409, 522-527) — changed `─────` / `proxy_menu_divider` to direct `echo -e '\033[1;31m═════...═════\033[0m'` with light red color.
  2. `app/modules/runtime/runtime_status_ops.sh`: replaced 2 separator lines (lines 712, 715, 722) — changed `C_TITLE` (cyan) to `C_SEP` (light red `\033[1;31m`), changed `─────` to `═════`.

- **Verification**:
  - `bash -n` passed on both files.
  - Deployed to `gcp-oregon`, rebuilt bundles; all 5 separators render consistently in light red double-line style.

- **Commit**: `a1f88ac` — `Unify main menu separator lines to double-line style in light red`

##### u-2-111 bugfix+ux: ghost user guard, install protocol UX improvements (2026-03-15)
> **Target**: Prevent ghost "user" entries from appearing during protocol install, and streamline the install protocol UX with cleaner messages, spinner animation, and simplified prompts.

- **Investigation** (ghost user):
  1. Root cause: `proxy_user_meta_apply_protocol_membership` and `protocol_install_session_queue_membership` both called `normalize_proxy_user_name` before checking for empty input. `normalize_proxy_user_name("")` returns `DEFAULT_PROXY_USER_NAME` ("user"), so empty input silently created a "user" group entry.
  2. The existing guard in `proxy_user_group_add` (added in u-2-103) only covered direct group creation, not the membership/session-queue paths.

- **Fixes**:
  1. `app/modules/user/user_meta_ops.sh / proxy_user_meta_apply_protocol_membership`: added `[[ -n "${target_name//[[:space:]]/}" ]] || return 1` before `normalize_proxy_user_name` call.
  2. `app/modules/protocol/protocol_install_singbox_ops.sh / protocol_install_session_queue_membership`: added identical pre-normalization empty guard.
  3. Same file: replaced "添加成功，配置已写入。" + yellow deferred-restart warning with single-line `green "添加成功，已复用配置。"`.
  4. Same file: rewrote `protocol_install_session_flush_now` to use `proxy_run_with_spinner_fg "正在应用新配置文件..." protocol_install_session_flush_inner` with graceful fallback to static `yellow` message if spinner function is unavailable.
  5. Same file: simplified user selection prompt from `"选择用户名 (${selected_proto_label})"` to `"选择用户名"` in both singbox (line 102) and snell (line 1209) install paths.

- **Verification**:
  - `bash -n` passed on both modified files.
  - Deployed to `gcp-oregon`, rebuilt bundles; install protocol flow confirmed working with simplified prompts and spinner animation.

##### u-2-112 refactor: code review cleanup and structural deduplication (2026-03-15)
> **Target**: Address code quality, efficiency, and structural duplication issues identified by three-agent parallel review (/simplify), then resolve the remaining deferred items.

- **Phase 1 — Review findings and immediate fixes**:
  1. `proxy_run_with_spinner_fg` in `common_ops.sh:266` ran `"$@" >/dev/null 2>&1`, silently discarding all stdout/stderr from the work function — sub-step messages like route-sync status were invisible to the user. Fix: removed the redirect; spinner writes to `/dev/tty` so no collision.
  2. `protocol_install_session_flush_inner` was defined as a nested function inside `flush_now`, leaking to global scope on every call. Fix: hoisted to module scope as `_protocol_install_session_flush_inner()`.
  3. `surge_notes` array was vestigial after note removal. Fix: replaced with direct conditional `printf`.

- **Phase 2 — Structural deduplication**:
  1. `app/modules/subscription/share_ops.sh`: removed 3 verbose surge note lines. Extracted `_subscription_share_render_body()` using bash namerefs — accepts user array name, sing map name, and surge map name as arguments. Both `subscription_share_render_to_file` and `subscription_share_render_payload_to_file` now delegate to this single helper (~50 duplicated lines removed).
  2. `app/modules/protocol/protocol_install_singbox_ops.sh`: merged two identical `case` blocks for `selected_proto` and `selected_proto_label` into one — `selected_proto_label` is now derived as `"${selected_proto:-protocol}"`.
  3. `app/modules/core/common_ops.sh`: added `proxy_is_blank_string()` utility (one-liner: `[[ -z "${1//[[:space:]]/}" ]]`). Replaced 4 inline whitespace-guard patterns: `user_meta_ops.sh` (2 sites), `user_ops.sh` (1 site), `protocol_install_singbox_ops.sh` (1 site).

- **Verification**:
  - `bash -n` passed on all 5 modified files.
  - Deployed to `gcp-oregon`, rebuilt bundles successfully.

##### u-2-113 ux: unify all sub-menu separators and headers to 68-char standardized API (2026-03-15)
> **Target**: Eliminate all raw `echo "==="` and `echo "---"` separator patterns across the entire `app/modules/` tree, replacing them with the standardized `proxy_menu_header`, `proxy_menu_divider`, and `proxy_menu_rule` APIs at a consistent 68-char width.

- **Changes**:
  1. `app/modules/core/common_ops.sh`: updated default widths from 45→68 for `proxy_menu_rule`, `proxy_menu_header`, `proxy_menu_divider`; added `proxy_is_blank_string` utility.
  2. `app/management.sh`: redesigned main menu layout — 68-char `═` separators, centered title `shell-proxy 一键部署 [服务端]`, protocol display uses `/` separator, menu items right-aligned `(N)` in 8-char field.
  3. `app/modules/runtime/runtime_status_ops.sh`: matching main menu dashboard changes — 2-space status indent, `/` protocol separator, `+shadow-tls` token format.
  4. Raw `echo "==="` headers replaced with `proxy_menu_header` in 8 files (14 occurrences): `protocol_install_singbox_ops.sh` (snell sub-menu), `protocol_ops.sh` (uninstall), `routing_menu_support_ops.sh` (direct outbound, chain proxy, test routing), `routing_rule_menu_ops.sh` (add/delete/modify/configure rules), `routing_res_socks_ops.sh` (node picker, chain proxy config), `service_ops.sh` (uninstall service, protocol management), `network_firewall_ops.sh` (firewall convergence), `bootstrap_ops.sh` (script update).
  5. Raw `echo "---"` dividers replaced across 13 files: section dividers → `proxy_menu_divider` (thin `─`), menu footers before "回车返回" → `proxy_menu_rule "═"` (thick).
  6. All `proxy_menu_back_hint 45` calls updated to `proxy_menu_back_hint` (uses default 68) in `core_ops.sh`, `user_ops.sh`, `service_ops.sh`, `network_ops.sh`, `log_ops.sh`, `routing_menu_support_ops.sh`.
  7. `log_ops.sh`: replaced 2 `yellow "=== snell-v5/shadow-tls-v3 配置 ==="` with `proxy_menu_header`.

- **Verification**:
  - `bash -n` passed on all 15 modified `.sh` files.
  - Zero raw `echo "==="` or `echo "---"` dividers remain in `app/modules/`.

##### u-2-114 ux: streamline menus — remove pause/hints, reorder protocols, compact prompts (2026-03-15)
> **Target**: Remove all "回车返回" pause prompts, streamline menu interactions, and eliminate extra blank lines.

- **Changes**:
  1. Deleted `pause()` and all 60+ call sites across 16 files; deleted `pause_unless_cancelled` from `bootstrap_ops.sh`.
  2. Deleted `proxy_menu_back_hint` (zero callers). Kept `proxy_prompt_print` (used by `read_prompt`).
  3. Unified `prompt_select_index`: removed "回车返回" hint, prompt → "选择序号(回车取消):".
  4. Reordered install protocol menu: ss→vless→tuic→trojan→anytls→snell-v5, 2-space indent, remapped dispatch.
  5. Removed release/repo selection from script update — defaults to repo mode.
  6. Simplified chain proxy input: single-line Chinese format hint, removed yellow tip.
  7. Extended share divider 60→68 chars; double-space user separator in uninstall table.
  8. Removed 13 blank-line `echo` across 7 files and 5 `\n` prefixes from install headers.

- **Verification**:
  - `bash -n` passed on all 18 modified files.
  - Deployed to `gcp-oregon`, rebuilt bundles, verified menu interactions.
