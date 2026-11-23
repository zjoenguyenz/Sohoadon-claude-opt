# HOW IT WORKS — GL-Keeper (Sohoadon) — read this BEFORE auditing or optimizing

Written by the leader from the production project records and code. If anything
here disagrees with the code on branch `v3`, trust the code, flag the
disagreement in your PR, and do not silently follow this document.

## What the app is for (the owner's real job)
One person in Oklahoma keeps paper receipts for US tax purposes. He photographs
a receipt; the app reads it, files it as Personal or Business, keeps the
original photo as evidence, and at tax time exports a pack (PDF + CSV + ZIP)
his CPA can use. Accuracy of money is worth more than speed: a wrong total
that is NOT flagged is the worst possible failure.

## The core flow, end to end
1. **Capture** — camera document scan (VisionKit-style edge detection) or
   import (Sam's Club PDFs via share/Files; PDFs with a text layer are read
   as text, not OCR). Long receipts can be captured in multiple segments and
   stitched. Original image is NEVER modified; an enhanced copy is made only
   to help reading.
2. **Read (100% on-device, offline)** — Vision OCR on the iPhone. Fields:
   store, date, line items, tax, total, card last-4. Per-field confidence:
   high = accepted, mid = highlighted yellow for the owner to check,
   low = owner must confirm. There is NO cloud AI reading receipts.
3. **Reconcile / arbitrate** — the parsed items + tax must agree with the
   printed total; the totals/items arbiters cross-check the OCR. A receipt
   whose numbers do not reconcile gets a warning flag — and a flagged receipt
   CANNOT be approved until resolved (that gate is intentional, not a bug).
   Oklahoma tax logic is rule-based (state + city rates, groceries vs goods),
   not learned: item type → tax rate is a step inside the totals mechanism.
4. **Classify** — Personal vs Business is suggested by the registered card
   last-4 (each card is registered as Personal or Business in Settings);
   no card match → the receipt waits in a review inbox, never guessed.
   Line-level split is supported: one receipt can contain both kinds, and
   the split parts (+ allocated tax) must sum to the receipt total.
   The app learns per-store profiles from the owner's own approved receipts
   (layout, tax labels, local Tulsa/Oklahoma stores) — local learning,
   on-device only.
5. **Review & approve** — nothing is an official record until the owner
   approves it. The review screen shows original image beside parsed fields;
   he edits the wrong field, not the whole receipt.
6. **Store** — SwiftData on the device is the source of truth; original
   images are stored as files (~300–600 KB each). Deleting the app deletes
   the sandbox — there is no server copy.
7. **Sync (Google Drive)** — Drive sync (drive.file scope, OAuth PKCE)
   mirrors receipts to a `GL-Keeper/` folder on the owner's Drive with a
   manifest; it is a backup/mirror, not the source of truth. Sync must
   self-recover from network drops without erroring the run.
8. **Export** — Tax Pack per year and per Personal/Business: PDF (table +
   original images), CSV (must match the app to the cent), ZIP.

## Build & delivery flow (how code reaches the owner's phone)
- GitHub Actions workflow `build-ipa.yml` on branch `v3` builds TWO unsigned
  IPAs: the main app and a bench/harness app used to measure the reading
  core against a frozen receipt corpus. A green main build with a red
  harness is NOT a pass.
- The owner signs the unsigned IPA with his own signing app and installs it
  himself. No TestFlight, no App Store, no developer account.
- His phone: latest iPhone Pro Max on the newest iOS — optimize for that
  hardware's headroom, not for a weak-device floor.

## What "optimization" must never break
- The reconciliation/flag gate, the approval gate, duplicate detection
  (same purchase via photo + PDF must be caught), the 7-year retention
  default, Face ID lock, and the diagnostic-log export.
- Money math must stay cent-exact. Any change near parsing/totals must be
  validated against the bench harness, not just compiled.

## Where the bodies are buried (known history)
- The reading core was rebuilt (v4 parser) after earlier parsers measured
  well on the wrong read path — always measure through the app's real
  ReadPipeline, never a side path.
- 14 original receipt images once went missing from the device store in a
  recent-build window; cause never convicted. Treat image-store writes and
  migrations as high-risk surfaces.
