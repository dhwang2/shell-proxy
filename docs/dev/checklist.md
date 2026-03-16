# shell-proxy Repository Tasks

## 0.0 Archiving Guidelines

1. **Mapping:** The tasks in the checklist and the execution records in the workflow must map to each other one-to-one. When writing, you must add: section mapping title, mapping sequence number, and mapping date to ensure tasks and execution records are synchronized.
2. **Prioritize Checklist:** The checklist tasks have the highest priority. If a task has not been executed, the workflow execution record should retain the task sequence number; if an execution record is an impromptu, extra execution and not recorded in the task, the task must first be added to the checklist.
3. **Hierarchical Archiving:** Archive separately according to the level of records. When archiving, there is no need to add "Main Modified Files" and "Version Information" descriptions; archiving must include the mapped date, sequence number, and title.
4. **English Only:** All writings, logs, and workflow updates must strictly use English to facilitate agent read/write operations.
5. **Writing Principle:** Adhere to the principle of being concise and comprehensive when writing.

## 1.0 proxy Repository Overall Planning Tasks

- [x] **u-1-1 Architecture Refactoring: Self-built proxy repository (2026-02-10)**
  - [x] Create a new GitHub repository `proxy`, with content completely copied from the current `sing-box` repository.
  - [x] Repository merge and structure reorganization.
- [x] **u-1-2 Repository Convergence: Migrate sing-box configs and deprecate legacy repo locally (2026-02-16)**
  - [x] Migration of client and server configurations.
  - [x] Add version records.
- [x] **u-1-3 Checklist/Workflow Deep Decoupling (Client Configs vs Server Install Scripts) (2026-02-25)**: Further structurally decouple `checklist` and `workflow`, splitting the setup process and tasks according to "client configuration files" and "server installation scripts".
  - [x] Client configuration file workflow and tasks: Split into three independent main threads for `sing-box`, `mihomo`, and `surge mac`.
  - [x] Server workflow and tasks: Focus exclusively on the `proxy` installation script (install, configure, ops, verify) main thread.
  - [x] Document boundary requirements: `checklist` tracks task status, `workflow` logs execution records, preventing the same task from being written in both documents.

## 2.0 shell-proxy

### v0.0.0

