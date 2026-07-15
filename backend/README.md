# Customer Indent Portal OData services (ABAP)

Backend implementation for the Customer Indent Portal, ported from the WebDynpro
`INDMAIN` component (component controller + view methods).

> Scope: **With Vehicle** and **Without Vehicle** tabs. The Inbound tab is not covered here.

These are plain `.abap` source files meant to be pasted into ADT / SE24 (or recreated
through SEGW). They are not auto-deployed — see *Wiring* below.

---

## Files

| File | Object | Role |
|------|--------|------|
| `ZCL_ZSDI_ODATA_CUST_PO_MPC_EXT.abap` | MPC extension class | Declares the With-Vehicle entity types & sets (model) |
| `ZCL_ZSDI_ODATA_CUST_PO_DPC_EXT.abap` | DPC extension class | Runtime: all `GET_ENTITYSET` reads + `SaveIndentSet` create |
| `ZCL_ZSD_CUST_PORTAL_DE_DPC_EXT.abap` | DPC extension class (deep service) | `CREATE_DEEP_ENTITY` for `ZCREATESet` (submit) / `ZDELETESet` (delete) |
| `ZCL_ZSD_CUST_IND_NOVEH_MPC_EXT.abap` | MPC extension class (no-vehicle service) | Declares the Without-Vehicle entity types & sets (model) |
| `ZCL_ZSD_CUST_IND_NOVEH_DPC_EXT.abap` | DPC extension class (no-vehicle service) | Runtime: value-help + open-indents reads, place (`CREATE`), delete (`DELETE`), short-close (`UPDATE`) |

The frontend uses **three** Gateway services (see `webapp/manifest.json`):

- `ZSDI_ODATA_CUST_PORTAL_01_SRV` — main service (reads + save) → main MPC/DPC
- `ZSD_CUST_PORTAL_DEEPENTITY_SRV` — deep entity service (submit/delete) → deep DPC
- `ZSD_CUST_IND_NOVEH_SRV` — Without-Vehicle service (value help + place/delete/close) → no-vehicle MPC/DPC

---

## Entity set → WebDynpro source map

| Entity set | Op | WebDynpro origin |
|------------|----|------------------|
| `VehicleSet` | GET_ENTITYSET | vehicle value help (OIGV) |
| `ZUSERSet` | GET_ENTITYSET | `WDDOINIT` customer derivation (ZSD_CUST_USR_MAP → KNVV/KNVP → KNA1) + `ONACTIONACTIVATE_GSTN` (DI/EX → GSTIN enable) |
| `CheckLicenseSet` | GET_ENTITYSET | `ONACTIONGET_VEHICLE`: open-indent check + `Z_CHECK_VEHICLE_LICENSE` |
| `GETCompartmentNoSet` | GET_ENTITYSET | `ONACTIONGET_VEHICLE`: `Z_GET_COMP_CAPACITY` + OIGCC count + EN/QN enable rules + veh-type |
| `GETProductSet` | GET_ENTITYSET | `ONACTIONGET_VEHICLE`: product drop-down (ZSD_INDENT_PROD by category, minus ZSD_CUST_NO_PRD) |
| `SalesContractSet` | GET_ENTITYSET | `ONACTIONSELECT_EXPORT` contract list (VBAK/VBPA/VBAP, open balance) |
| `GSTNSet` | GET_ENTITYSET | `ONACTIONACTIVATE_GSTN` GSTN list (ZTRANS_GSTN) |
| `GetEndUseSet` | GET_ENTITYSET | `ONACTIONSELECT_EXPORT` / `ONACTIONSELECT_IND_END_USE` (DD07T `ZIND_END_USE`, MS-/HSD- activation) |
| `FlushreasonSet` | GET_ENTITYSET | `ONACTIONFLUSHING_REASON` (DD07T `ZATF_FLUSH_REASON`) |
| `GETINDENTSet` | GET_ENTITYSET | `EXECUTE_Z_GET_CUSTOMER_INDENT` (`Z_GET_CUSTOMER_INDENT` + depot/partner filter) |
| `SaveIndentSet` | CREATE_ENTITY | `ONACTIONSAVE_INDENT` (full validation chain + INSERT ZSD_CUST_INDENT) |
| `ZCREATESet` | CREATE_DEEP_ENTITY | `ONACTIONSUBMIT_INDENT` (status 4 → 5, ZSAUTOMATETT_TBL/_LPG) |
| `ZDELETESet` | CREATE_DEEP_ENTITY | `ONACTIONDELETE_INDENT` / `ONACTIONREACT_TO_YES` (delete unprocessed) |

### Without-Vehicle service (`ZSD_CUST_IND_NOVEH_SRV`)

| Entity set | Op | WebDynpro origin |
|------------|----|------------------|
| `GetCustomerSet` | GET_ENTITYSET | customer value help (ZSD_CUST_USR_MAP → KNA1) |
| `MaterialSet` | GET_ENTITYSET | `SELECT_MAT_AND_GSTN` — customer material(s) + `ACTIVE1/ACTIVE2` enable flags |
| `GetOrderIdSet` | GET_ENTITYSET | `SELECT_CONTRACT_NVEH` — sales-contract value help (customer + material) |
| `GetTransGSTINSet` | GET_ENTITYSET | `ACTIVATE_GSTN` GSTN list (ZTRANS_GSTN) |
| `GetOpenIndentsSet` | GET_ENTITYSET | open indents for the customer (ZSD_INDENT_NVEH + contract balance) |
| `GetOpenIndentsSet` | CREATE_ENTITY | `SAVE_NOV_VEH_INDENT` (validate + INSERT ZSD_INDENT_NVEH, returns `ORDER_NO`) |
| `GetOpenIndentsSet` | DELETE_ENTITY | `REACT_TO_DEL_ORDER` (delete an open row) |
| `GetOpenIndentsSet` | UPDATE_ENTITY | `REACT_TO_CLOSE_ORDER` (short-close: DDIC `ORD_CLOSED = 'X'`) |

