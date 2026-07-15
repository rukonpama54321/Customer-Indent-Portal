# With-Vehicle Port — Tier 2 Business Decisions

Two behaviours in the original WebDynpro (INDMAIN) diverge from the new Fiori/Gateway
port. Both are **business-logic calls**, not code defects — I need a decision from the
process owner before porting them, because either direction is a valid implementation
and picking wrong changes what users see.

Source of truth: `.vscode/docs/out.txt` (the WebDynpro original).

---

## Q1 — M10: Should a multi-depot user's *filtered* indent list show all their depots, or only their first depot?

**Who is affected:** only users mapped to **more than one depot** in `zsd_cust_usr_map`.
Single-depot users see no difference either way.

**What WebDynpro does today** (out.txt 597–646):

- When the user applies an **Indent Type** filter *or* a **Deletable** filter, WD narrows
  the open-indent list to **one depot only** — the *first* row of their depot mapping
  (`READ TABLE ZTABCUST … INDEX 1`, then `DELETE … WHERE DEPOT <> ZTABCUST1-DEPOT`).
- When **no** such filter is applied, WD shows **all** mapped depots.

**What the new port does today** (`GETINDENTSet`): always shows **all** mapped depots,
whether or not a filter is applied.

**The decision:** For a multi-depot user who filters by Indent Type or Deletable —

- **(A) Match WebDynpro** — collapse the filtered list to their first/primary depot only.
- **(B) Keep the port's behaviour** — keep showing all mapped depots even when filtered.

> My read: the WebDynpro narrowing looks incidental (a side-effect of reusing the
> single-depot code path), and option (B) is the more intuitive behaviour — a filter on
> *type* shouldn't silently also filter by *depot*. But this is a business call: if any
> report, reconciliation, or user habit depends on the filtered view showing a single
> depot, choose (A) and I'll replicate it exactly.

---

## Q2 — M12: Is the Material Price Group **IN / EP** dropdown still in use for non-special products?

**Context — the contract/price dropdown has two modes** (out.txt 9049–9161):

- **Special products** (material code prefix `PWAX`, `RPC0`, `CPC0`, `SUL0`, or `GWAX`):
  the dropdown lists the user's **live sales contracts** (contract number + open balance).
- **All other (non-special) products** (the `ELSE` branch): the dropdown instead lists
  **Material Price Group codes `IN` and `EP`** pulled from table `T178`
  ("Added for Material Price Group").

**What the new port does today:** it runs the **contract path unconditionally** for every
product. So:
- `GWAX` (and the other special) products already get their contract list — that part is fine.
- Non-special products currently get a (usually empty) contract list **instead of** the
  `IN` / `EP` price-group options.

**Why these two are coupled:** if I add the "special-product" gate but *not* the `IN/EP`
else-branch, non-special products would show a **blank** dropdown. So I port **both or neither**.

**The decision:** Is the **IN / EP** Material Price Group selection still a live feature
for non-special products?

- **(A) Yes, still used** — I port the special-product gate **and** the `IN/EP` else-branch,
  restoring the price-group dropdown for non-special products. (Full WD parity.)
- **(B) No, it's dead** — non-special products don't need that dropdown anymore. I leave the
  gate out and document it as a deliberate drop (simpler, no blank dropdown).

> I can't tell from the code alone whether IN/EP is still an active business flow or
> legacy — hence the question. If unsure, (A) is the safe/parity-preserving choice.

---

### Summary for the owner

| # | Question | Options | Affects |
|---|----------|---------|---------|
| Q1 | Filtered list scope for multi-depot users | (A) first depot only / (B) all depots | Multi-depot users only |
| Q2 | Is IN/EP price-group dropdown still used? | (A) yes → full parity / (B) no → drop it | Non-special products |

Once I have answers to both, I can implement M10 and the remaining M12 branch (GWAX gate +
IN/EP else) together.