- [x] **u-2-1: Script enhancement, Snell v5 integration (2026-02-10)**: Integrated Snell v5, implemented dynamic version management, and optimized configuration options.
- [x] **u-2-2: Script interactive experience optimization (UX)**: Optimized management and installation menus to loop and auto-guide instead of directly exiting.
- [x] **u-2-3: ShadowTLS and security enhancements**: Independently integrated ShadowTLS, optimized v3 installation parameters, and added port conflict detection.
- [x] **u-2-4: Transparent uninstallation logic**: Listed all paths during uninstallation and provided real-time deletion feedback.
- [x] **u-2-5: Sing-box interactive config upgrade & randomization (2026-02-11)**: Added interactive modifications, randomized UUID/ShadowTLS/Reality elements, and Reality key pairs.
- [x] **u-2-6: Dual-stack support and fake domain optimization**: Researched IPv4/IPv6 dual stack capabilities, streamlined inbound configurations, and improved Shadow-TLS domains.
- [x] **u-2-7: Subscription and protocol links**: Implemented dual-endpoint JSON and Surge format subscriptions.
- [x] **u-2-8: Architecture structural refactoring (First principles)**: Decoupled code modules, introduced systemd templates, enforced strict error handling, and fixed public installer.
- [x] **u-2-9: Menu hierarchy and routing UX (2026-02-12)**: Adjusted main menus based on opensource alternatives to prioritize setup logic.
- [x] **u-2-10: Server path convergence (2026-02-16)**: Centralized all outputs to `/etc/shell-proxy/` and fixed Windows dual-stack details.
- [x] **u-2-11: Subscription availability & UX fixes**: Handled Reality/TUIC URI generation failures, added port override dialogues, and improved menu UI colors.
- [x] **u-2-12: Operational Logs menu rebuilding (2026-02-17)**: Categorized live logs into internal scripts, daemon watchdogs, and protocol states.
- [x] **u-2-13: Main menu and dynamic routing integration**: Streamlined settings, deployed dual-stack adaptable routing, and matched proxy exit IPs with DNS resolutions.
- [x] **u-2-14: Chain-proxy enhancements and config readability**: Addressed chain proxy input types, removed dead ACME routing strings, and used formatting for easy config reading.
- [x] **u-2-15: ShadowTLS multi-binding and interface fixes**: Supported ShadowTLS binding on single-protocol levels, enhanced interface logging.
- [x] **u-2-16: Anytls protocol coverage & naming bounds**: Addressed the `anytls` protocol workflow integrations securely, checking Apple guidelines natively.
- [x] **u-2-17: Atomic DNS and route linkage (2026-02-18)**: Synced routing/DNS tables simultaneously preventing silent removal of critical baseline routes.
- [x] **u-2-18: Geosite/Geoip catalogs and server integrations**: Mapped Netflix/TikTok databases natively providing accurate content filtering over 1-9 UI interactions.
- [x] **u-2-19: Trace logs removal**: Trimmed broken interactive realtime logging systems.
- [x] **u-2-20: Trojan fixes**: Bridged ALPN and configuration generation anomalies over HTTPS links.
- [x] **u-2-21: SS 2022 unified cryptography (2026-02-18)**: Pushed 2022-blake3 default configurations with matching Surge template outputs.
- [x] **u-2-22: DMIT server deployments & firewall logic (2026-02-19)**: Rolled out server installation capabilities coupled strictly with native firewall port policies.
- [x] **u-2-23: DNS strategies & subscription exports (2026-02-19)**: Enforced `prefer_ipv4` on generic dual-stack targets, unified public DNS tags, and streamlined subscription formats.
- [x] **u-2-24: Sing-box v1.14 compatibility**: Adapted core network generations securely to `domain_resolver.strategy` resolving flows.
- [x] **u-2-25: Network optimization module**: Added the main menu "Network Optimization" providing end-to-end OS BBR deployments, regression tested continuously on DMIT.
- [x] **u-2-26: Reminder sync optimizations (2026-02-21)**: Handled subscription format validations, tuned Surge parameter specs, audited ShadowTLS UI variables, and filtered proxy domains accurately.
- [x] **u-2-27: AI telemetry & geosite filtering**: Paired unified `geoip-ai` mapping directly alongside foundational AI rulesets natively.
- [x] **u-2-28: Subscription reload guard**: Prevented UI prompt cyclic auto-restarts by enforcing configuration timestamp comparisons and deduplicated general Surge node footprints.
- [x] **u-2-29: Shadow-TLS V3 patches**: Standardized local proxy linkages strictly adhering to `shadow-tls-version=3` averting generic TLS handshake degradation against Surge clients.
- [x] **u-2-30: Surge link format convergence**: Conformed remote UI template links perfectly overlapping the mapped local iOS `dmit.conf` standard metrics.
- [x] **u-2-31: Terminal UI enhancements**: Compressed visual occupied port tracking data intelligently and pushed complex parameter design guides into local documentation nodes.
- [x] **u-2-32: IPv4 public address correction**: Discarded generalized IPv4 polling metrics mapping Surge nodes exclusively relying on global public IPs.
- [x] **u-2-33: Complete uninstallation sequences**: Embedded comprehensive `Uninstall All Protocols` functionality providing fully-clean teardown capabilities spanning overlapping configurations securely.
- [x] **u-2-34: Caddy version mechanisms (2026-02-28)**: Resolved legacy hardcoded tags enforcing systematic dynamic API fetches consistent with master update pipelines.
- [x] **u-2-35: Account-level routing frameworks (2026-02-28)**: Structured granular routing profiles mapping standalone upstreams and unique rule definitions selectively based on individual user contexts.
- [x] **u-2-36: Shadow-TLS subscription formats (2026-03-01)**: Merged linked subscriptions preventing raw protocol exports directly underneath assigned Shadow-TLS entry bindings.
- [x] **u-2-37: Link target diagnostics (2026-03-01)**: Remedied internal `::ffff:...` map collisions alongside high latency UI freezes by offloading complex rendering cycles strictly into cached contexts.
- [x] **u-2-38: User structural overhaul (2026-03-01)**: Inverted general management trees focusing operations directly via explicit User identifiers rather than indexing shared protocols.
- [x] **u-2-39: Locked protocol manipulation scopes (2026-03-01)**: Mandated all component installations/uninstallations specifically within selected Username confines matching grouped user subscriptions flawlessly.
- [x] **u-2-40: De-coupled initialization routines (2026-03-01)**: Dropped automatic protocol bindings across basic Username setups, permitting hollow accounts lacking prior rule parameters conditionally.
- [x] **u-2-41: Interactive flow standardization (2026-03-01)**: Directed overarching UI workflows linearly defining sequential selections specifically starting as: Protocol Identification -> Target Username Assignment.
- [x] **u-2-42: Legacy UI speedups (2026-03-01)**: Rebuilt backend execution polling chains migrating massive repetitive file scans effectively into streamlined in-memory multi-tiered caching modules reducing layout latency.
- [x] **u-2-43: Management hierarchy simplifications (2026-03-02)**: Abstracted explicit user routing behaviors firmly out of standard general management menus pushing them cleanly into separate routing portals conditionally mapped against target parameters.
- [x] **u-2-44: Network firewall integrations (2026-03-02)**: Expanded the internal BBR optimizations layout appending comprehensive automated nftables/iptables synchronizations tightly monitoring standard protocol ports securely.
- [x] **u-2-45 proxy script v1.0.0 refactoring and optimization (2026-03-03)**: Identified 6 major structural risks in the monolithic `config_ops.sh`; extracted 66 focused modules by domain (common, routing, user, protocol, subscription, service, network, etc.); introduced base preloading + menu lazy-loading; converged managed-file manifests into `env.sh`; cleaned up all confirmed dead functions and aliases.
- [x] **u-2-46 server/install module grouping list convergence (2026-03-03)**: Unified module lists into a single source of truth in `env.sh`; promoted grouped `modules/core|protocol|routing|subscription|user/?` directories from mirrors to true implementations; demoted flat `modules/*.sh` to compatibility shells; hardened self-update bootstrap; fixed installation and menu regressions on `gcp-hk`.
- [x] **u-2-47 GCP-HK installation and IPv6 repair, TLS domain-check parallelization (2026-03-04)**: Completed fresh install on `gcp-hk`; fixed IPv6 detection false positives; parallelized TLS domain-availability checks to cut certificate wait time.
- [x] **u-2-48 Certificate wait animation and script-update parallelization (2026-03-04)**: Added live spinner during certificate issuance; parallelized script-update download and verification steps.
- [x] **u-2-49 Script update chain and Surge display corrections (2026-03-04)**: Fixed update-chain source-ref tracking; corrected Surge link display format mismatches after update.
- [x] **u-2-50 Main menu network stack display (2026-03-04)**: Added IPv4/IPv6 dual-stack indicator to the main menu status block.
- [x] **u-2-51 User management removed "User Control" (2026-03-04)**: Removed the deprecated "User Control" sub-menu entry; simplified user management page.
- [x] **u-2-52 server/install subscription cache, DNS sync, and management entry convergence (2026-03-04)**: Merged subscription cache paths and DNS-sync triggers; tightened management entry module boundaries.
- [x] **u-2-53 bugfix: tuic domain override update and certificate entry default domain repair (2026-03-05)**: Fixed TUIC domain-override not persisting across restarts; corrected certificate entry defaulting to wrong domain.
- [x] **u-2-54 perf: subscription bucketized per-user + routing rules sessionized submissions (2026-03-05)**: Partitioned subscription render cache per user; deferred routing-rule writes into session batches to eliminate redundant reloads.
- [x] **u-2-55 perf: routing submission chain second-round hotspot convergence (2026-03-05)**: Eliminated remaining O(n) hotspots in the routing submission path; further compressed per-write overhead.
- [x] **u-2-56 stability fixes and resource health archiving (2026-03-05)**: Applied a batch of stability patches; archived resource-health baseline metrics for reference.
- [x] **u-2-57 bugfix: DNS strategy and chained-node IP-family linkage fix (2026-03-05)**: Corrected DNS strategy not propagating correctly to chain-proxy node IP-family selection.
- [x] **u-2-58 perf: protocol menu snapshot-only stale rebuilds + main menu dashboard static caches (2026-03-05)**: Protocol menu now rebuilds its snapshot only on stale fingerprints; main menu dashboard values are statically cached between renders.
- [x] **u-2-59 perf: startup chain deduplication and auto-config process-level short-circuiting (2026-03-05)**: Eliminated duplicate `source` calls in the startup chain; `auto-config` exits early when configuration is already up to date.
- [x] **u-2-60 perf: startup first-round stale background re-synchronization (2026-03-05)**: Moved stale-state re-sync off the critical startup path into a background job.
- [x] **u-2-61 perf: user template routing sync persistent short-circuits and compilation caches (2026-03-05)**: Added persistent fingerprint short-circuits and on-disk compilation caches to skip redundant template-route syncs.
- [x] **u-2-62 perf: routing sync warm path further compressed (2026-03-05)**: Reduced warm-path overhead for routing synchronization.
- [x] **u-2-63 perf: routing sync warm path fixed overhead further converged (2026-03-05)**: Eliminated remaining fixed costs (file reads, `jq` invocations) from the routing sync warm path.
- [x] **u-2-64 perf: startup fingerprint hot-path caching + stale verification offloaded to background (2026-03-05)**: Cached fingerprint comparisons in memory; moved stale-verification work to a background process.
- [x] **u-2-65 perf: DNS sync hot-path deduplication and parent-shell cache reuse (2026-03-06)**: Deduplicated redundant DNS sync calls within a single shell session; reused parent-shell cache across sub-shell invocations.
- [x] **u-2-66 perf: user template routing sync cross-process cache offloading (2026-03-06)**: Persisted routing-sync intermediate results to disk so child processes can reuse them without recomputing.
- [x] **u-2-67 perf: user template routing sync input-fingerprint short-circuit (2026-03-06)**: Added an input-side fingerprint check so unchanged template inputs skip all sync work immediately.
- [x] **u-2-68 perf: routing status view-cache and config display single-jq rendering (2026-03-06)**: Consolidated routing status and config display into a single `jq` call per render pass.
- [x] **u-2-69 perf: menu status fingerprint lightening and background warmup after startup (2026-03-06)**: Simplified the status fingerprint to cheaper fields; kicked off menu warmup in the background after startup completes.
- [x] **u-2-70 perf: routing status cache pre-pushed to write time, pre-build scope narrowed (2026-03-06)**: Pushed routing status cache generation forward to write time; narrowed the pre-build scope to avoid unnecessary work.
- [x] **u-2-71 perf: main startup chain slimmed, menu warmup disabled by default, config-view header merged (2026-03-06)**: Removed non-essential loads from the startup critical path; disabled eager menu warmup by default; merged config-view header rendering.
- [x] **u-2-72 perf: subscription menu dependency autonomy fix and target-detection cross-process caches (2026-03-06)**: Fixed subscription menu accidentally depending on routing state at load time; added cross-process caches for target-detection results.
- [x] **u-2-73 perf: subscription rendering context cross-process caches and dashboard cold-rebuild frequency lowering (2026-03-06)**: Persisted subscription render context across processes; reduced cold-rebuild frequency for the main menu dashboard.
- [x] **u-2-74 perf: main menu full-page static cache, base unloading, and routing-source pollution fixes (2026-03-06)**: Cached the full main menu page statically; unloaded base modules after startup; fixed routing-source variable pollution.
- [x] **u-2-75 perf: subscription freshness-check deduplication and routing top-level lazy loading (2026-03-06)**: Deduplicated redundant freshness checks in the subscription path; made top-level routing module loading lazy.
- [x] **u-2-76 perf: share light-entry + host cache + routing sub-function tiered lazy loading (2026-03-06)**: Added a fast empty-install path for share; cached host detection results; tiered lazy loading for routing sub-functions.
- [x] **u-2-77 perf: rule menu first screen lazily fetches state and reuses user-state cache (2026-03-06)**: Routing rule list page now lazily fetches routing state and reuses the already-loaded user state.
- [x] **u-2-78 perf: routing-status freshness-check chain cross-process cache (2026-03-06)**: Added a cross-process fingerprint cache for the routing-status freshness check chain.
- [x] **u-2-79 perf: routing session-state loading chain slimmed (2026-03-06)**: Removed redundant loads from the routing session-state initialization path.
- [x] **u-2-80 perf: test-routing-effect switched to cache-prioritization + background refresh (2026-03-06)**: "Test Routing Effect" now shows cached results immediately and refreshes in the background.
- [x] **u-2-81 perf: compress write path for user routing-rule submissions (2026-03-06)**: Merged multiple per-rule writes into a single batched write; eliminated repeated `jq` re-parsing per submission.
- [x] **u-2-82 perf: meta-level fast short-circuits for user template routing sync (2026-03-06)**: Skips full routing sync when the user has no template or the template rules are empty.
- [x] **u-2-83 perf: routing submission chain skips irrelevant inbound username sanitize (2026-03-06)**: Bypassed the costly username-sanitize pass for inbounds unrelated to the current submission.
- [x] **u-2-84 fix: menu regression fixes after reinstallation (2026-03-06)**: Fixed several menu interaction regressions that appeared after a clean reinstall from the public entry script.
- [x] **u-2-85 UX/perf: install protocol changed to delayed restart within menu session (2026-03-08, merged into u-2-88)**: Buffered `sing-box` restarts until exiting the install-protocol session instead of restarting after each individual protocol.
- [x] **u-2-86 UX: stay in install-protocol menu after installing a single protocol (2026-03-08, merged into u-2-88)**: After installing a protocol the menu loops back to the protocol selector instead of jumping to the main menu.
- [x] **u-2-87 perf: squeeze user-management entry first-screen stutters (2026-03-08, merged into u-2-88)**: Reduced first-screen stutter in user management by deferring membership cache loads.
- [x] **u-2-88 refactor: refactor menu and loading architecture from first principles (2026-03-08)**: Major refactor: introduced per-group bundle pre-build system in `env.sh`; deferred `sing-box` restart to session exit; unified menu headers/spinners; parallelized subscription target probing; narrowed compatibility boundary to `v1.0.0+`; deleted 14 shim files and orphan helpers; converged public/private bootstrap entry; 13-phase execution with full `gcp-oregon` regression verification.
- [x] **u-2-89 refactor: remove public install entry script, retaining only private repo bootstrap (2026-03-08)**: Deleted `public/install-proxy.sh`; unified installation entry to `server/install/bootstrap.sh` in the private repo; updated docs.
- [x] **u-2-90 refactor backlog: existing architecture approaching upper limits ? refactor menu & architecture (2026-03-08)**: Defined 5 architectural targets (silky UX, simpler code, merged files, concise interface, phased design-first refactor); executed 13 phases covering bundle scope, TTY detection, subscription convergence, orphan cleanup, compat-boundary narrowing, Snell stale-binding removal, reinstallation regression, and bootstrap convergence.
- [x] **u-2-91 refactor: high-ceiling architecture as baseline -- advance ultimate performance and silky menu interactions (2026-03-09)**: Took the new architecture from u-2-88 as baseline; executed 5 phases: bleeding-control for install/update chains, basic-layer split (`release_ops`, `bootstrap_ops`, `runtime_shadowtls_ops`), hot-path load reduction (read-only menu no longer invalidates main-menu cache, routing/share short TTL caches), subscription-chain modularization (`share_meta_ops`, merged dual-probe, display-name cache fast path, eliminated cross-process disk render context); `gcp-oregon` metrics: `proxy status` 0.851s -> 0.240s, main-menu blackbox 0.561s -> 0.236~0.557s, share cold render 3.293s. Phase 5: async config-apply, bundle-build heredoc extracted to `bundle_build_ops.sh`, module total realigned to 38.
- [x] **u-2-92 cleanup: dead/legacy/redundant code removal and regression re-verification (2026-03-10)**: Low-risk first pass deleted 8 confirmed zero-call functions across `config_ops`, `protocol_port_ops`, `routing_ops`, `routing_res_socks_ops`, `subscription_ops`; minimal machine regression on `gcp-oregon` (subscription management, test routing, routing management, install protocol) passed; continued protocol-add-chain convergence: per-user `compiled-rules` cache, atomic `user-management.json` write, gating on route-state change; warm metrics: `proxy status` 0.169s, main-menu 0.257s, subscription 1.757s, routing 0.616s.
- [x] **u-2-93 regression: real menu interaction verification (2026-03-10)**: Measured 6-protocol real-menu install for user `u193x1` -- before fix: `proto_5(anytls)` 39s, `proto_6(snell)` 34s, `exit_install_apply` 30s; after fix: all <=7s, `exit_install_apply` 11.755s. Remaining targets (10 routing rules, 5-user full run, Workflow archiving) are pending [ ].
- [x] **u-2-94 gcp-oregon remote script update and basic function re-verification (2026-03-10)**
  - [x] Target 1: Execute a round of `self_update.sh repo` on `gcp-oregon` through a real TTY, confirm that the update chain can complete normally, and record the script source version change.
  - [x] First did a live check of the remote status quo: at that time, the target machine was an "empty environment", `/etc/shell-proxy`, `/usr/bin/proxy`, and `self_update.sh` did not exist; therefore, this round first used the local `server/install` copy to restore the installation, and then continued to execute update verification.
  - [x] Executed local script copy installation on `gcp-oregon` via a real TTY; after installation completed, wrote the remote `.pat`, and then executed `sudo bash /etc/shell-proxy/self_update.sh repo`.
  - [x] The updater normally completed a round of comparison and verification: the remote end showed that all `48` managed files matched, and `/etc/shell-proxy/.script_source_ref` was written to disk as the current repository commit `repo:97303b13...`.
  - [x] Target 2: After the update completes, execute a round of basic function re-verification, covering at least `proxy status`, the main menu's first screen, the `11) Script Update` entry, and one read-only menu chain, confirming no missing modules, bundle fallback anomalies, or obvious interaction regressions occurred.
  - [x] `proxy status` verified: `sing-box` and `proxy-watchdog` are running normally; when `shadow-tls-v3` is unconfigured, it prompts to skip as expected.
  - [x] Main menu first screen verified: `printf "0\n" | sudo proxy` normally displays version, system, network stack, status, menu items, and return entry, with no missing modules or bundle fallback errors.
  - [x] `11) Script Update -> 2. repo` menu chain verified: can normally enter the update submenu and return "Already up to date."
  - [x] Read-only menu chain verified: `7) View Config` can normally enter and return to the main menu, without abnormal blockage.
  - [x] Target 3: Archive the remote update results and re-verification conclusions into the Checklist / Workflow.

