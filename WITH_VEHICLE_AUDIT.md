# With-Vehicle Port — Fidelity Audit

**Scope:** SAPUI5 + Gateway port of the WebDynpro `INDMAIN` **With Vehicle** tab, audited against the WebDynpro source of truth (`.vscode/docs/out.txt`).

**Method:** each WebDynpro action handler was diffed against its ported Gateway DPC method and UI5 controller/view. Findings are behavioral-fidelity gaps only (cosmetics excluded unless noted).

**Files audited**
- Main DPC — `backend/ZCL_ZSDI_ODATA_CUST_PO_DPC_EXT.abap`
- Main MPC — `backend/ZCL_ZSDI_ODATA_CUST_PO_MPC_EXT.abap`
- Deep DPC — `backend/ZCL_ZSD_CUST_PORTAL_DE_DPC_EXT.abap`
- Controllers — `webapp/controller/WithVehicleTab.controller.js`, `webapp/controller/ChangeIndentWithVehicleTab.controller.js`
- Views — `webapp/view/WithVehicleTab.view.xml`, `webapp/view/ChangeIndentWithVehicleTab.view.xml`
- Deep metadata — `backend/ZCL_ZSD_CUST_PORTAL_DE_MPC.abap` (runtime model; the local mock copy was removed when the mock server was retired)

---

## Headline

**The `ZPROD_GRP_INDENT` quantity-vs-plan cap — the core business control of this tab — is enforced NOWHERE in the port.**
It is broken on the **save** path (H1) and entirely absent on the **submit** path (H2). Over-plan indents both save and submit freely.

---

## Port progress

Remediation is being applied in batches (see order at the bottom). Status as of 2026-07-06:

