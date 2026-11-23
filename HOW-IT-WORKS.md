# HOW IT WORKS — GL-Keeper (Sohoadon) — read this BEFORE auditing or optimizing

Written by the leader from the production project records and code. If anything
here disagrees with the code on branch `v3`, trust the code, flag the
disagreement in your PR, and do not silently follow this document.

## What the app is for (the owner's real job)
One person in Oklahoma keeps paper receipts for US tax purposes. He photographs
a receipt; the app reads it, files it as Personal or Business, keeps the
original photo as evidence, and at tax time is meant to export a pack (PDF + CSV + ZIP —
not built yet, see §8) his CPA can use. Accuracy of money is worth more than speed: a wrong total
that is NOT flagged is the worst possible failure.

## The core flow, end to end
1. **Capture** — camera document scan (VisionKit-style edge detection) or
   import (Sam's Club PDFs via share/Files; PDFs with a text layer are read
   as text, not OCR). Long receipts can be captured in multiple segments and
   stitched. The stored original is never edited after it is saved, but
   imported/captured PHOTOS are stored re-compressed as JPEG q0.8 via
   `ImageStore.saveJPEG` (not the camera/library bytes); only PDFs keep their
   original bytes (`ImageStore.saveFile`). An enhanced/flat copy is made only
   to help reading.
2. **Read (100% on-device, offline)** — Vision OCR on the iPhone. Fields:
   store, date, line items, tax, total, card last-4. Per-field confidence:
   high = accepted, mid = highlighted yellow for the owner to check,
   low = owner must confirm. There is NO cloud AI reading receipts.
3. **Reconcile / arbitrate** — the parsed items + tax must agree with the
   printed total; the totals/items arbiters cross-check the OCR. A receipt
   whose numbers do not reconcile gets a warning flag. The approval gate is
   CLASSED (`ReceiptLogic.approvalGate`): a flagged receipt CAN be approved
   after an explicit confirmation that lists each flag (recorded as
   `confirmedWithFlag`); only a missing original file BLOCKS approval.
   Oklahoma tax logic is rule-based (state + city rates, groceries vs goods),
   not learned: item type → tax rate is a step inside the totals mechanism.
4. **Classify** — Personal vs Business is suggested by the registered card
   last-4 (each card is registered as Personal or Business in Settings);
   no card match → the receipt waits in a review inbox, never guessed.
   Line-level Personal/Business split is FOUNDATION ONLY: the `LineItem`
   fields exist, but nothing writes them and there is no UI.
   Store profiles (v1) learn only ZIP + tax category + approved-receipt count
   from the owner's own approved receipts — local learning, on-device only
   (`StoreProfiles.json` in Application Support).
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
8. **Export** — the Tax Pack export does NOT exist yet: Reports shows a
   preview table only, with a "coming in a later version" note. Planned:
   PDF + CSV (must match the app to the cent) + ZIP per year.

## Build & delivery flow (how code reaches the owner's phone)
- GitHub Actions workflow `build-ipa.yml` on branch `v3` builds TWO unsigned
  IPAs: the main app and a bench/harness app used to measure the reading
  core against a frozen receipt corpus. `build-ipa.yml` does NOT run the
  harness: the harness is the separate manual-dispatch workflow
  `harness-ci.yml`. A green main build with a red harness is still NOT a
  pass — but that rule is procedural, not enforced by CI.
- The owner signs the unsigned IPA with his own signing app and installs it
  himself. No TestFlight, no App Store, no developer account.
- His phone: latest iPhone Pro Max on the newest iOS — optimize for that
  hardware's headroom, not for a weak-device floor.

## What "optimization" must never break
- The reconciliation/flag gate, the approval gate, duplicate detection
  (same purchase via photo + PDF must be caught), Face ID lock, and the
  diagnostic-log export. (7-year retention: `Receipt.retentionUntil` exists
  in the model but is never assigned anywhere yet.)
- Money math must stay cent-exact. Any change near parsing/totals must be
  validated against the bench harness, not just compiled.

## Where the bodies are buried (known history)
- The reading core was rebuilt (v4 parser) after earlier parsers measured
  well on the wrong read path — always measure through the app's real
  ReadPipeline, never a side path.
- 14 original receipt images once went missing from the device store in a
  recent-build window; cause never convicted. Treat image-store writes and
  migrations as high-risk surfaces.