- [x] **u-2-95 Protocol addition and subscription display regression in multi-user scenarios (2026-03-10)**
  - [x] Issue 1: Membership cache skip during active install session (`user_membership_ops.sh`); eliminated repeated O(inbounds) jq scans per menu loop.
  - [x] Issue 2: Removed outer spinner wrapper from flush phase (`protocol_install_singbox_ops.sh`); sub-step progress now visible to users.
  - [x] Issue 3: Subscription view freshness check uses live `calc_subscription_render_fingerprint` instead of stale cached override (`share_ops.sh`); all users' links now display correctly.
  - [x] Target: All three multi-user regressions pinpointed and fixed; execution records archived in workflow.

- [x] **u-2-96 perf backlog: protocol install latency, routing-management stalls, and subscription-refresh decoupling (2026-03-11)**
  - [x] Issue 1: Route sync cache key narrowed to inbounds-only fingerprint (`user_route_ops.sh`, schema `v3` → `v4`); route-only conf_file writes no longer trigger recompilation.
  - [x] Issue 2: Routing menu entry pre-warms user list in background (`routing_menu_support_ops.sh`); post-commit status refresh switched to async (`routing_core_ops.sh`).
  - [x] Issue 3: Subscription fingerprint decoupled from routing state — uses inbounds-only conf_fp and template-excluded user_meta_fp (`subscription_ops.sh`, schema `v2` → `v3`).
  - [x] Target: All three hotspots addressed; execution records archived in workflow.

