# CORE-PHASE0-REPORT — Pha 0 lõi: topk 1 ↔ topk 3 trên 40 ca gate100

**Chỉ đo. Không file app, Parser.swift, Arbiter.swift hay thang điểm §3.6 nào bị sửa trong phần này.**

## Cách đo (chạy được)
- Nhánh `claude/opt-3` @ `012a339`. Code lõi y hệt v3 `774e163`; khác biệt chỉ ở tài liệu và công cụ harness.
- Lệnh: `gh workflow run harness-ci.yml --ref claude/opt-3 -f job=gate100`, lượt **[45221693993](https://github.com/zjoenguyenz/Sohoadon-claude-opt/actions/runs/45221693993)**.
  Workflow không sửa. Bên trong lượt đó:
  - `SoHoaDonHarness images --dir Gate100Images --sets 2 --dump streams-gate100-topk1` (mặc định `--lang old --topk 1`);
  - `SoHoaDonHarness images --dir Gate100Images --sets 2 --topk 3 --dump streams-gate100-topk3` — **topk 3 = cấu hình app thật**: `ClassicTextEngine.topCandidates = 3` (OCREngine.swift:126);
  - `python3 harness/tools/stream_compare.py streams-gate100-topk1 streams-gate100-topk3 --label-a topk1 --label-b topk3 --focus 02-walmart-2 --focus 01-walmart-1 --expect 40`.
- Dump dùng lượt (set) 1 của mỗi làn: **MỘT lượt trên 40 ca**, đúng phạm vi đã chốt, không mở rộng corpus.
- Hiện trạng làn: làn `--topk 3` và dump theo từng ứng viên (`scoreComponents` + `parseSummary`) **đã có trên v3** từ 2026-11-21 (commit 1ab97f1, d18229c, 95d27d1). Vòng này thêm vào `stream_compare.py`:
  - in **chuỗi đọc cuối đầy đủ** (dòng READ);
  - in **mọi ứng viên** kèm scoreComponents và tóm tắt parse suy từ scoreComponents (dòng CAND);
  - in ứng viên giàu bằng chứng nhất so với ứng viên thắng (dòng EVIDENCE).
  Toàn bộ dòng in nằm trong log của lượt trên, bước "GATE100 — đối chiếu luồng topk1 ↔ topk3".
- Giới hạn: ứng viên THUA không có ParseResult lưu trong chẩn đoán của app, nên không có giá trị cent. Tóm tắt parse của nó (e1/e2/e3 khép? có sub/tot/dòng thuế/ngày/tiệm?) được suy từ chính `scoreComponents` mà app đã chấm. "Giàu bằng chứng" = số cờ bằng chứng trong 8 cờ (e1, e2, e3, sub, tot, thuế, ngày, tiệm); hoà thì nhiều mảnh hơn.

## Tóm tắt máy in ra
```
SUMMARY compared=40 changed=1 unchanged=39 classChanged=0 totalsChanged=1 onlyA=0 onlyB=0
CLASSES topk1: closed=21 unclosed=18 all-nil=1
CLASSES topk3: closed=21 unclosed=18 all-nil=1
FOCUS 02-walmart-2: class unclosed -> unclosed (same), topk3 closed=no
FOCUS 01-walmart-1: class unclosed -> unclosed (same), topk3 closed=no
READ-SUMMARY changed=1 cases=14-cvs-pharmacy-2
COVERAGE topk1=40 topk3=40 expected=40 complete=yes
```

## Trả lời
### 1. 02-walmart-2 có khép sổ ở topk 3 không?
**Không.** Lớp `unclosed` ở cả topk 1 và topk 3, chuỗi đọc y hệt nhau:
`subtotal=8772 tax=135 total=8907 items=26 sumItems=6141` (E2 khép, E1 không: Σmón 6141 ≠ tạm tính 8772).

**Ứng viên thắng ở topk 3**: #4 `tiledRescue`, điểm −289.7, bằng chứng 6/8.
**Ứng viên giàu bằng chứng nhất** cũng là #4. Nó hoà 6/8 với #0 `original` và thắng phân hạng nhờ 163 mảnh so với 119. Vậy ở ca này **ứng viên thắng = ứng viên giàu bằng chứng nhất**; không có ứng viên giàu hơn bị loại.

Đối thủ cùng 6/8 là `original` (−678.9). Nó thua ở đúng hai thành phần:
- `itemsMissingAmountPenalty`: −1025 so với −700, tức 41 so với 28 món thiếu tiền;
- `moneyColumnIntegrity`: 25.0 so với 88.9.

Cả hai có cùng e2/sub/tot/thuế/ngày/tiệm. **Không ứng viên nào trong 5 ứng viên có e1 hay e3**, nên ở lượt này không có bản nào khép sổ được.

scoreComponents đầy đủ của mọi ứng viên, topk 3:
```
    CAND 02-walmart-2 topk3 #0 kind=original winner=no score=-678.9 gate=- frags=119 lines=67 evidence=6/8 [e1=n e2=Y e3=n sub=Y tot=Y tax=Y date=Y vendor=Y]
      scoreComponents: alnumTiebreak=1.107 e2Within2c=200.000 hasDate=20.000 hasSubtotal=30.000 hasTaxLine=20.000 hasTotal=40.000 itemsMissingAmountPenalty=-1025.000 moneyColumnIntegrity=25.000 vendorResolved=10.000
    CAND 02-walmart-2 topk3 #1 kind=shadowRemoved winner=no score=-40.0 gate=- frags=2 lines=2 evidence=1/8 [e1=n e2=n e3=n sub=n tot=n tax=n date=n vendor=Y]
      scoreComponents: alnumTiebreak=0.011 itemsMissingAmountPenalty=-50.000 vendorResolved=10.000
    CAND 02-walmart-2 topk3 #2 kind=enhanced winner=no score=-983.8 gate=- frags=139 lines=71 evidence=4/8 [e1=n e2=n e3=n sub=n tot=Y tax=Y date=Y vendor=Y]
      scoreComponents: alnumTiebreak=1.154 hasDate=20.000 hasTaxLine=20.000 hasTotal=40.000 itemsMissingAmountPenalty=-1175.000 moneyColumnIntegrity=100.000 vendorResolved=10.000
    CAND 02-walmart-2 topk3 #3 kind=binarized winner=no score=-1009.0 gate=- frags=113 lines=66 evidence=4/8 [e1=n e2=n e3=n sub=n tot=Y tax=Y date=Y vendor=Y]
      scoreComponents: alnumTiebreak=0.991 hasDate=20.000 hasTaxLine=20.000 hasTotal=40.000 itemsMissingAmountPenalty=-1100.000 vendorResolved=10.000
    CAND 02-walmart-2 topk3 #4 kind=tiledRescue winner=YES score=-289.7 gate=- frags=163 lines=77 evidence=6/8 [e1=n e2=Y e3=n sub=Y tot=Y tax=Y date=Y vendor=Y]
      scoreComponents: alnumTiebreak=1.398 e2Within2c=200.000 hasDate=20.000 hasSubtotal=30.000 hasTaxLine=20.000 hasTotal=40.000 itemsMissingAmountPenalty=-700.000 moneyColumnIntegrity=88.889 vendorResolved=10.000
```

### 2. 01-walmart-1 có đổi lớp kết quả giữa topk 1 và topk 3 không?
**Không đổi lớp**: `unclosed` ở cả hai làn. Ở lượt đo này chuỗi đọc cũng y hệt:
`subtotal=37692 tax=0 total=37692 items=1 sumItems=2049`.
Ứng viên thắng ở cả hai làn là #2 `enhanced` (−229.4, 3/8), cũng là ứng viên giàu bằng chứng nhất.

⚠ **Không ổn định giữa các lượt**: ở lượt gate100 trước, với cùng code lõi ([45156234663](https://github.com/zjoenguyenz/Sohoadon-claude-opt/actions/runs/45156234663)), tổng của ca này **có đổi**:
topk 1 `35465/2227/37692` (`binarized` thắng, −346.1) → topk 3 `37692/0/37692`. Lớp vẫn `unclosed`.

Ca 01-walmart-1 và 02-walmart-2 **không có trong gate100-gt.json**, nên không chấm đúng/sai được.

topk 1:
```
    CAND 01-walmart-1 topk1 #0 kind=original winner=no score=-305.1 gate=- frags=71 lines=45 evidence=2/8 [e1=n e2=n e3=n sub=n tot=n tax=n date=Y vendor=Y]
      scoreComponents: alnumTiebreak=0.623 hasDate=20.000 itemsMissingAmountPenalty=-350.000 moneyColumnIntegrity=14.286 vendorResolved=10.000
    CAND 01-walmart-1 topk1 #1 kind=shadowRemoved winner=no score=-139.9 gate=- frags=13 lines=11 evidence=1/8 [e1=n e2=n e3=n sub=n tot=n tax=n date=n vendor=Y]
      scoreComponents: alnumTiebreak=0.116 itemsMissingAmountPenalty=-250.000 moneyColumnIntegrity=100.000 vendorResolved=10.000
    CAND 01-walmart-1 topk1 #2 kind=enhanced winner=YES score=-229.4 gate=- frags=67 lines=44 evidence=3/8 [e1=n e2=n e3=n sub=n tot=Y tax=n date=Y vendor=Y]
      scoreComponents: alnumTiebreak=0.622 hasDate=20.000 hasTotal=40.000 itemsMissingAmountPenalty=-400.000 moneyColumnIntegrity=100.000 vendorResolved=10.000
    CAND 01-walmart-1 topk1 #3 kind=binarized winner=no score=-346.1 gate=- frags=61 lines=40 evidence=3/8 [e1=n e2=n e3=n sub=n tot=Y tax=n date=Y vendor=Y]
      scoreComponents: alnumTiebreak=0.581 hasDate=20.000 hasTotal=40.000 itemsMissingAmountPenalty=-450.000 moneyColumnIntegrity=33.333 vendorResolved=10.000
    CAND 01-walmart-1 topk1 #4 kind=tiledRescue winner=no score=-919.0 gate=- frags=130 lines=71 evidence=2/8 [e1=n e2=n e3=n sub=n tot=n tax=n date=Y vendor=Y]
      scoreComponents: alnumTiebreak=0.985 hasDate=20.000 itemsMissingAmountPenalty=-950.000 vendorResolved=10.000
```
topk 3:
```
    CAND 01-walmart-1 topk3 #0 kind=original winner=no score=-233.7 gate=- frags=71 lines=45 evidence=2/8 [e1=n e2=n e3=n sub=n tot=n tax=n date=Y vendor=Y]
      scoreComponents: alnumTiebreak=0.623 hasDate=20.000 itemsMissingAmountPenalty=-350.000 moneyColumnIntegrity=85.714 vendorResolved=10.000
    CAND 01-walmart-1 topk3 #1 kind=shadowRemoved winner=no score=-139.9 gate=- frags=13 lines=11 evidence=1/8 [e1=n e2=n e3=n sub=n tot=n tax=n date=n vendor=Y]
      scoreComponents: alnumTiebreak=0.116 itemsMissingAmountPenalty=-250.000 moneyColumnIntegrity=100.000 vendorResolved=10.000
    CAND 01-walmart-1 topk3 #2 kind=enhanced winner=YES score=-229.4 gate=- frags=67 lines=44 evidence=3/8 [e1=n e2=n e3=n sub=n tot=Y tax=n date=Y vendor=Y]
      scoreComponents: alnumTiebreak=0.622 hasDate=20.000 hasTotal=40.000 itemsMissingAmountPenalty=-400.000 moneyColumnIntegrity=100.000 vendorResolved=10.000
    CAND 01-walmart-1 topk3 #3 kind=binarized winner=no score=-346.1 gate=- frags=61 lines=40 evidence=3/8 [e1=n e2=n e3=n sub=n tot=Y tax=n date=Y vendor=Y]
      scoreComponents: alnumTiebreak=0.581 hasDate=20.000 hasTotal=40.000 itemsMissingAmountPenalty=-450.000 moneyColumnIntegrity=33.333 vendorResolved=10.000
    CAND 01-walmart-1 topk3 #4 kind=tiledRescue winner=no score=-919.0 gate=- frags=130 lines=71 evidence=2/8 [e1=n e2=n e3=n sub=n tot=n tax=n date=Y vendor=Y]
      scoreComponents: alnumTiebreak=0.985 hasDate=20.000 itemsMissingAmountPenalty=-950.000 vendorResolved=10.000
```

### 3. 38 ca còn lại: đổi kết quả đọc giữa hai cấu hình?
Ở lượt đo này **chỉ 1 ca đổi**:
- **14-cvs-pharmacy-2**: thuế 98 → 100 (subtotal 5958 / total 6056 không đổi; lớp `closed` cả hai làn).
  Ứng viên thắng đổi từ #0 `original` (340.5) sang #1 `shadowRemoved` (365.5). Lý do: `moneyColumnIntegrity` của `shadowRemoved` lên 0 → 100 ở topk 3, các thành phần khác giữ nguyên.
  **Đáp án GT: thuế 98, nên topk 3 đọc SAI ca này ở lượt đo.**
  Ở lượt trước (45156234663) ca này **không đổi** (98/98).

37 ca còn lại: **không đổi**, so trên chuỗi đọc cuối đầy đủ (tiệm, subtotal, thuế, total, số món, Σmón, sold, thẻ, số cờ).

Cột cuối của bảng là kết quả lượt trước (cùng code) để thấy độ ổn định:

| Ca | topk 1 (lượt đo) | topk 3 (lượt đo) | Chuỗi đọc đầy đủ | Lượt trước 45156234663 (topk1 → topk3) |
|---|---|---|---|---|
| 01-walmart-1 | unclosed 37692/0/37692 | unclosed 37692/0/37692 | **không đổi** | unclosed 35465/2227/37692 → unclosed 37692/0/37692 (ĐỔI) |
| 02-walmart-2 | unclosed 8772/135/8907 | unclosed 8772/135/8907 | **không đổi** | unclosed 8772/135/8907 → unclosed 8772/135/8907 (không đổi) |
| 03-target-1 | closed 1000/108/1108 | closed 1000/108/1108 | **không đổi** | closed 1000/108/1108 → closed 1000/108/1108 (không đổi) |
| 04-target-2 | closed 3855/54/3909 | closed 3855/54/3909 | **không đổi** | closed 3855/54/3909 → closed 3855/54/3909 (không đổi) |
| 05-best-buy-1 | closed 3298/200/3498 | closed 3298/200/3498 | **không đổi** | closed 3298/200/3498 → closed 3298/200/3498 (không đổi) |
| 06-kroger-1 | unclosed 1016/49/1065 | unclosed 1016/49/1065 | **không đổi** | unclosed 1016/49/1065 → unclosed 1016/49/1065 (không đổi) |
| 07-trader-joes-1 | unclosed 6618/0/6618 | unclosed 6618/0/6618 | **không đổi** | unclosed 6618/0/6618 → unclosed 6618/0/6618 (không đổi) |
| 08-trader-joes-2 | unclosed 4836/0/4836 | unclosed 4836/0/4836 | **không đổi** | unclosed 4836/0/4836 → unclosed 4836/0/4836 (không đổi) |
| 09-safeway-1 | closed 120/0/120 | closed 120/0/120 | **không đổi** | closed 120/0/120 → closed 120/0/120 (không đổi) |
| 10-publix-1 | closed 458/7/465 | closed 458/7/465 | **không đổi** | closed 458/7/465 → closed 458/7/465 (không đổi) |
| 11-publix-2 | unclosed 6327/331/6658 | unclosed 6327/331/6658 | **không đổi** | unclosed 6327/331/6658 → unclosed 6327/331/6658 (không đổi) |
| 12-aldi-1 | unclosed 12560/700/13260 | unclosed 12560/700/13260 | **không đổi** | unclosed 12560/700/13260 → unclosed 12560/700/13260 (không đổi) |
| 13-cvs-pharmacy-1 | unclosed 914/78/992 | unclosed 914/78/992 | **không đổi** | unclosed 914/78/992 → unclosed 914/78/992 (không đổi) |
| 14-cvs-pharmacy-2 | closed 5958/98/6056 | closed 5958/100/6056 | **ĐỔI** | closed 5958/98/6056 → closed 5958/98/6056 (không đổi) |
| 15-walgreens-1 | closed 1298/133/1431 | closed 1298/133/1431 | **không đổi** | closed 1298/133/1431 → closed 1298/133/1431 (không đổi) |
| 16-walgreens-2 | unclosed 5504/0/5504 | unclosed 5504/0/5504 | **không đổi** | unclosed 5504/0/5504 → unclosed 5504/0/5504 (không đổi) |
| 17-rite-aid-1 | unclosed 1857/0/1857 | unclosed 1857/0/1857 | **không đổi** | unclosed 1857/0/1857 → unclosed 1857/0/1857 (không đổi) |
| 18-mcdonalds-1 | closed 789/72/861 | closed 789/72/861 | **không đổi** | closed 789/72/861 → closed 789/72/861 (không đổi) |
| 19-mcdonalds-2 | unclosed 150/7/157 | unclosed 150/7/157 | **không đổi** | unclosed 150/7/157 → unclosed 150/7/157 (không đổi) |
| 20-mcdonalds-3 | closed 318/30/348 | closed 318/30/348 | **không đổi** | closed 318/30/348 → closed 318/30/348 (không đổi) |
| 21-chick-fil-a-1 | closed 1158/69/1227 | closed 1158/69/1227 | **không đổi** | closed 1158/69/1227 → closed 1158/69/1227 (không đổi) |
| 22-taco-bell-1 | all-nil nil/0/nil | all-nil nil/0/nil | **không đổi** | all-nil nil/0/nil → all-nil nil/0/nil (không đổi) |
| 23-starbucks-1 | closed 730/34/764 | closed 730/34/764 | **không đổi** | closed 730/34/764 → closed 730/34/764 (không đổi) |
| 24-hy-vee-gas-1 | unclosed 1288/110/1398 | unclosed 1288/110/1398 | **không đổi** | unclosed 1288/110/1398 → unclosed 1288/110/1398 (không đổi) |
| 25-exxon-1 | unclosed 2482/700/3182 | unclosed 2482/700/3182 | **không đổi** | unclosed 2482/700/3182 → unclosed 2482/700/3182 (không đổi) |
| 26-murphy-usa-1 | closed 2368/0/2368 | closed 2368/0/2368 | **không đổi** | closed 2368/0/2368 → closed 2368/0/2368 (không đổi) |
| 27-lowes-1 | closed 25598/1792/27390 | closed 25598/1792/27390 | **không đổi** | closed 25598/1792/27390 → closed 25598/1792/27390 (không đổi) |
| 28-lowes-2 | closed 600/36/636 | closed 600/36/636 | **không đổi** | closed 600/36/636 → closed 600/36/636 (không đổi) |
| 29-lowes-3 | closed 528/44/572 | closed 528/44/572 | **không đổi** | closed 528/44/572 → closed 528/44/572 (không đổi) |
| 30-lowes-4 | closed 1245/112/1357 | closed 1245/112/1357 | **không đổi** | closed 1245/112/1357 → closed 1245/112/1357 (không đổi) |
| 31-ace-hardware-1 | closed 299/31/330 | closed 299/31/330 | **không đổi** | closed 299/31/330 → closed 299/31/330 (không đổi) |
| 32-ace-hardware-2 | closed 1499/109/1608 | closed 1499/109/1608 | **không đổi** | closed 1499/109/1608 → closed 1499/109/1608 (không đổi) |
| 33-dunkin-donuts-1 | unclosed 244/9/253 | unclosed 244/9/253 | **không đổi** | unclosed 244/9/253 → unclosed 244/9/253 (không đổi) |
| 34-sams-club-1 | unclosed 15460/321/15781 | unclosed 15460/321/15781 | **không đổi** | unclosed 15460/321/15781 → unclosed 15460/321/15781 (không đổi) |
| 35-bjs-wholesale-club-1 | closed 2836/0/2836 | closed 2836/0/2836 | **không đổi** | closed 2836/0/2836 → closed 2836/0/2836 (không đổi) |
| 36-costco-1 | closed 8561/352/8913 | closed 8561/352/8913 | **không đổi** | closed 8561/352/8913 → closed 8561/352/8913 (không đổi) |
| 37-cvs-pharmacy-3 | unclosed 3770/321/4091 | unclosed 3770/321/4091 | **không đổi** | unclosed 3770/321/4091 → unclosed 3770/321/4091 (không đổi) |
| 38-publix-3 | unclosed 415/22/437 | unclosed 415/22/437 | **không đổi** | unclosed 415/22/437 → unclosed 415/22/437 (không đổi) |
| 39-publix-4 | unclosed 1240/0/81 | unclosed 1240/0/81 | **không đổi** | unclosed 1240/0/81 → unclosed 1240/0/81 (không đổi) |
| 40-mcdonalds-4 | closed 499/30/529 | closed 499/30/529 | **không đổi** | closed 499/30/529 → closed 499/30/529 (không đổi) |

## Đọc số (không suy diễn thêm)
- Trên lượt đo, topk 3 so với topk 1: lớp `closed=21 unclosed=18 all-nil=1` **giống hệt** ở hai làn; 1/40 ca đổi số (14-cvs-pharmacy-2, đổi theo chiều sai so với GT).
- Hai lượt cùng code cho **hai tập ca đổi khác nhau** (lượt trước: 01-walmart-1; lượt này: 14-cvs-pharmacy-2). Vậy chênh topk 1 ↔ topk 3 trên 40 ca hiện nằm **trong biên dao động giữa các lượt OCR**. Một lượt không đủ để quy hiệu ứng cho topk.
- Ở 3 ca có chi tiết (02, 01, 14), khi ứng viên thắng đổi hoặc gần đổi, thành phần quyết định là `moneyColumnIntegrity` và `itemsMissingAmountPenalty`, không phải cờ khép sổ.

## Đề xuất cho Pha 1 (CHỈ đề xuất, không thực hiện)
1. Trước khi đổi tầng chọn ứng viên: đo **≥ 2 lượt** mỗi cấu hình, hoặc chấm lượt tệ nhất như FL-314. Một lượt cho tập ca đổi không lặp lại được.
2. Ở 14-cvs-pharmacy-2, `moneyColumnIntegrity` (0 → 100 theo biến thể chữ của topk 3) lật ứng viên thắng sang một bản đọc thuế sai trong khi cờ khép sổ y hệt. Nên đo xem thành phần này có nên được phép thắng khi các cờ e1/e2/e3 bằng nhau hay không. Cần lệnh riêng và số trên corpus.
3. 02-walmart-2: không ứng viên nào có E1. Sửa tầng chọn **không** làm ca này khép sổ được. Nút thắt ở khối món: 28–41 món thiếu tiền tuỳ ứng viên, tức tầng đọc món/ráp dòng, không phải tầng chọn.
4. Muốn chấm 01/02-walmart đúng/sai thì cần thêm đáp án GT cho hai ca này (hiện không có trong gate100-gt.json).
