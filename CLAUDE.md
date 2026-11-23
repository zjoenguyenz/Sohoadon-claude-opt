# CLAUDE.md — Sohoadon-claude-opt (GL-Keeper)

This repository is an ISOLATED OPTIMIZATION COPY of `zjoenguyenz/Sohoadon`.
It exists so Claude Code can optimize the app without touching the production repo.
The human leader (Wally, on behalf of the owner) reviews every result here before
anything is ported back to the original repository. Nothing here ships to the owner
directly.

## The app
- Display name: **GL-Keeper** (receipt book / Sổ Hóa Đơn). Bundle ID must stay
  `com.nje.sohoadon` — never change it.
- iOS app, Swift / SwiftUI + SwiftData, unsigned IPA built by GitHub Actions
  (`.github/workflows/build-ipa.yml`). The owner signs and installs it himself.
- **Working branch of the original project is `v3`, NOT `main`.** Treat `v3` as the
  baseline. Do not optimize the stale `main` snapshot.

## Hard rules (owner's standing laws — no exceptions)
1. Work ONLY in this repository, and only on branches named `claude/opt-*`.
   Never push to `v3` or `main` directly. Open a pull request into `v3` inside
   THIS repo when a chunk is ready; the leader reviews the diff.
2. No data-model / SwiftData schema changes, no bundle-ID change, no settled
   design/spec changes, nothing that touches the owner's real saved data —
   unless the leader's prompt for that round explicitly authorizes it.
3. Optimization means: performance, memory, code clarity, dead-code removal,
   and build reliability — with **zero behaviour change** unless the prompt
   says otherwise. Every optimization PR must state what was measured
   before/after (method + numbers). Unmeasured "optimizations" are rejected.
4. Never fabricate APIs, methods, build flags or library names. Target the
   iOS version and Swift version the project actually uses; check the project
   files before assuming. If behaviour cannot be verified, say so in the PR.
5. Do not add secrets, tokens or credentials anywhere. Do not edit
   `.github/workflows/*` unless the prompt explicitly asks for CI work.
6. Keep commits small and batched per topic. Do not reformat whole files for
   cosmetic reasons — it destroys diff reviewability.
7. The app must keep its built-in diagnostic-log export working.

## Review gate
Code is not "done" when it compiles locally. Each PR description must include:
what changed, why, before/after measurements, risks, and what was NOT verified.
The leader runs the project's own review + CI before anything is ported back.