- [x] **u-2-97 perf: user management menu loading delay and rename double-restart elimination (2026-03-11)**
  - [x] Issue 1: User menu pre-warms membership cache in background (`user_ops.sh`); sub-option selection now hits warm caches instead of blocking on O(inbounds) jq scan.
  - [x] Issue 2: `finalize_user_group_batch` reordered to run route sync before explicit restart (`user_batch_ops.sh`); fingerprint comparison detects if sync already restarted sing-box, skipping redundant 2-8s restart.
  - [x] Target: Both user management hotspots addressed; execution records archived in workflow.

- [x] **u-2-98 bugfix: DNS auth_user not synced with route auth_user after username changes (2026-03-11)**
  - [x] Root cause: `routing_managed_rules_dns_shape_fingerprint` excluded `auth_user` from its normalized shape, so username renames did not change the DNS fingerprint and DNS re-sync was skipped.
  - [x] Fix: Added `auth_user` to the DNS shape fingerprint normalization and sort key (`user_route_ops.sh`); username changes now trigger DNS rule re-sync.

- [x] **u-2-99 perf: background-job accumulation causing transient CPU spikes and menu lag (2026-03-11)**
  - [x] Root cause: Two unlocked per-loop-iteration background warmup jobs (`proxy_user_group_sync_from_memberships` in user menu, `routing_prepare_target_user_selection_context` in routing menu) spawned new subshells on every loop without concurrency guards; rapid menu navigation accumulated parallel instances.
  - [x] Fix: Wrapped both warmup jobs in mkdir-based lock subshells (`user_ops.sh`, `routing_menu_support_ops.sh`); concurrent spawns now exit immediately if a previous instance is still running.
  - [x] Audit: All other background job sites (routing status refresh, protocol cache rebuild, test effect refresh, async config apply) already use flock or mkdir locks. No additional accumulation vectors found.