---

## Dependencies (must already exist on the system)

**Z tables**: `ZSD_CUST_INDENT`, `ZSD_CUST_USR_MAP`, `ZSD_INDENT_PROD`, `ZSD_CUST_NO_PRD`,
`ZPROD_GRP_INDENT`, `ZTRANS_GSTN`, `ZSET_MAT_VALTYPE`, `ZDESP_STOCK_PLNT`, `ZSAUTOMATETT_TBL`,
`ZSAUTOMATETT_LPG`, `ZEBMS_SRS`, `ZEBMS_MAT_MAP`, `ZSD_INDENT_NVEH`.

**Standard tables**: `OIGCC`, `OIGV`, `OIGS`, `OIGSI`, `KNVV`, `KNVP`, `KNA1`, `MARA`,
`VBAK`, `VBAP`, `VBPA`, `VBFA`, `DD07L`, `DD07T`, `T178`, `T001L`.

**Function modules (reused as the WebDynpro did — not re-implemented here)**:
`Z_GET_COMP_CAPACITY`, `Z_CHECK_VEHICLE_LICENSE`, `Z_GET_CUSTOMER_INDENT`,
`Z_ETHANOL_INDENT_STK_CHECK`, `CEVA_CONVERT_FLOAT_TO_CHAR`, `MOVE_CHAR_TO_NUM`,
`NUMERIC_CHECK`.

---

## Wiring (SEGW / ADT)

1. Create / reuse the SEGW project that generates base classes
   `ZCL_ZSDI_ODATA_CUST_PO_MPC` / `_DPC` and register service
   `ZSDI_ODATA_CUST_PORTAL_01_SRV`. Do the same for the deep service
   (`ZSD_CUST_PORTAL_DEEPENTITY_SRV`).
2. Define the entity types/sets in the data model so the generated `_MPC`/metadata match
   the matching file under `webapp/localService/` (`mainService/` for With-Vehicle,
   `withoutvehService/` for Without-Vehicle). If you keep the existing (correct)
   model, you can skip the supplied `_MPC_EXT` and only replace the DPC.
3. Paste each `_EXT` class body into the corresponding generated `*_EXT` class
   (`DEFINE` in MPC_EXT; the redefined runtime methods in DPC_EXT).
4. Activate, then `/IWFND/MAINT_SERVICE` → clear cache / re-register.
5. For the Without-Vehicle service, create number-range object `ZNVEHORD` (interval `01`)
   for `ORDER_NO`. If it is absent the DPC falls back to `MAX(ORDER_NO)+1`.

---

## Assumptions / notes

- Where the WebDynpro called a function module, the DPC calls the **same FM** — this keeps
  fidelity and avoids re-implementing logic that lives inside those FMs.
- `SaveIndentSet` returns soft validation text in the entity's **`ERROR`** field *and* raises
  a business exception for hard failures, so the UI5 `MessageBox` shows the message either way.
- Customer key (`KUNNR`) is normalised to 10 chars with `CONVERSION_EXIT_ALPHA_INPUT`.
- Quantities are stored exactly as the WebDynpro did: numeric value + UOM suffix (`KL`/`KG`)
  derived from vehicle type.
- The qty-vs-plan check ports `EXECUTE_Z_INDENT_QTY_CHECK` against `ZPROD_GRP_INDENT`.
- Class/service names follow the existing manifest data sources; rename consistently if your
  system uses different identifiers.
- **`ZSD_INDENT_NVEH` (Without-Vehicle storage) — OData ↔ DDIC field mapping.** The OData
  contract exposes `ROW_TYPE` and `WERKS`, which the DPC aliases onto the real DDIC columns
  `ORD_CLOSED` and `DEPOT`. Open row ⇔ `ORD_CLOSED = space`; short-closed ⇔ `ORD_CLOSED = 'X'`
  (read maps it back to `ROW_TYPE` `'O'`/`'C'`). `CREATE` also stamps `INDENT_DATE = sy-datum`,
  `INDENT_TIME = sy-uzeit`, `VEHICLE = space`, `KUNNR_DESC`, `UOM1`/`UOM2` (from `VBAP-VRKME`
  of the contract items) and, for a two-material indent, `CONTRACT2 = CONTRACT1`. `BL_QTY1/2`
  are persisted columns but the open-indents read recomputes them live from the contract
  balance. Actual DDIC fields: `MANDT ORDER_NO BEGDA VEHICLE DEPOT INDENT_DATE INDENT_TIME
  CUST_USER_ID KUNNR KUNNR_DESC MATNR1 QUANTITY1 UOM1 MATNR2 QUANTITY2 UOM2 CONTRACT1
  CONTRACT2 CHK TPT_GSTN ERROR BL_QTY1 BL_QTY2 ORD_CLOSED`. The derived OData properties
  `NAME1/DATE_FROM/ORDER_ID/TRANS_GSTID/TRANS_TEXT` are not stored.