| Batch | Scope | Status |
|-------|-------|--------|
| 1 | H1 + H2 — qty-vs-plan cap on SAVE and SUBMIT | ✅ Done |
| 2 | H3 — `SalesContractSet` filter rewrite (KUNNR/product/depot/NVEH) | ✅ Done |
| 3 | H4 — Change screen clobbers saved quantities | ✅ Done |
| 4 | H5, M2, M7 — dropped save validations | ✅ Done |
| 5 | M3–M6 — deep-service correctness | ✅ Done |
| 6 | M8, M9 — Change-screen ATF flushing + HSD end-use | ✅ Done |
| 7 (Tier 1) | M1, M11, M13, M12 (VBFA open-balance) — cheap correctness | ✅ Done |
| 8 (Tier 2) | M10 (first-depot narrowing), M12 (T178 IN/EP + GWAX gate) | ✅ Done |
| — | L-series | ⬜ Pending (Tier 3, cosmetic — candidate won't-fix) |

**Batch 1 (H1/H2) — done.** `create_entity` now aggregates compartment qty by SPART into the LPG/MS/… summary columns before INSERT; `qty_plan_check` reads real `SELECT SUM` bookings before comparing to `ZPROD_GRP_INDENT`; new `qty_plan_check_submit` gates `submit_indents` (booked SUMs exclude status-4 rows).

**Batch 2 (H3) — done.** `get_entityset` WHEN `SalesContractSet` rewritten to mirror WD `ONACTIONSELECT_EXPORT` (out.txt 9042–9161): reads `KUNNR` + `PRODUCT1` filters, exact `vbap~matnr = PRODUCT1`, adds `werks = <user depot>` and `pstyv <> 'ZTAE'`, dropped the loose `matnr LIKE` prefix + whole-scope loop + spurious `abgru = space`; added the `ZSD_INDENT_NVEH` open-order (`ord_closed = space`) replacement path (list rebuilt from `order_no`). *Deferred to M12: VBFA RQTY open-balance formula, GWAX prefix, T178 IN/EP branch.*

**Batch 3 (H4) — done.** `ChangeIndentWithVehicleTab._loadCompartments` no longer calls `setValue()` on the compartment product/qty Inputs (both the reset loop and the `COMPOSITION` write are gone). Those Inputs are two-way bound to `SelectedIndent>/PROD_CMPn` and `/QUAN_COMPn`, so `setValue` was writing back through the binding and wiping the saved indent before the user touched anything. Now only `setEditable` is managed — the saved qty/product values loaded in `_onObjectMatched` are preserved, mirroring WD `REACT_TO_MODIFY` (out.txt 5253–5372) which re-binds product dropdowns + re-enables fields but never clears stored quantities.

**Batch 4 (H5/M2/M7) — done.** Three dropped save validations restored in `create_entity` (`ZCL_ZSDI_ODATA_CUST_PO_DPC_EXT.abap`): (H5) the duplicate-indent check now has WD's ELSE branch — when no blank-SHNUMBER draft exists, it reads any existing indent's SHNUMBER for begda/vehicle/depot and blocks if its shipment is still in progress (`OIGS-OIG_SSTSF < 6`); (M2) the bulk-order block now guards comp-1 qty against the open-order balance (`lv_qty1 > ZSD_INDENT_NVEH-BL_QTY1 × 1000`, `ord_closed = space`) before decrementing, mirroring WD `ONACTIONCHECK_QUANTITY`; (M7) the mandatory-contract check now tests PWAX across `PROD_CMP1..6` (and SUL0/RPC0/CPC0 in comp 1, aligned to WD's 4-char match) instead of comp 1 only.

**Batch 5 (M3–M6) — done.** Deep-service correctness in `ZCL_ZSD_CUST_PORTAL_DE_DPC_EXT.abap` (+ the M4 key plumbing). (M3) `delete_indents` now reads `ZSD_INDENT_NVEH` by the indent's `BULK_ORDER`, adds `BULK_QTY` back to `BL_QTY1`, and `MODIFY`s it after a successful delete when `ORDER_NO` is set (both status-4 and status-5 branches), mirroring WD `ONACTIONREACT_TO_YES` (out.txt 5430–5442 / 5478–5482). (M4) the deep item key gained `DEPOT` + `KUNNR` — `ty_item`, both `submit_indents`/`delete_indents` WHERE clauses, `metadata.xml` (ZCREATEItems/ZDELETEItems keys), the UI submit/delete payloads (`WithVehicleTab.controller.js`), and the `GETINDENT` projection + MPC (`_p 'DEPOT'`) — so a one-row submit/delete can no longer sweep the user's other same-date+vehicle indents. (M5) `submit_indents` now sets `ls_tbl-atf_flash = ls_ind-atf_flush` after the `MOVE-CORRESPONDING` (names differ, so it was silently dropped), per WD out.txt 10000. (M6) the staging-cleanup WHERE clauses now branch on status: status 4 → both `ZSAUTOMATETT_TBL` and `_LPG` sweep `( ztt_status = '4' OR shnumber = ' ' )`; status 5 → both restricted to `ztt_status = '5'` (was one generic pair — TBL always had `OR shnumber=' '`, LPG never), per WD out.txt 5446–5452 / 5484–5490.

> **M4 backend note:** `DEPOT`/`KUNNR` were added as key properties across the deep model — the local `metadata.xml` **and** the runtime MPC base class `ZCL_ZSD_CUST_PORTAL_DE_MPC` (added to the repo): both `TS_ZCREATEITEMS`/`TS_ZDELETEITEMS` bound structures and the `DEFINE_ZCREATEITEMS`/`DEFINE_ZDELETEITEMS` `create_property` blocks (keys, EDM string, `set_label` literals to avoid new text-pool symbols). The base MPC carries a "never hand-modify — change in SEGW" banner: on deploy, re-add the two fields to the ZCREATEItems/ZDELETEItems entities in SEGW and regenerate (which also refreshes the metadata cache per the gateway-stale-serializer procedure), so a later SEGW regen doesn't wipe these edits. Until the model refresh + cache clear, the gateway won't deserialize the new payload keys.

> Not compiler-verified — edits cross-checked against out.txt only. Batch 1 needs a two-indent over-plan regression test; Batch 2 needs a contract-dropdown test (correct customer/product/depot + open-bulk-order surfacing); Batch 4 needs: an active-shipment duplicate test (H5 — indent with in-progress shipment blocks a second save), an over-draw bulk-order test (M2), and a PWAX-in-comp2+ save test (M7). Batch 5 needs: a delete-restores-bulk-balance test (M3), a two-customer/depot same-vehicle submit+delete test to confirm only the selected row is touched (M4), an ATF-tanker submit test that the flushing flag lands in `ZSAUTOMATETT_TBL` (M5), and a status-4 vs status-5 delete test for correct staging cleanup (M6).

---

## HIGH severity

### H1 — Qty-vs-plan cap non-functional on SAVE  ✅ FIXED (Batch 1)
Two linked defects render `EXECUTE_Z_INDENT_QTY_CHECK` (WD out.txt 821–1626) inert:
- **Summary qty columns never written on INSERT.** WD aggregates each compartment qty by SPART into `ZSD_CUST_INDENT` columns `LPG/MS/ATF/SKO/HSD/ARHSD/PWAX/MTO/RPC/SUL/NTG/OTHER` (out.txt 994–1018) and inserts that row (7494). Port `create_entity` (`ZCL_ZSDI_ODATA_CUST_PO_DPC_EXT.abap:799–871`) never assigns any of them → every row inserted with these = 0. (These columns exist in the MPC entity type but are never filled.)
- **Plan check never sums prior bookings.** WD runs `SELECT SUM(<col>)` three times (by KUNNR, by KDGRP, by depot/date total), adds the new qty, compares to `ZPROD_GRP_INDENT` (out.txt 1028–1570). Port `qty_plan_check` (`:1289–1300`) sets the three accumulators to *only the current indent's qty* — the SUM reads were never written (code comment admits it).
- **Consequence:** any number of individually-under-plan indents all save even when their daily sum blows past the plan cap.
- **Fix:** populate the per-SPART summary columns in `create_entity` before INSERT (mirror out.txt 994–1018), then add the three `SELECT SUM` reads in `qty_plan_check` before adding the new qty. (Refactor `qty_plan_check` to `CHANGING is_indent` so it can both read and write.)

### H2 — Qty-vs-plan cap absent on SUBMIT  ✅ FIXED (Batch 1)
WD `ONACTIONSUBMIT_INDENT` gates the entire submit body on `EXECUTE_Z_IND_QTY_CHECK_SUBMIT` (out.txt 9861–9885; check body 1628–2571), which re-aggregates per-SPART totals (excluding status-4 rows via the `VW_SV2='X'` branch) against `ZPROD_GRP_INDENT` and blocks over-plan submits. Port `submit_indents` (`ZCL_ZSD_CUST_PORTAL_DE_DPC_EXT.abap:76–156`) performs **no** plan check — every status-4 row is moved to status 5 unconditionally.
- **Fix:** reimplement the `ZPROD_GRP_INDENT` comparison (with the status-4-excluded sums) in `submit_indents` and skip/error rows that exceed plan.

### H3 — `SalesContractSet` built from wrong criteria  ✅ FIXED (Batch 2)
The contract dropdown handler (`ZCL_ZSDI_ODATA_CUST_PO_DPC_EXT.abap:351–386`) diverges from WD `ONACTIONSELECT_EXPORT` (out.txt 9042–9161) on nearly every filter. The controller *does* send `KUNNR`/`PRODUCTn` filters (`WithVehicleTab.controller.js:514–519`) — the backend never reads them.
- Selected `KUNNR` ignored → loops the **entire** customer scope (`:359–383`) instead of `vbpa~kunnr = LV_KUNNR1` (out.txt 9081).
- Exact product match `vbap~matnr = LV_PROD1` (out.txt 9083) replaced with `matnr LIKE 'PWAX%'/'SUL%'/'RPC%'/'CPC%'` (`:371–372`).
- Depot filter `vbap~werks = ZDEPOT` (out.txt 9084) dropped entirely.
- `ZSD_INDENT_NVEH` open-order replacement path (out.txt 9102–9119: if an open no-vehicle indent exists on the contract, rebuild the list from NVEH rows with `BL_QTY1` as balance) missing.
- **Consequence:** contract dropdown lists contracts for all of the user's customers/plants, matched by loose prefix, and never surfaces the open bulk-order path.
- **Fix:** in `SalesContractSet`, read `KUNNR` + `PRODUCT1` via `get_filter_value`, add `werks = <depot>` and exact `matnr = PRODUCT1`, and replicate the `ZSD_INDENT_NVEH` replacement loop.

### H4 — Change screen silently corrupts saved quantities  ✅ FIXED (Batch 3)
`ChangeIndentWithVehicleTab.controller.js` `_loadCompartments` (`:60–63`) unconditionally runs `oQty.setValue(oComp.COMPOSITION)` per compartment. The qty inputs are two-way bound to `SelectedIndent>/QUAN_COMPn` (view `:63–77`), so entering the Change screen **replaces the user's saved quantities with the vehicle's default composition/capacity** (and blanks empty-composition compartments) before the user touches anything. `onUpdateIndent` then posts the clobbered values. WD `REACT_TO_MODIFY` (out.txt 5300–5335) repopulates products and re-runs capacity but does **not** wipe stored quantities.
- **Fix:** on the change screen only call `setEditable`; do not overwrite `QUAN_COMPn` with `COMPOSITION`.
- **Fixed:** removed all `setValue()` calls from `_loadCompartments` (the reset-loop blanking of product/qty **and** the `COMPOSITION` write both propagated through the two-way binding). The method now manages editability only; saved product/qty values loaded in `_onObjectMatched` survive intact.

### H5 — Duplicate-indent check ignores active-shipment case  ✅ FIXED (Batch 4)
WD blocks a save when the existing indent has an assigned shipment whose `OIGS-OIG_SSTSF < 6` (out.txt 6240–6249). Port (`:680–685`) only counted rows with `shnumber = ' '` (blank). A vehicle that already had an indent with an in-progress (status < 6) shipment was not detected.
- **Consequence:** a duplicate indent could be created for a vehicle with an active shipment.
- **Fixed:** added WD's ELSE branch — when no blank-SHNUMBER draft exists, `SELECT SINGLE shnumber` for begda/vehicle/depot, then `SELECT SINGLE oig_sstsf FROM oigs`, and raise the same "Indent already available" message when `sy-subrc = 0 AND oig_sstsf < 6`.

---

## MEDIUM severity

### M1 — Depot-scoped special-customer include/exclude dropped (scope leak)  ✅ FIXED (Tier 1)
WD `WDDOINIT` (out.txt 2686–2731): if mapped `DEPOT <> '3100'` it **deletes** `0000100036`; if `DEPOT <> '3202'` it deletes `0000100192/193/194/195`. Port `get_user_scope`/`ZUSERSet` (`:1164–1194`, `:173–185`) never applies these removals → those customers stay selectable for the wrong depot. **Fixed:** `get_user_scope` now, after building + deduping the KUNN2 set, deletes `0000100036` from `et_kunnr` unless a `3100` depot is mapped, and `0000100192/193/194/195` unless a `3202` depot is mapped (out.txt 2723–2731). The INDEX-1 re-ordering (2686–2722) is cosmetic (L10) and intentionally not reproduced.

### M2 — Bulk-order balance check missing on SAVE  ✅ FIXED (Batch 4)
WD `ONACTIONCHECK_QUANTITY` (out.txt 3518–3598): for PWAX/CPC0/SUL0/RPC0/GWAX with a selected order, blocks when comp-1 qty > `ZSD_INDENT_NVEH-BL_QTY1 × 1000`. Port read `znveh_ind` (`:751`) and later decremented `bl_qty1` (`:1062`) but never validated the qty against the remaining balance → over-draw; `BL_QTY1` could go negative on the subsequent MODIFY. **Fixed:** added the `lv_qty1 > znveh_ind-bl_qty1 * 1000` guard (gated on `ord_closed = space`) right where `znveh_ind` is read in the contract block, raising WD's "Order balance = … is less than indent quantity. You may close the order." message before `contract1` is resolved. *(Distinct from the VBAP/VBFA sales-contract balance check, which is correctly ported.)*

### M3 — Bulk-order qty not restored on DELETE  ✅ FIXED (Batch 5)
WD `ONACTIONREACT_TO_YES` (out.txt 5430–5442, 5478–5482) restores `ZSD_INDENT_NVEH-BL_QTY1 += BULK_QTY` on successful delete. Port `delete_indents` never touched `ZSD_INDENT_NVEH` → bulk balances drifted downward permanently. **Fixed:** `delete_indents` reads `ZSD_INDENT_NVEH` by `ls_ind-bulk_order`, adds `bulk_qty` to `bl_qty1`, and `MODIFY`s it after the indent delete succeeds when `order_no` is not initial — applied in both the status-4 and status-5 delete branches.

### M4 — Deep-entity item key under-specified (submit/delete over-reach)  ✅ FIXED (Batch 5)
Deep item type carried only `BEGDA/VEHICLE/CUST_USER_ID/ZTT_STATUS`. Both `submit_indents` and `delete_indents` re-SELECTed by that partial key and looped over **all** matches — no DEPOT/KUNNR. A user with multiple indents on the same date+vehicle (different customers/depots) who selected one row submitted/deleted **all** of them. **Fixed:** added `DEPOT` + `KUNNR` to the item key end-to-end — `ty_item`, both re-SELECT WHERE clauses, the deep `metadata.xml` item-type keys, the UI submit/delete payloads, and the `GETINDENT` projection + MPC (which now expose `DEPOT`; `KUNNR` was already a key). INDENT_DATE/TIME were **not** added: H5's duplicate guard already makes begda+vehicle+depot unique among drafts, and DEPOT/KUNNR are string-safe (no Edm.DateTime round-trip risk). **Backend caveat:** the deep runtime MPC (not in this repo) must be regenerated so the gateway deserializes the new payload keys — see the batch note above.

### M5 — `ATF_FLUSH` → `ATF_FLASH` not mapped on submit  ✅ FIXED (Batch 5)
`submit_indents` relies on `MOVE-CORRESPONDING ls_ind TO ls_tbl`, but the staging field is `ATF_FLASH` while the indent field is `ATF_FLUSH` (WD out.txt 10000 maps them explicitly). ATF tankers landed in `ZSAUTOMATETT_TBL` with a blank flushing flag. **Fixed:** added `ls_tbl-atf_flash = ls_ind-atf_flush.` after the `MOVE-CORRESPONDING` in the volume-tanker (TBL) branch.

### M6 — Staging cleanup WHERE clauses diverge on delete  ✅ FIXED (Batch 5)
WD branches on status (out.txt 5446–5452 vs 5484–5490): status 4 → both TBL and LPG include `OR shnumber = ' '`; status 5 → both restricted to `ztt_status = '5'`. Port used one generic pair: TBL had `OR shnumber=' '` always, LPG never. Result: status-4 delete left LPG orphans; status-5 delete could over-delete blank-SHNUMBER TBL rows. **Fixed:** `delete_indents` now branches the cleanup on `ls_ind-ztt_status` — status 4 → both TBL and LPG use `( ztt_status = '4' OR shnumber = ' ' )`; status 5 → both use `ztt_status = '5'`, exactly as WD.

### M7 — Sales-contract mandatory check only inspects compartment 1  ✅ FIXED (Batch 4)
WD requires a contract if PWAX is in **prod1–prod6** (or SUL0/RPC0/CPC0 in prod1) (out.txt 6449–6455). Port (`:664–666`) tested only `prod_cmp1`, so PWAX in comps 2–6 escaped the mandatory-contract guard. **Fixed:** extended the condition to PWAX across `PROD_CMP1..6` and aligned the comp-1 special products to WD's 4-char match (`SUL0`/`RPC0`/`CPC0`, replacing the looser 3-char `SUL`/`RPC`/`CPC`).

### M8 — Flushing reason uneditable on Change screen  ✅ FIXED (Batch 6)
`ChangeIndentWithVehicleTab.view.xml` wires `change=".onFlushingSelectChange"` (`:87`) but the controller has no such method, and `changeFlushingReasonSelect` is hardcoded `enabled="false"` (`:90–97`). Server still requires `flush_reason` when `atf_flush='Y'` (`create_entity:628–634`) → an ATF indent that needs flushing can't be modified (unsatisfiable server error). **Fixed:** added `onFlushingSelectChange` + a `_syncFlushReasonEnabled(sKey)` helper — enables the reason Input when the flushing key is `Y`, else disables and clears it (in the control *and* `SelectedIndent>/FLUSH_REASON`). Keyed on the change view's `Y`/`N`/`''` domain values (NOT the main controller's `"YES"`). `_onObjectMatched` now calls the helper with the loaded `ATF_FLUSH` so an existing ATF-flush indent opens with the reason field already editable (the view's hardcoded `enabled="false"` only sets the initial state). Pure UI — no backend change.

### M9 — `HSD_END_USE` not round-tripped on modify  ✅ FIXED (Batch 6)
`GETINDENTSet` projection (`:490–519`) included `ms_end_use` but not `hsd_end_use`. The change view binds End Use to `${MS_END_USE} || ${HSD_END_USE}` (`:82–83`) → for an HSD indent the saved end-use showed blank and `onUpdateIndent` posted it empty → HSD end-use silently lost on modify. **Fixed:** added `hsd_end_use TYPE zsd_cust_indent-hsd_end_use` to the `ls_gi` projection struct (the existing `MOVE-CORRESPONDING <ind> TO ls_gi` now copies it — `<ind>` is `zsd_cust_indent`, which carries the field) and exposed it as `_p 'HSD_END_USE'` on the `GETINDENT` entity type in `ZCL_ZSDI_ODATA_CUST_PO_MPC_EXT`. **Backend note:** one new non-key property on `GETINDENT` — if this service's model is maintained in SEGW rather than by the hand-coded MPC_EXT `DEFINE`, add `HSD_END_USE` (Edm.String) to the GETINDENT entity in SEGW and regenerate + clear the metadata cache (per the gateway-stale-serializer procedure).

### M10 — Open-list depot scope diverges when a filter is applied  ✅ FIXED (Tier 2)
WD collapses to the **first** mapped depot (`READ … INDEX 1`) when `IND_TYPE` or `DEL_IND` is set (out.txt 597–646); otherwise all depots. Port `GETINDENTSet` always used all mapped depots. Multi-depot users applying a type/deletable filter saw rows WD would hide. **Business decision Q1 = (A) match WebDynpro.** **Fixed:** `get_user_scope` now also exports `ev_first_depot` — the depot of the raw (pre-sort) `zsd_cust_usr_map` INDEX 1 row, matching WD's un-`ORDER BY`'d `ZTABCUST` INDEX 1 (out.txt 561/595); the port's own `et_depot` is sorted so its INDEX 1 could not be reused. `GETINDENTSet` computes `lv_gifilter` (INDENT_TYPE or ZDELETE set) and, when true, keeps only rows where `depot = ev_first_depot`; when false it retains the all-mapped-depots membership check. Affects multi-depot users only.

### M11 — End-use depot-3100 exclusion dropped  ✅ FIXED (Tier 1)
WD excludes `NORM_OBLND`/`BRND_OBLND` end-uses when `ZDEPOT = '3100'` (out.txt 9265–9272). Port `GetEndUseSet` (`:428–429`) reads all texts with no depot condition → those two wrongly appear at depot 3100. **Fixed:** `GetEndUseSet` now derives the user's depot via `get_user_scope` (`CUST_USER_ID` filter, fallback `sy-uname`, first mapped depot — mirroring WD's `SELECT SINGLE DEPOT … WHERE cust_user_id = sy-uname`) and `CONTINUE`s past `domvalue_l = 'NORM_OBLND'/'BRND_OBLND'` in the `ZIND_END_USE` loop when that depot is `3100`.

### M12 — Contract-list secondary divergences  ✅ FIXED (Tier 1 VBFA/pstyv + Tier 2 gate/IN-EP)
Within `SalesContractSet`/`GetEndUseSet` (all out.txt 9085–9159): open-balance VBFA formula (`RQTY = ZMENG − SUM(RFMNG_FLO)`) not computed; `pstyv <> 'ZTAE'` exclusion dropped and a spurious `abgru = space` added (`:370`); `GWAX` prefix missing from the match list; the non-special-product `T178` KONDM `'IN'/'EP'` branch missing.
- **Fixed (Tier 1):** `pstyv <> 'ZTAE'` restored + spurious `abgru = space` removed (already done in Batch 2). The VBFA open-balance formula is now computed per contract in `SalesContractSet` — `SELECT SINGLE ZMENG ZIEME POSNR FROM VBAP` then `SELECT SUM( RFMNG_FLO ) FROM VBFA WHERE VBTYP_N = 'C'`, `RQTY = ZMENG − ΣRFMNG_FLO` (out.txt 9090–9100) — and surfaced in the contract `DESC` (`"<matnr> - Bal: <rqty> <uom>"`); the NVEH replacement path shows `BL_QTY1` (out.txt 9116). WD does **not** hide zero-balance contracts on the With-Vehicle path (no `RQTY <= 0` delete, unlike the No-Veh `ONACTIONNO_VEH_CONTRACT` at 8677), so membership is unchanged — balance is display-only.
- **Fixed (Tier 2 — business decision Q2 = (A) IN/EP still in use → full parity):** `SalesContractSet` now reads `PRODUCT2–5` and computes `lv_special` from the WD gate (out.txt 9049–9053) — `PWAX`/`GWAX` matched across compartments 1–5, `RPC0`/`CPC0`/`SUL0` on compartment 1. When `lv_special = abap_true` the contract path runs (as before); otherwise the else-branch selects `T178` KONDM `'IN'`/`'EP'` and returns them as the list entries (`text = desc = KONDM`), mirroring WD's `LOOP AT ZZT178 WHERE KONDM = 'IN' OR 'EP'` (out.txt 9139–9161). Gate + else ported together (coupled — the gate alone would blank non-special products).

### M13 — KL/KG UOM derived but dropped in UI  ✅ FIXED (Tier 1)
Backend derives `COMP.UOM` (`:1198–1204`, MPC `:79`) but `_loadCompartments` (`WithVehicleTab.controller.js:301–313`) never reads it → compartment qty shows unitless. WD displays capacity with its KL/KG suffix (out.txt 5874–5878). **Fixed:** `_loadCompartments` now sets each qty `Input`'s `description` to `oComp.UOM` (with `fieldWidth` 70% so the unit renders beside the value); `_resetCompartments` clears the `description`/`fieldWidth` so a stale unit can't survive a vehicle change. Pure UI — `UOM` was already on the `GETCompartmentNo` entity.

---

## LOW severity (fidelity / UX)

- **L1** Open-indent block message: DPC builds `dd . mm . yyyy` (spaced dots, `:208–210`) and the UI titles it "License Check Failed" instead of "Please check!" — an open-indent block reads as a licence error.
- **L2** Licence messages capped at 14 (`:229`, controller `:277`); WD loops all.
- **L3** ATF product `ATF01` not auto-defaulted/selected (WD pins it; port leaves blank — save still enforces it).
- **L4** Capacity check covers comps 1–8; WD only 1–5. Also port skips the check for a 0-capacity compartment where WD would flag it.
- **L5** `CUST_USER_ID` stamped from client payload (fallback `sy-uname`); WD always uses `SY-UNAME` (trust/consistency).
- **L6** Stored `QUAN_COMP` decimal text differs (`CEVA_CONVERT_FLOAT_TO_CHAR` 3-dp vs raw string) — numerically equivalent.
- **L7** Change view references handlers that don't exist (`onQuantityChange` throws on keystroke; `onDateChange`/`onVehicleValueHelp` inert); "Fill All" (master product/qty) dead on change screen.
- **L8** No vehicle-licence re-check on modify (consistent with save in the port; WD re-runs GET_VEHICLE).
- **L9** GSTN value-help display text is bare GSTIN vs WD's `GSTN+NAME` concat (saved value equivalent after 15-char truncation).
- **L10** Leading blank placeholder customer row (WD 2733) not reproduced.
- **L11** End-use dropdown sort order (WD sorts by IND_CATEGORY) not reproduced.

---

## Faithful mappings (verified correct — no action)

- Ship-to **KUNN2 expansion** in customer derivation and open-list scope (KNVV→KNVP `PARVW='WE'`/`VTWEG<>'11'`, special-KDGRP DI/RE/TG/OI/EX branch) — matches WD and the documented No-Veh pattern.
- GSTIN enablement (DI/EX), GSTN list source (`ZTRANS_GSTN`).
- **GET_VEHICLE**: open-indent block, `Z_CHECK_VEHICLE_LICENSE`, `Z_GET_COMP_CAPACITY` + OIGCC count, EN/QN enable rules, product category filter + `ZSD_CUST_NO_PRD` exclusion, ATF flushing enablement.
- **SAVE validations** (17-point checklist): ATF flush + reason, customer/user/vehicle mandatory, blank-SHNUMBER duplicate, per-compartment product, GSTN for DI/EX (with SPART 40/25/30 exemption), sales-contract VBAP−VBFA balance, SKO/MTO same-material, MS06/HSD06 date-gated end-use, ethanol HOSP stock check — all reproduced. *(Gaps are H1/H3/H5/M2/M7 above.)*
- **FlushreasonSet** + flushing-reason enablement; **GetEndUseSet** MS06/HSD06 KNVV+date activation (incl. the intentional 2028 HSD guard).
- **SUBMIT/DELETE**: status-4-only submit guard, volume/weight table routing (TTV/ATF/WOIL/TTVM → TBL else LPG), B2B licence + ethanol re-checks on submit, delete guards (status 4 always / status 5 only when `ZDELETE='Y'`).
- **MODIFY** re-runs the full server-side save validation via `create_entity` (update flag) — nothing slips through unchecked. *(Caveat: the old-row delete key is safe only because vehicle + loading date are non-editable on the change view.)*

---

## Suggested remediation order

1. **H1 + H2** together — restore the plan cap on both save and submit (H1 must fix M-linked column population first). This is the single most important gap.
2. **H3** — `SalesContractSet` filter rewrite (KUNNR/product/depot/NVEH).
3. **H4** — stop the Change screen clobbering saved quantities.
4. **H5, M2, M7** — dropped save validations (active-shipment duplicate, bulk-order balance, PWAX comp scope).
5. **M3–M6** — deep-service correctness (bulk restore, item key, ATF flag, staging WHERE).
6. **M8, M9** — Change-screen ATF flushing + HSD end-use round-trip.
7. **M1, M10, M11** — scope/exclusion parity (confirm M10 with business).
8. **M12, M13** and the L-series as polish.