- [x] **u-2-100 release: publish GitHub release v1.1.0 from the latest tagged baseline (2026-03-11)**
  - [x] Select release baseline commit `c462c3e66fd7ce0d45361cb34f4b1f0cc921c5e9` for `v1.1.0`.
  - [x] Create and push annotated tag `v1.1.0`, then publish the matching GitHub release page.
  - [x] Sync `README.md` and `AGENTS.md` to mark `v1.1.0` as the current formal release baseline.

- [x] **u-2-101 regression: gcp-oregon clean install and interactive menu verification with issue archiving (2026-03-14)**
  - [x] Execute a clean uninstall/reinstall verification cycle on `gcp-oregon`, covering both the documented private-bootstrap path and a local-copy fallback path.
  - [x] Traverse the main interactive menu chains: add user, install protocol, configure routing, view subscriptions, view configuration, uninstall protocol, plus read-only checks for protocol/log/core/network menus.
  - [x] Archive the blocking install/auth issues and menu regressions discovered during the run into Checklist / Workflow.

- [x] **u-2-102 fix: repair private install/update paths, correct bootstrap entry, and re-verify remote flows (2026-03-14)**
  - [x] Push the private install/update path fixes to `shell-proxy/main`, covering archive extraction under `app/`, `self_update` source resolution, and deleted-user route cleanup.
  - [x] Re-verify PAT access on both local and `gcp-oregon`, then execute a real remote bootstrap/install and a real `11) Script Update -> 2. repo` menu chain.
  - [x] Re-check the `ss` blank-password install path and re-validate orphan `auth_user` rule cleanup, archiving the corrected conclusions into Workflow.

- [x] **u-2-103 bugfix: ghost "user" group appearing in user list with no protocols (2026-03-14)**
  - [x] Root cause 1: `proxy_user_group_add` accepted empty/whitespace input; `normalize_proxy_user_name("")` falls back to `"user"`, silently creating an orphaned group.
  - [x] Root cause 2: `modify_singbox_inbounds_logic` and `modify_snell_config` called `proxy_user_group_add` eagerly after user selection but before protocol install completed; if cancelled mid-flow the group persisted without any protocol binding.
  - [x] Fix: added pre-normalization empty guard to `proxy_user_group_add`; removed the two eager calls from the install path; removed the orphaned `"user"` entry from `gcp-oregon` `user-management.json`; rebuilt bundles.

- [x] **u-2-104 fix: routing menu freeze caused by subprocess spinner discarding variable state (2026-03-14)**
  - [x] Root cause: `proxy_run_with_spinner_compact` runs work in a background subprocess; routing prep functions communicate results via shell variables which are lost when the subprocess exits, causing the foreground fallback to re-execute all heavy jq/cache work without spinner feedback.
  - [x] Fix: added `proxy_run_with_spinner_fg` that runs the spinner animation in a background process and the work in the foreground, preserving variable assignments; switched both routing menu prep spinners to use it.
  - [x] Verified on `gcp-oregon`: routing menu "配置分流" loads without freeze, spinner displays correctly, user list populates immediately after spinner completes.

