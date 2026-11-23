#!/usr/bin/env python3
"""set_compare — cổng nghiệm thu vòng 3 (công cụ đội, KHÔNG phải code app).

So kết quả đọc của HAI log harness (bước `images`, dòng
"SET n <ảnh>: frag[...] asm[...] vendor=... subtotal=... tax=...").
Vì OCR Vision dao động giữa các lượt, chỉ so trên nhóm (ảnh, điều tra
mảnh frag[...]) có MẶT ở cả hai log; mỗi nhóm là TẬP kết quả quan sát
được (bỏ trường score). Một nhóm "NOVEL" = log B có kết quả chưa từng
thấy ở log A cho cùng ảnh + cùng điều tra mảnh.

Cách lấy log: gh run view <RUN> --log | sed 's/^[^\\t]*\\t[^\\t]*\\t[0-9TZ:.-]* //' > run.log
Dùng: python3 set_compare.py BASE.log NEW.log
"""
import re
import sys


def load(path):
    d = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"SET (\d+) (\S+\.jpg): (frag\[[^\]]*\]) (.*)", line.strip())
        if m:
            d.setdefault((m.group(2), m.group(3)), set()).add(
                re.sub(r" score=\S+", "", m.group(4)))
    return d


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    a, b = load(argv[1]), load(argv[2])
    common = set(a) & set(b)
    novel = [(k, b[k] - a[k], a[k]) for k in sorted(common) if b[k] - a[k]]
    cases = {k[0] for k in a} | {k[0] for k in b}
    covered = {k[0] for k in common}
    print(f"groups={len(common)} withNovelOutcome={len(novel)} "
          f"casesCovered={len(covered)}/{len(cases)} uncovered={sorted(cases - covered)}")
    for k, new, old in novel:
        print("NOVEL", k[0], k[1])
        print("   before:", sorted(old))
        print("   after: ", sorted(new))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
