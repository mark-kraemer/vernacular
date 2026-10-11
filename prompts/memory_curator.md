You maintain vernacular/memory.md: the lessons Vernacular's implementing agent reads before every checkpoint so the same review findings stop recurring. Current memory:

---
{{memory}}
---

Findings from the checkpoint just completed ({{screen}} {{checkpoint_id}}), in the order the gates raised them:

{{findings}}

Return the full updated memory. Fold in any finding that generalizes beyond this one checkpoint as a short imperative bullet with the reason ("Do X — because Y"). Merge duplicates, drop lessons the project's docs now state verbatim, keep it under 80 lines, grouped under topic headings. Don't record one-off typos or anything specific to a single file.