- [x] **u-2-105 ux: remove redundant prompts during option configuration (2026-03-14)**
  - [x] Shortened `prompt_select_index` hint, user selection prompts, install/uninstall flow messages, and inbound reuse messages across 10 module files.
  - [x] Removed verbose subtitles from 10 menu headers; removed "说明" header and numbering from subscription notes; collapsed two-line pending-changes warning to one line.
  - [x] Standardized all "按回车返回......" → "回车返回" across 16 files including `pause()`, `bootstrap_ops.sh`, and all routing/network/log modules.
  - [x] Fixed display bug in `add_user_group`: stray "按回车返回......" rendered before username input prompt.
  - [x] Removed duplicate reuse success message, deleted "待生效" banner, and changed flush message to "正在应用新配置文件(...)".
  - [x] Updated `.claude/rules/archive.md` with mandatory real-world menu verification constraint.
  - [x] Re-validated with `bash -n` on all 16 modified files and real-world menu verification on `gcp-oregon`.

- [x] **u-2-106 ux: keep inbound-reuse success message on a single line (2026-03-14)**
  - [x] Replace the custom formatted reuse-success output in `protocol_install_singbox_ops.sh` with a plain single-line `green` message.
  - [x] Preserve the existing message content (`已为用户名 ... 复用 ... 入站: 端口 ...`) while preventing wrapped multi-line rendering caused by the previous implementation.
  - [x] Re-validated with `bash -n` and `git diff --check`.

- [x] **u-2-107 fix: self_update repo changed-file download must honor app/ source prefix (2026-03-14)**
  - [x] Fix the parallel changed-file download loop in `app/self_update.sh` so managed files are fetched from the real repo source path under `app/` instead of the repo root.
  - [x] Add failed-file reporting for the changed-file download stage to make future remote update failures diagnosable.
  - [x] Re-verify on the remote machine by forcing a stale managed file and executing the real `11) Script Update -> 2. repo` menu chain successfully.

- [x] **u-2-108 refactor: prepare repository for public release (2026-03-15)**
  - [x] Remove PAT authentication from bootstrap, install, self-update, and all GitHub API call paths; public repo no longer requires a token.
  - [x] Rename `PRIVATE_REPO` → `REPO_NAME` across `env.sh`, `self_update.sh`, `bootstrap_ops.sh`.
  - [x] Remove `TOKEN_FILE`, `get_auth_header()`, `save_token()`, `download_private_repo_archive()`, `extract_private_install_tree()` from install/env.
  - [x] Simplify `install_control_script()` to always use local copy from bootstrap layer.
  - [x] Update `AGENTS.md` to reflect public repository status; remove `with pat` from verification tiers.
  - [x] Replace placeholder email `admin@gmail.com` → `user@example.com` in `protocol_tls_ops.sh`.
  - [x] Simplify README installation command to single `curl | bash`.
  - [x] Move `docs/`, `.claude/`, `AGENTS.md` to local-only via `.gitignore` and `git rm --cached`.
  - [x] Squash all 27 commits into a single initial commit; delete tag `v0.0.0` and its GitHub release.
  - [x] Re-validated with `bash -n` on all modified `.sh` files.

- [x] **u-2-109 feat: add shell-proxy-verify skill and restructure verification tiers (2026-03-15)**
  - [x] Created `.claude/skills/shell-proxy-verify/SKILL.md` with 12 verification modules (VM-01–VM-12) aligned to main menu options, invocation interface, pre-flight steps, and tier mapping.
  - [x] Created `references/file-module-map.md` mapping all 37 module files + 5 entry scripts + 5 systemd templates to VM modules with bundle group cross-reference.
  - [x] Created `references/dependency-graph.md` with weighted dependency declarations, direct dependents lookup, and topological sort order.
  - [x] Updated `.claude/rules/verification.md` Tier 2/3 to invoke the skill instead of ad-hoc procedures.
  - [x] Updated `AGENTS.md` directory structure and verification table to reference skill invocation.
  - [x] Tier 3 regression verified on `gcp-oregon`: all 11 modules passed (VM-12 skipped as destructive).

- [x] **u-2-110 ux: unify main menu separator lines to double-line light red style (2026-03-15)**
  - [x] Replaced all 5 separator lines across `management.sh` and `runtime_status_ops.sh` with consistent `═════` style in light red (`\033[1;31m`).
  - [x] Re-validated with `bash -n` on both files; deployed and rebuilt bundles on `gcp-oregon`.

- [x] **u-2-111 bugfix+ux: ghost user guard, install protocol UX improvements (2026-03-15)**
  - [x] Added pre-normalization empty guards to `proxy_user_meta_apply_protocol_membership` and `protocol_install_session_queue_membership` to prevent `normalize_proxy_user_name("")` from creating ghost "user" entries.
  - [x] Replaced "添加成功，配置已写入。" + deferred restart warning with single-line "添加成功，已复用配置。".
  - [x] Wrapped `protocol_install_session_flush_now` with `proxy_run_with_spinner_fg` for spinner animation during config apply.
  - [x] Simplified install protocol user selection prompt from "选择用户名 (protocol)" to "选择用户名" in both singbox and snell paths.
  - [x] Re-validated with `bash -n`; deployed and rebuilt bundles on `gcp-oregon`.

- [x] **u-2-112 refactor: code review cleanup and structural deduplication (2026-03-15)**
  - [x] Fixed `proxy_run_with_spinner_fg` swallowing stdout/stderr — removed `>/dev/null 2>&1` redirect so sub-step messages are visible alongside spinner.
  - [x] Hoisted nested `protocol_install_session_flush_inner` to module scope as `_protocol_install_session_flush_inner` to prevent global namespace leak.
  - [x] Removed 3 verbose surge note lines from subscription share view in `share_ops.sh`.
  - [x] Extracted `_subscription_share_render_body` helper using namerefs to deduplicate ~90% identical rendering logic between `render_to_file` and `render_payload_to_file`.
  - [x] Merged duplicate `case` blocks for `selected_proto` / `selected_proto_label` into single `case` with derived label.
  - [x] Added `proxy_is_blank_string` utility to `common_ops.sh`; replaced 4 inline whitespace-guard patterns across 3 files.
  - [x] Re-validated with `bash -n` on all 5 modified files; deployed and rebuilt bundles on `gcp-oregon`.

