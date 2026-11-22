# -*- coding: utf-8 -*-
import sys, io
from docx import Document

out = io.open(r"D:\Учема 5 сем\Курсач\5_deepseek\_docs_text.txt", "w", encoding="utf-8")

def dump(path):
    out.write("\n" + "=" * 80 + "\n")
    out.write("FILE: " + path + "\n")
    out.write("=" * 80 + "\n")
    doc = Document(path)
    for i, p in enumerate(doc.paragraphs):
        t = p.text
        if t.strip():
            out.write("[" + p.style.name + "] " + t + "\n")
    for ti, tbl in enumerate(doc.tables):
        out.write("\n--- TABLE %d ---\n" % (ti + 1))
        for row in tbl.rows:
            cells = [c.text.strip() for c in row.cells]
            out.write(" | ".join(cells) + "\n")

for f in sys.argv[1:]:
    try:
        dump(f)
    except Exception as e:
        out.write("ERROR %s %r\n" % (f, e))
out.close()
print("done")