- [x] **u-2-113 ux: unify all sub-menu separators and headers to 68-char standardized API (2026-03-15)**
  - [x] Replaced all 14 raw `echo "==="` sub-menu headers across 8 files with `proxy_menu_header` (68-char default width).
  - [x] Replaced all remaining raw `echo "---"` dividers across `app/modules/` with `proxy_menu_divider` (thin `─`) or `proxy_menu_rule "═"` (thick, for menu footers).
  - [x] Fixed all `proxy_menu_back_hint 45` calls to use default width 68.
  - [x] Replaced 2 `yellow "=== ..."` config detail headers in `log_ops.sh` with `proxy_menu_header`.
  - [x] Updated default widths in `common_ops.sh`: `proxy_menu_rule`, `proxy_menu_header`, `proxy_menu_divider` all 45→68.
  - [x] Redesigned main menu layout: wider 68-char `═` separators, centered title, protocol display `/` separator, `(N)` right-aligned menu items.
  - [x] Re-validated with `bash -n` on all 15 modified files.

- [x] **u-2-114 ux: streamline menus — remove pause/hints, reorder protocols, compact prompts (2026-03-15)**
  - [x] Deleted `pause()` function and all 60+ call sites across 16 files; removed `pause_unless_cancelled`.
  - [x] Deleted `proxy_menu_back_hint` (zero callers); inlined `proxy_prompt_print` into `read_prompt`.
  - [x] Unified `prompt_select_index`: removed "回车返回" hint, changed prompt to "选择序号(回车取消):".
  - [x] Reordered install protocol menu: ss→vless→tuic→trojan→anytls→snell-v5, 2-space indent.
  - [x] Removed release/repo selection from script update — defaults to repo mode.
  - [x] Simplified chain proxy input: single-line Chinese format hint, removed yellow tip.
  - [x] Extended share divider from 60→68 chars; double-space user name separator in uninstall table.
  - [x] Removed 13 extra blank-line `echo` and 5 `\n` prefixes from protocol install headers.
  - [x] Re-validated with `bash -n` on all 18 modified files; deployed and rebuilt on `gcp-oregon`.

- [x] **u-2-115 refactor+ux: DRY separator color, universal 2-space menu indent (2026-03-15)**
  - [x] Added optional `color` parameter to `proxy_menu_rule()`; replaced 6 hardcoded separator lines in `management.sh` and `runtime_status_ops.sh` with `proxy_menu_rule "═" 68 "1;37"`.
  - [x] Changed main menu divider color from red to white (`1;31m` → `1;37m`).
  - [x] Added 2-space indent to all remaining sub-menus: 12+ static menus across 6 files, 8 dynamic `printf`/`echo` lines across 6 files.
  - [x] Changed service menu `)` to `.` numbering style.
  - [x] Re-validated with `bash -n` on all 16 modified files; deployed and rebuilt on `gcp-oregon`.

- [x] **u-2-116 refactor: remove "all traffic" and "custom" menu options, clean dead code (2026-03-15)**
  - [x] Removed `c. 自定义域名/IP/CIDR` and `f. 所有流量` from routing rule preset menu and case mappings.
  - [x] Removed `routing_print_route_rule_all()`, dead "all" jq sort patterns (3 locations), dead custom input/state blocks.
  - [x] Removed dead function `routing_user_requires_route_sync_on_protocol_add()`.
  - [x] Kept `custom` type handling in state processing and label rendering for backward compatibility.
  - [x] Re-validated with `bash -n` on all 4 modified files.

- [x] **u-2-117 bugfix: fix ghost "user" group and unify protocol install success message (2026-03-15)**
  - [x] Removed `normalize_proxy_user_name` fallback to `DEFAULT_PROXY_USER_NAME`/"user" — now returns empty for invalid input.
  - [x] Updated `proxy_user_share_suffix_cached` and `proxy_user_link_name_cached` guards from `!= "user"` to `[[ -n ]]`.
  - [x] Unified protocol install success message to `协议安装成功` for both first-install and reuse paths.
  - [x] Re-validated with `bash -n`; deployed and verified on `gcp-oregon`.
- [x] **u-2-118 enhancement: streamline protocol install UX and fix ghost user v2 (2026-03-15)**
  - [x] Fixed ghost "user" root cause v2: removed `DEFAULT_PROXY_USER_NAME` fallback in `proxy_user_link_name_cached`.
  - [x] Simplified domain/certificate prompts: removed verbose hints, merged cert warning into single prompt.
  - [x] Simplified snell install: removed IPv6 hint, "配置已写入"/"统一重启" messages, "未配置" hint; block duplicate snell install with immediate return.
  - [x] Simplified shadow-tls setup: removed backend port/recommended port/default port hints, instance detail line; kept occupied ports display only when non-empty.
  - [x] Suppressed restart messages during session flush spinner.
  - [x] Removed "--- 添加 xxx ---" header lines from all protocol installs.
  - [x] Removed protocol count from user list and uninstall list displays.
  - [x] Simplified reuse messages; added numbered SS encryption method selector with stderr output.
  - [x] Re-validated with `bash -n`; deployed and verified on `gcp-oregon`.

- [x] **u-2-119 perf: reduce jq fork overhead for e2-micro performance (2026-03-15)**
  - [x] Phase 1: Removed 32 redundant `jq .` post-mutation validation forks across 11 files — jq output is always valid JSON if exit code was 0.
  - [x] Phase 2: Merged check-then-mutate pairs — `proxy_user_group_add` grep fast-path, `routing_ensure_state_db` bash builtin read, `proxy_user_meta_db_ensure` guard simplified.
  - [x] Phase 3: Replaced static `jq -nc` with heredocs/printf — `auto_rule_set_catalog_json` literal, `routing_sync_dns_compute_context` delimited string, snell user JSON inline bash.
  - [x] Phase 4: Merged multi-field extractions — `ensure_singbox_auto_config` dual-read into single `@tsv` jq.
  - [x] Code review fixes: re-added grep fast-path for existing groups, added backslash escaping to snell JSON, replaced `head -c 1` with `read -r -n 1`, inlined dead `routing_sync_dns_context_fields`, renamed `context_json` to `context_delimited`.
  - [x] Re-validated with `bash -n` on all 12 modified files.

- [x] **u-2-120 perf: profile-guided startup fork reduction (2026-03-16)**
  - [x] Profiled `proxy menu` on gcp-oregon via `PS4+EPOCHREALTIME` tracing (309ms baseline, 1105 trace lines).
  - [x] Added `_PROXY_STAT_CACHE` in-memory associative array to `calc_file_meta_signature` (stat forks 15→9).
  - [x] Batched 2 `systemctl is-active` into 1 call (21ms→10ms); replaced all 8 `date` forks with `printf '%(%s)T'` builtin.
  - [x] Added re-entry guards for `ensure_runtime_log_files` and `ensure_file_fp_cache_maps`; replaced `dirname`/`basename` with parameter expansion.
  - [x] Result: main menu render 309ms→243ms (-21%) on e2-micro.
  - [x] Re-validated with `bash -n`; deployed and verified on `gcp-oregon`.

- [x] **u-2-120a ux: breathing dot loading animation (2026-03-16)**
  - [x] Replaced braille spinner with pulsing `●` using 256-color grayscale brightness cycling (240→255→240) at 120ms interval across all 4 spinner sites.
  - [x] Re-validated with `bash -n`.

- [x] **u-2-121 bugfix: test split view missing newline and redundant title (2026-03-16)**
  - [x] Fixed `proxy_cache_write_atomic` `printf '%s'` → `'%s\n'` to restore trailing newline stripped by command substitution.
  - [x] Removed redundant `测试分流效果（结果仅作快速自检）` title from `routing_render_test_effect_uncached` and pending view (already in `proxy_menu_header`).
  - [x] Re-validated with `bash -n`; deployed and verified on `gcp-oregon`.

- [x] **u-2-122 ux: Claude Code braille spinner (2026-03-16)**
  - [x] Replaced all spinner animations with Claude Code's exact spinner: braille dots `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` in `rgb(215,119,87)` at 80ms (extracted from Claude Code binary).
  - [x] Applied to all 4 spinner sites: `proxy_run_with_spinner`, `_compact`, `_fg`, and TLS cert wait.
  - [x] Re-validated with `bash -n`; deployed and verified on `gcp-oregon`.

- [x] **u-2-123 refactor: DRY spinner constants and fork-free sleep (2026-03-16)**
  - [x] Extracted `_PROXY_SPIN_FRAMES` and `_PROXY_SPIN_COLOR` globals in `common_ops.sh`; replaced 4 local array copies across 2 files.
  - [x] Fixed 3 printf lines where `${_PROXY_SPIN_COLOR}` was inside single quotes (variable won't expand); applied quote-breaking pattern.
  - [x] Replaced `sleep 0.08` with `read -t 0.08` builtin in 3 spinner loops to eliminate ~12.5 fork+exec/sec.
  - [x] Re-validated with `bash -n` on both modified files.

- [x] **u-2-124 ux: bouncing gradient bar spinner (2026-03-16)**
  - [x] Replaced braille/pulsing-dot spinner with bouncing gradient bar `█▓▒░` (14 frames, 120ms, `rgb(215,119,87)`).
  - [x] Left-aligned spinner output (removed 2-space indent) across all 4 spinner sites.
  - [x] Reverted `read -t` back to `sleep` (fork cost negligible at 120ms interval).
  - [x] Re-validated with `bash -n`; deployed and verified on `gcp-oregon`.

- [x] **u-2-125 ux: simplify user-facing output (2026-03-16)**
  - [x] Self-update: merged version prompt, simplified file count `正在更新 N/T 个文件`, removed verbose headers, fixed `spin_done` → `spin_clear_line` to avoid extra blank line.
  - [x] Bootstrap/install: removed duplicate install source line, verbose dependency/service/caddy messages, non-interactive hint simplified.
  - [x] Uninstall: removed blank lines between component sections and verbose progress messages.
  - [x] Autoconfig: removed `已自动生成 sing-box 配置` and `网络栈识别` messages.
  - [x] Bootstrap transition: removed `⟳ 配置生效中...` message.
  - [x] Protocol install: added `✓` checkmark to success message.
  - [x] Re-validated with `bash -n`; deployed and verified on `gcp-oregon`.

- [x] **u-2-126 bugfix: smart quotes and fresh install errors (2026-03-16)**
  - [x] Fixed Unicode curly quotes `\xe2\x80\x9c`/`\xe2\x80\x9d` in `self_update.sh` and `protocol_install_singbox_ops.sh` causing bash parse errors.
  - [x] Fixed `$(< file 2>/dev/null)` → `$(cat file 2>/dev/null)` in `runtime_status_ops.sh` for missing file on fresh install.
  - [x] Re-validated with `bash -n`; deployed and verified on `gcp-oregon`.

- [x] **u-2-127 refactor: code review cleanup (2026-03-16)**
  - [x] Negated `true` placeholder branches to proper `if !` guards in `install.sh`.
  - [x] Removed TOCTOU anti-pattern in `runtime_status_ops.sh`.
  - [x] Removed duplicate `source routing_core_ops.sh` in `routing_autoconfig_ops.sh`.
  - [x] Re-validated with `bash -n`.