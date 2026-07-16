*&---------------------------------------------------------------------*
*&  ZCL_ZSD_CUST_IND_NOVEH_DPC_EXT
*&  Data provider (extension) - "Without Vehicle" tab.
*&
*&  Service: ZSD_CUST_IND_NOVEH_SRV  (manifest model: withoutvehModel)
*&  Ported from WebDynpro INDMAIN "Without Vehicle" tab methods
*&  (SELECT_MAT_AND_GSTN / SELECT_CONTRACT_NVEH / ACTIVATE_GSTN /
*&   SAVE_NOV_VEH_INDENT / REACT_TO_DEL_ORDER / REACT_TO_CLOSE_ORDER).
*&
*&  Storage table: ZSD_INDENT_NVEH  (same table the With-Vehicle DPC reads
*&  for contract-balance checks: ORDER_NO, CONTRACT1, ...).
*&
*&  Paste the redefined methods into the generated *_DPC_EXT class and add
*&  the private TYPES / METHODS to its class definition.
*&
*&  ZSD_INDENT_NVEH DDIC (actual): MANDT ORDER_NO BEGDA VEHICLE DEPOT
*&  INDENT_DATE INDENT_TIME CUST_USER_ID KUNNR KUNNR_DESC MATNR1 QUANTITY1
*&  UOM1 MATNR2 QUANTITY2 UOM2 CONTRACT1 CONTRACT2 CHK TPT_GSTN ERROR
*&  BL_QTY1 BL_QTY2 ORD_CLOSED.
*&  The OData contract exposes ROW_TYPE (open/closed flag) and WERKS
*&  (plant); these are ALIASED to the DDIC ORD_CLOSED and DEPOT columns
*&  respectively (see the explicit mapping in GET/UPDATE/DELETE below).
*&  ROW_TYPE 'C' <-> ORD_CLOSED = 'X'; open row <-> ORD_CLOSED = space.
*&  NAME1/DATE_FROM/ORDER_ID/TRANS_GSTID/TRANS_TEXT are derived, not stored.
*&---------------------------------------------------------------------*
CLASS zcl_zsd_cust_ind_noveh_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zsd_cust_ind_noveh_dpc
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS /iwbep/if_mgw_appl_srv_runtime~get_entityset REDEFINITION.
    METHODS /iwbep/if_mgw_appl_srv_runtime~create_entity REDEFINITION.
    METHODS /iwbep/if_mgw_appl_srv_runtime~update_entity REDEFINITION.
    METHODS /iwbep/if_mgw_appl_srv_runtime~delete_entity REDEFINITION.

  PRIVATE SECTION.

    "---- line types (match webapp/localService/withoutvehService) -----
    TYPES: BEGIN OF ty_customer,
             kunnr        TYPE kunnr,
             kunnr_desc   TYPE name1_gp,
             eligible     TYPE char1,       " 'X' = at least one material configured (MaterialSet would return rows)
             mat_count    TYPE char3,       " how many materials the customer's group has (WD dropdown size)
             cust_user_id TYPE xubname,
             smtp_addr    TYPE ad_smtpadr,
           END OF ty_customer.
    TYPES tt_customer TYPE STANDARD TABLE OF ty_customer WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_gstin,
             tpt_gstn     TYPE char100,
             name         TYPE char100,
             cust_user_id TYPE xubname,
             smtp_addr    TYPE ad_smtpadr,
           END OF ty_gstin.
    TYPES tt_gstin TYPE STANDARD TABLE OF ty_gstin WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_orderid,
             order_no     TYPE vbeln,
             kunnr        TYPE kunnr,
             matnr1       TYPE char40,
             matnr2       TYPE char40,
             vsbed        TYPE char20,
             " ---- display-only contract details (GetOrderIdSet) ---------
             " Product name (MAKT-MAKTX), contract ordered qty (VBAP-ZMENG),
             " remaining available (get_contract_available - already computed
             " to drop zero-balance contracts) and the contract UOM
             " (VBAP-ZIEME). All in the contract's NATIVE UOM - CON_UOM1
             " disambiguates the two qty figures.
             matnr1_desc  TYPE makt-maktx,
             con_ord_qty1 TYPE char17,
             con_avl_qty1 TYPE char17,
             con_uom1     TYPE vbap-zieme,
             cust_user_id TYPE xubname,
             smtp_addr    TYPE ad_smtpadr,
           END OF ty_orderid.
    TYPES tt_orderid TYPE STANDARD TABLE OF ty_orderid WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_material,
             kunnr        TYPE kunnr,
             matnr        TYPE char40,      " one material per row (ZSD_INDT_NO_VEH-MATNR)
             matdesc      TYPE char100,     " ZSD_INDT_NO_VEH-DESCRIPTION
             active1      TYPE char1,       " material-1 slot enabled for the group (all 5 groups)
             active2      TYPE char1,       " material-2 slot enabled for the group (OI/TG/ON only)
             cust_user_id TYPE xubname,
             smtp_addr    TYPE ad_smtpadr,
           END OF ty_material.
    TYPES tt_material TYPE STANDARD TABLE OF ty_material WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_open,
             kunnr        TYPE kunnr,
             name1        TYPE name1_gp,
             date_from    TYPE char10,
             werks        TYPE werks_d,
             trans_gstid  TYPE char40,
             trans_text   TYPE char80,
             order_id     TYPE char10,
             order_no     TYPE vbeln,
             begda        TYPE char10,
             kunnr_desc   TYPE name1_gp,
             matnr1       TYPE char40,
             quantity1    TYPE char17,
             matnr2       TYPE char40,
             quantity2    TYPE char17,
             contract1    TYPE vbeln,
             bl_qty1      TYPE char17,
             bl_qty2      TYPE char17,
             tpt_gstn     TYPE char100,
             error        TYPE char200,
             row_type     TYPE char1,
             cust_user_id TYPE xubname,
             smtp_addr    TYPE ad_smtpadr,
           END OF ty_open.
    TYPES tt_open TYPE STANDARD TABLE OF ty_open WITH DEFAULT KEY.

    "---- helpers (same contract as the With-Vehicle DPC) --------------
    METHODS get_filter_value
      IMPORTING io_request      TYPE REF TO /iwbep/if_mgw_req_entityset
                iv_property     TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS get_user_scope
      IMPORTING iv_uname TYPE xubname
      EXPORTING et_kunnr TYPE STANDARD TABLE            " raw mapped (sold-to) customers
                et_depot TYPE STANDARD TABLE.           " depots

    " Customer scope for the "Without Vehicle" tab - the single identity
    " space used by the dropdown, the save target and the open-indents
    " filter. Faithful port of the WebDynpro INDMAIN value-help build
    " (.vscode/docs/out.txt:561-592): seed the SOLD-TO parties from
    " ZSD_CUST_USR_MAP -> KNVV customer-group expansion (SPART<>'11',
    " skipping restricted groups DI/RE/TG/OI/EX) -> KNVP ship-to partners
    " (PARVW='WE', VTWEG<>'11') -> distinct KUNN2. Returned rows carry
    " KUNNR=KUNN2 and its KNA1-NAME1.
    METHODS get_scope_customers
      IMPORTING iv_uname       TYPE xubname
      RETURNING VALUE(rt_cust) TYPE tt_customer.

    METHODS raise_busi
      IMPORTING iv_msg TYPE string
      RAISING   /iwbep/cx_mgw_busi_exception.

    " Materials the customer may indent without a vehicle (WebDynpro
    " ONACTIONSELECT_MAT_AND_GSTN, out.txt:9549-9615). The customer's KNVV
    " group is normalized into (DI,EX,OI,TG,ON); the eligible materials are
    " ZSD_INDT_NO_VEH rows for that group. Each returned row carries the group
    " enable-flags ACTIVE1 (all 5 groups) and ACTIVE2 (OI/TG/ON only) so the
    " UI can show one or two material dropdowns from the same list.
    METHODS get_customer_material
      IMPORTING iv_kunnr      TYPE kunnr
      RETURNING VALUE(rt_mat) TYPE tt_material.

    " Normalize a customer's KNVV sales-area group into the eligible-group
    " space (DI,EX,OI,TG,ON), DETERMINISTICALLY: among the customer's eligible
    " groups (ORDER BY kdgrp) prefer one that has materials in ZSD_INDT_NO_VEH,
    " else the first eligible group. Single source of truth shared by
    " get_customer_material and the GetCustomerSet eligibility flag so the
    " dropdown-eligibility and the "No material" toast can never disagree - this
    " only holds because the resolution is stable across calls (see IMPLEMENTATION).
    METHODS resolve_cust_group
      IMPORTING iv_kunnr        TYPE kunnr
      RETURNING VALUE(rv_kdgrp) TYPE knvv-kdgrp.

    " Remaining available quantity on a sales contract for a material
    " (WD SELECT_CONTRACT_NVEH, out.txt:8619-8675 / WD SAVE, out.txt:8206-8275).
    " = contract ordered (VBAP-ZMENG) - delivered (VBFA vbtyp 'C')
    "   - open commitments (SUM BL_QTY1 of open indents on the contract
    "     + SUM QUANTITY1 of their not-yet-shipped ZINDT_NVEH_ITEM rows).
    " Commitments are scaled x1000 when the contract UOM (VBAP-ZIEME) is 'KG',
    " exactly as the WebDynpro does. Returns <= 0 when nothing is available
    " (or the contract/material pair does not exist). Single source of truth
    " for both the GetOrderIdSet availability filter and the create_entity
    " sufficiency check.
    TYPES ty_qty TYPE p LENGTH 15 DECIMALS 3.
    METHODS get_contract_available
      IMPORTING iv_vbeln       TYPE vbeln
                iv_matnr       TYPE matnr
      RETURNING VALUE(rv_rqty) TYPE ty_qty.

ENDCLASS.



CLASS zcl_zsd_cust_ind_noveh_dpc_ext IMPLEMENTATION.

  "===================================================================
  "  GET_ENTITYSET  (dispatch)
  "===================================================================
  METHOD /iwbep/if_mgw_appl_srv_runtime~get_entityset.

    DATA lv_uname TYPE xubname.
    lv_uname = get_filter_value( io_request = io_tech_request_context iv_property = 'CUST_USER_ID' ).
    IF lv_uname IS INITIAL. lv_uname = sy-uname. ENDIF.

    CASE iv_entity_set_name.

      "----------------------------------------------- GetCustomerSet -
      WHEN 'GetCustomerSet'.
        DATA lt_cust TYPE tt_customer.
        " expanded ship-to customers (WebDynpro INDMAIN value-help)
        lt_cust = get_scope_customers( lv_uname ).
        SORT lt_cust BY kunnr.
        DELETE ADJACENT DUPLICATES FROM lt_cust COMPARING kunnr.

        " Eligibility flag: mirror MaterialSet exactly so the dropdown never
        " lands on a customer that then raises "No material configured". A
        " customer is eligible iff ZSD_INDT_NO_VEH has >=1 row for the group
        " resolve_cust_group() maps its KNVV entry to. Group counts are read
        " once (not per customer) and matched in memory.
        SELECT cust_group, COUNT(*) AS cnt
          FROM zsd_indt_no_veh
          INTO TABLE @DATA(lt_grpcnt)                                   "#EC CI_NOWHERE
          GROUP BY cust_group.
        LOOP AT lt_cust ASSIGNING FIELD-SYMBOL(<c>).
          DATA(lv_grp) = resolve_cust_group( <c>-kunnr ).
          READ TABLE lt_grpcnt INTO DATA(ls_gc) WITH KEY cust_group = lv_grp.
          IF sy-subrc = 0 AND ls_gc-cnt > 0.
            <c>-eligible  = 'X'.
            DATA lv_cnt TYPE i.
            lv_cnt        = ls_gc-cnt.
            <c>-mat_count = lv_cnt.
            CONDENSE <c>-mat_count.
          ENDIF.
        ENDLOOP.

        " Segregate valid customers from invalid ones: eligible = 'X' sorts
        " above space, so DESCENDING floats the valid (material-configured)
        " customers to the top; KUNNR keeps a stable order within each block.
        SORT lt_cust BY eligible DESCENDING kunnr ASCENDING.

        copy_data_to_ref( EXPORTING is_data = lt_cust CHANGING cr_data = er_entityset ).

      "---------------------------------------------- GetTransGSTINSet -
      WHEN 'GetTransGSTINSet'.
        DATA lt_gstn TYPE tt_gstin.
        SELECT gstn AS tpt_gstn, name AS name FROM ztrans_gstn
          INTO CORRESPONDING FIELDS OF TABLE @lt_gstn.                  "#EC CI_NOWHERE
        LOOP AT lt_gstn ASSIGNING FIELD-SYMBOL(<g>).
          <g>-cust_user_id = lv_uname.
        ENDLOOP.
        SORT lt_gstn BY tpt_gstn.
        DELETE ADJACENT DUPLICATES FROM lt_gstn COMPARING tpt_gstn.
        copy_data_to_ref( EXPORTING is_data = lt_gstn CHANGING cr_data = er_entityset ).

      "------------------------------------------------- GetOrderIdSet -
      WHEN 'GetOrderIdSet'.
        DATA lt_ord TYPE tt_orderid.
        DATA: lv_okun     TYPE kunnr,
              lv_omat     TYPE matnr,
              lv_oavl     TYPE ty_qty,
              lv_ord_disp TYPE ty_qty,
              lv_avl_disp TYPE ty_qty.
        lv_okun = get_filter_value( io_request = io_tech_request_context iv_property = 'KUNNR' ).
        lv_omat = get_filter_value( io_request = io_tech_request_context iv_property = 'MATNR1' ).
        IF lv_okun IS NOT INITIAL.
          CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
            EXPORTING input = lv_okun IMPORTING output = lv_okun.
        ENDIF.
        " MATNR1 is a real (short) material code drawn from ZSD_INDT_NO_VEH and
        " matched EXACTLY against VBAP-MATNR (WD out.txt:8606) - no alpha conv,
        " no prefix LIKE. Without a material there is nothing to match.
        IF lv_omat IS INITIAL.
          copy_data_to_ref( EXPORTING is_data = lt_ord CHANGING cr_data = er_entityset ).
          RETURN.
        ENDIF.

        " depot of the logged-in portal user (WD out.txt:8526 - ZSD_CUST_USR_MAP)
        DATA lv_odep TYPE werks_d.
        SELECT SINGLE depot FROM zsd_cust_usr_map INTO @lv_odep         "#EC CI_NOORDER
          WHERE cust_user_id = @lv_uname.

        " candidate contracts (WD SELECT_CONTRACT_NVEH, out.txt:8598-8608):
        " valid today, ship-to = customer, exact material, OWN-BOND valuation
        " at the user's depot, real item category (<> ZTAE), not rejected.
        SELECT v~vbeln, a~matnr, v~vsbed, a~zmeng, a~zieme
          FROM vbak AS v
          INNER JOIN vbpa AS p ON p~vbeln = v~vbeln
          INNER JOIN vbap AS a ON a~vbeln = v~vbeln
          INTO TABLE @DATA(lt_vb)
          WHERE v~guebg <= @sy-datum AND v~gueen >= @sy-datum
            AND p~kunnr = @lv_okun AND p~parvw = 'WE'
            AND a~matnr = @lv_omat
            AND a~bwtar = 'OWN-BOND'
            AND a~werks = @lv_odep
            AND a~pstyv <> 'ZTAE'
            AND a~abgru = @space.                                       "#EC CI_BUFFJOIN
        SORT lt_vb BY vbeln.
        DELETE ADJACENT DUPLICATES FROM lt_vb COMPARING vbeln.

        LOOP AT lt_vb INTO DATA(ls_vb).
          " drop contracts with no remaining balance (WD out.txt:8677 RQTY <= 0);
          " keep the figure - it is the availability shown in the value help
          lv_oavl = get_contract_available( iv_vbeln = ls_vb-vbeln iv_matnr = ls_vb-matnr ).
          IF lv_oavl <= 0.
            CONTINUE.
          ENDIF.
          DATA ls_ord TYPE ty_orderid.
          CLEAR ls_ord.
          ls_ord-order_no     = ls_vb-vbeln.
          ls_ord-kunnr        = lv_okun.
          ls_ord-matnr1       = ls_vb-matnr.
          ls_ord-vsbed        = ls_vb-vsbed.
          " contract details: ordered qty (VBAP-ZMENG) and available balance
          " are both in the contract's native UOM. The customer enters the
          " indent quantity in MT, so show these in MT too - a KG contract is
          " 1 MT = 1000 KG (the same x1000 bridge the SAVE check uses). Non-KG
          " contracts are displayed in their native UOM unchanged.
          lv_ord_disp = ls_vb-zmeng.
          lv_avl_disp = lv_oavl.
          IF ls_vb-zieme = 'KG'.
            lv_ord_disp     = lv_ord_disp / 1000.
            lv_avl_disp     = lv_avl_disp / 1000.
            ls_ord-con_uom1 = 'MT'.
          ELSE.
            ls_ord-con_uom1 = ls_vb-zieme.
          ENDIF.
          ls_ord-con_ord_qty1 = lv_ord_disp.
          CONDENSE ls_ord-con_ord_qty1.
          ls_ord-con_avl_qty1 = lv_avl_disp.
          CONDENSE ls_ord-con_avl_qty1.
          " product name for the contract material
          SELECT SINGLE maktx FROM makt INTO ls_ord-matnr1_desc          "#EC CI_NOORDER
            WHERE matnr = @ls_vb-matnr AND spras = @sy-langu.
          ls_ord-cust_user_id = lv_uname.
          APPEND ls_ord TO lt_ord.
        ENDLOOP.
        SORT lt_ord BY order_no.
        copy_data_to_ref( EXPORTING is_data = lt_ord CHANGING cr_data = er_entityset ).

      "-------------------------------------------------- MaterialSet -
      " One row per eligible material for the customer's group (WD dropdown
      " list). ACTIVE1/ACTIVE2 on each row tell the UI whether the material-1
      " and material-2 slots are enabled for this group.
      WHEN 'MaterialSet'.
        DATA lt_mat TYPE tt_material.
        DATA lv_mkun TYPE kunnr.
        lv_mkun = get_filter_value( io_request = io_tech_request_context iv_property = 'KUNNR' ).
        IF lv_mkun IS NOT INITIAL.
          CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
            EXPORTING input = lv_mkun IMPORTING output = lv_mkun.
        ENDIF.
        lt_mat = get_customer_material( lv_mkun ).
        LOOP AT lt_mat ASSIGNING FIELD-SYMBOL(<m>).
          <m>-cust_user_id = lv_uname.
        ENDLOOP.
        SORT lt_mat BY matnr.
        copy_data_to_ref( EXPORTING is_data = lt_mat CHANGING cr_data = er_entityset ).

      "-------------------------------------------- GetOpenIndentsSet -
      WHEN 'GetOpenIndentsSet'.
        DATA lt_open TYPE tt_open.
        DATA lv_ikun TYPE kunnr.
        lv_ikun = get_filter_value( io_request = io_tech_request_context iv_property = 'KUNNR' ).
        IF lv_ikun IS NOT INITIAL.
          CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
            EXPORTING input = lv_ikun IMPORTING output = lv_ikun.
        ENDIF.

        " restrict to the user's expanded ship-to scope (KUNN2 space -
        " the same set the dropdown is built from). The frontend always sends
        " KUNNR (onGetOpenIndents guards "Please select a Customer" and returns
        " before calling - WithOutVehTab.controller.js:262), so the no-filter
        " branch below is defensive-only and never exercised in practice.
        DATA(lt_iscope) = get_scope_customers( lv_uname ).
        IF lv_ikun IS INITIAL.
          READ TABLE lt_iscope INTO DATA(ls_iscope) INDEX 1.
          lv_ikun = ls_iscope-kunnr.
        ELSE.
          READ TABLE lt_iscope TRANSPORTING NO FIELDS WITH KEY kunnr = lv_ikun.
          IF sy-subrc <> 0.
            " customer not in the user's scope -> empty result
            copy_data_to_ref( EXPORTING is_data = lt_open CHANGING cr_data = er_entityset ).
            RETURN.
          ENDIF.
        ENDIF.

        " open rows only (deleted rows are physically removed; short-close sets ORD_CLOSED)
        SELECT * FROM zsd_indent_nveh INTO TABLE @DATA(lt_nveh)
          WHERE kunnr = @lv_ikun
            AND ord_closed = @space.                                    "#EC CI_NOORDER
        LOOP AT lt_nveh ASSIGNING FIELD-SYMBOL(<n>).
          DATA ls_open TYPE ty_open.
          CLEAR ls_open.
          MOVE-CORRESPONDING <n> TO ls_open.       " KUNNR/BEGDA/MATNR1/2/QUANTITY1/2/CONTRACT1/TPT_GSTN/KUNNR_DESC/ERROR
          " OData aliases over the DDIC columns
          ls_open-werks    = <n>-depot.
          ls_open-row_type = COND #( WHEN <n>-ord_closed IS NOT INITIAL THEN 'C' ELSE 'O' ).
          SELECT SINGLE name1 FROM kna1 INTO ls_open-kunnr_desc WHERE kunnr = <n>-kunnr.
          ls_open-name1 = ls_open-kunnr_desc.
          " balance quantities are the STORED BL_QTY1/2 (WD parity): seeded at
          " SAVE (= ordered qty) and decremented as liftings occur. Already
          " carried in by MOVE-CORRESPONDING above - do NOT live-recompute here.
          " WD displays the stored value, and the delete guard compares
          " QUANTITY vs this same stored BL_QTY, so the two must stay identical.
          ls_open-cust_user_id = lv_uname.
          APPEND ls_open TO lt_open.
        ENDLOOP.
        SORT lt_open BY order_no DESCENDING.
        copy_data_to_ref( EXPORTING is_data = lt_open CHANGING cr_data = er_entityset ).

      WHEN OTHERS.
        super->/iwbep/if_mgw_appl_srv_runtime~get_entityset(
          EXPORTING iv_entity_name           = iv_entity_name
                    iv_entity_set_name        = iv_entity_set_name
                    iv_source_name            = iv_source_name
                    it_filter_select_options  = it_filter_select_options
                    it_order                  = it_order
                    is_paging                 = is_paging
                    it_navigation_path        = it_navigation_path
                    it_key_tab                = it_key_tab
                    iv_filter_string          = iv_filter_string
                    iv_search_string          = iv_search_string
                    io_tech_request_context   = io_tech_request_context
          IMPORTING er_entityset              = er_entityset
                    es_response_context       = es_response_context ).
    ENDCASE.

  ENDMETHOD.


  "===================================================================
  "  CREATE_ENTITY  (GetOpenIndentsSet)  - SAVE_NOV_VEH_INDENT
  "===================================================================
  METHOD /iwbep/if_mgw_appl_srv_runtime~create_entity.

    IF iv_entity_set_name <> 'GetOpenIndentsSet'.
      super->/iwbep/if_mgw_appl_srv_runtime~create_entity(
        EXPORTING iv_entity_name = iv_entity_name iv_entity_set_name = iv_entity_set_name
                  iv_source_name = iv_source_name io_data_provider = io_data_provider
                  it_key_tab = it_key_tab it_navigation_path = it_navigation_path
        IMPORTING er_entity = er_entity ).
      RETURN.
    ENDIF.

    DATA: BEGIN OF ls_in,
            kunnr        TYPE kunnr,
            kunnr_desc   TYPE name1_gp,
            begda        TYPE char10,
            contract1    TYPE vbeln,
            matnr1       TYPE char40,
            quantity1    TYPE char17,
            matnr2       TYPE char40,
            quantity2    TYPE char17,
            tpt_gstn     TYPE char100,
            row_type     TYPE char1,
            order_no     TYPE vbeln,
            cust_user_id TYPE xubname,
            smtp_addr    TYPE ad_smtpadr,
          END OF ls_in.
    io_data_provider->read_entry_data( IMPORTING es_data = ls_in ).

    DATA lv_uname TYPE xubname.
    lv_uname = COND #( WHEN ls_in-cust_user_id IS NOT INITIAL THEN ls_in-cust_user_id ELSE sy-uname ).
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING input = ls_in-kunnr IMPORTING output = ls_in-kunnr.

    " ---------- validations (mirror the WebDynpro popups) -----------
    IF ls_in-begda IS INITIAL.
      raise_busi( 'Please select a Loading Date.' ).
    ENDIF.
    IF ls_in-kunnr IS INITIAL.
      raise_busi( 'Please select Customer.' ).
    ENDIF.
    IF ls_in-matnr1 IS INITIAL.
      raise_busi( 'No material is configured for this customer.' ).
    ENDIF.
    IF ls_in-quantity1 IS INITIAL.
      raise_busi( 'Please enter Quantity 1.' ).
    ENDIF.

    " customer must be within the user's expanded ship-to scope - the same
    " KUNN2 identity space the dropdown is built from (the WebDynpro stores
    " the selected KUNN2 as ZSD_INDENT_NVEH-KUNNR; out.txt:8285)
    DATA(lt_scope) = get_scope_customers( lv_uname ).
    READ TABLE lt_scope TRANSPORTING NO FIELDS WITH KEY kunnr = ls_in-kunnr.
    IF sy-subrc <> 0.
      raise_busi( 'Customer is not mapped to the logged-in user.' ).
    ENDIF.

    " ---------- transporter-GSTIN check (WD SAVE, out.txt:7924-7934) --
    " For divisions outside (40/25/30) sold to a DI/EX customer group, a
    " transporter GSTIN is mandatory on the indent.
    DATA: lv_kdgrp TYPE knvv-kdgrp,
          lv_spart TYPE mara-spart,
          lv_zchk  TYPE c LENGTH 1.
    SELECT SINGLE kdgrp FROM knvv INTO @lv_kdgrp WHERE kunnr = @ls_in-kunnr.  "#EC CI_NOORDER
    SELECT SINGLE spart FROM mara INTO @lv_spart WHERE matnr = @ls_in-matnr1. "#EC CI_NOORDER
    IF lv_spart <> '40' AND lv_spart <> '25' AND lv_spart <> '30'.
      lv_zchk = 'X'.
    ENDIF.
    IF ( lv_kdgrp = 'DI' OR lv_kdgrp = 'EX' ) AND ls_in-tpt_gstn IS INITIAL AND lv_zchk = 'X'.
      raise_busi( 'Please enter GSTN of Transporter' ).
    ENDIF.

    " ---------- contract balance sufficiency (WD SAVE, out.txt:8206-8275)
    " Only WAX/SUL/RPC/CPC lines are contract-controlled. Remaining balance =
    " contract ordered (VBAP-ZMENG) - delivered (VBFA) - open commitments
    " (SUM BL_QTY1 of open indents on the same contract + SUM QUANTITY1 of
    " their not-yet-shipped item rows). Commitments are scaled x1000 when the
    " contract UOM is KG; the requested quantity is compared x1000.
    IF ls_in-matnr1(4) = 'PWAX' OR ls_in-matnr2(4) = 'PWAX'
       OR ls_in-matnr1(4) = 'RPC0' OR ls_in-matnr1(4) = 'CPC0'
       OR ls_in-matnr1(4) = 'SUL0'.

      IF ls_in-contract1 IS INITIAL.
        raise_busi( 'Please select contract number' ).
      ENDIF.

      DATA: lv_zrqty TYPE ty_qty,
            lv_blqty TYPE ty_qty,
            lv_reqq  TYPE ty_qty.

      " remaining contract balance (shared with the GetOrderIdSet filter)
      lv_zrqty = get_contract_available( iv_vbeln = ls_in-contract1 iv_matnr = ls_in-matnr1 ).

      CALL FUNCTION 'MOVE_CHAR_TO_NUM' EXPORTING chr = ls_in-quantity1 IMPORTING num = lv_reqq.
      lv_blqty = lv_reqq * 1000.
      IF lv_zrqty < lv_blqty.
        lv_zrqty = lv_zrqty / 1000.
        IF lv_zrqty < 0.
          raise_busi( 'No quantity is available in contract' ).
        ELSE.
          DATA: lv_etxt TYPE char15,
                lv_bmsg TYPE string.
          lv_etxt = lv_zrqty.
          CONDENSE lv_etxt.
          CONCATENATE 'Maximum quantity available in contract is' lv_etxt 'MT'
            INTO lv_bmsg SEPARATED BY space.
          raise_busi( lv_bmsg ).
        ENDIF.
      ENDIF.
    ENDIF.

    " ---------- next order number (WD SAVE, out.txt:8298-8308) -------
    " Number range object ZINDNT_HDR, interval '01'. No MAX+1 fallback -
    " a misconfigured range must hard-fail rather than silently collide
    " with legacy order numbers.
    DATA lv_order TYPE numc10.
    CALL FUNCTION 'NUMBER_GET_NEXT'
      EXPORTING nr_range_nr = '01' object = 'ZINDNT_HDR'
      IMPORTING number      = lv_order
      EXCEPTIONS OTHERS     = 1.
    IF sy-subrc <> 0 OR lv_order IS INITIAL.
      raise_busi( 'Number range object ZINDNT_HDR is not configured. Contact administrator.' ).
    ENDIF.

    " ---------- build & insert the ZSD_INDENT_NVEH record -----------
    DATA ls_nveh TYPE zsd_indent_nveh.
    CLEAR ls_nveh.
    MOVE-CORRESPONDING ls_in TO ls_nveh.     " KUNNR/BEGDA/MATNR1/2/QUANTITY1/2/CONTRACT1/TPT_GSTN
    ls_nveh-order_no     = lv_order.
    ls_nveh-kunnr        = ls_in-kunnr.
    ls_nveh-cust_user_id = lv_uname.
    " opening balance = ordered quantity (WD SAVE, out.txt:8311-8312). This
    " seeds every downstream balance calc (contract availability above, the
    " open-indents display, and the delete guard which compares QTY vs BL_QTY).
    ls_nveh-bl_qty1      = ls_nveh-quantity1.
    ls_nveh-bl_qty2      = ls_nveh-quantity2.
    ls_nveh-ord_closed   = space.            " open (short-close later sets 'X')
    ls_nveh-vehicle      = space.            " no vehicle on this tab
    ls_nveh-indent_date  = sy-datum.
    ls_nveh-indent_time  = sy-uzeit.
    SELECT SINGLE name1 FROM kna1 INTO ls_nveh-kunnr_desc WHERE kunnr = ls_in-kunnr.
    SELECT SINGLE depot FROM zsd_cust_usr_map INTO ls_nveh-depot        "#EC CI_NOORDER
      WHERE cust_user_id = lv_uname.
    " NOTE: CONTRACT2 and UOM1/UOM2 are intentionally NOT populated. WD
    " SAVE_NOV_VEH_INDENT does not write them (they were earlier invented as
    " enrichment); left blank for exact parity with the legacy stored record.

    INSERT zsd_indent_nveh FROM ls_nveh.
    IF sy-subrc <> 0.
      raise_busi( 'Failed to save indent. Please try again.' ).
    ENDIF.

    " ---------- echo the created entity back to the UI --------------
    DATA ls_out TYPE ty_open.
    CLEAR ls_out.
    MOVE-CORRESPONDING ls_in TO ls_out.
    ls_out-order_no     = lv_order.
    ls_out-kunnr        = ls_in-kunnr.
    ls_out-cust_user_id = lv_uname.
    SELECT SINGLE name1 FROM kna1 INTO ls_out-kunnr_desc WHERE kunnr = ls_in-kunnr.
    copy_data_to_ref( EXPORTING is_data = ls_out CHANGING cr_data = er_entity ).

  ENDMETHOD.


  "===================================================================
  "  UPDATE_ENTITY  (GetOpenIndentsSet)  - REACT_TO_CLOSE_ORDER
  "  Short-close: ROW_TYPE = 'C'.
  "===================================================================
  METHOD /iwbep/if_mgw_appl_srv_runtime~update_entity.

    IF iv_entity_set_name <> 'GetOpenIndentsSet'.
      super->/iwbep/if_mgw_appl_srv_runtime~update_entity(
        EXPORTING iv_entity_name = iv_entity_name iv_entity_set_name = iv_entity_set_name
                  iv_source_name = iv_source_name io_data_provider = io_data_provider
                  it_key_tab = it_key_tab it_navigation_path = it_navigation_path
        IMPORTING er_entity = er_entity ).
      RETURN.
    ENDIF.

    DATA: BEGIN OF ls_in,
            kunnr    TYPE kunnr,
            order_no TYPE vbeln,
            row_type TYPE char1,
          END OF ls_in.
    io_data_provider->read_entry_data( IMPORTING es_data = ls_in ).

    " keys arrive in it_key_tab (KUNNR / ORDER_NO)
    DATA: lv_kunnr TYPE kunnr,
          lv_order TYPE vbeln.
    READ TABLE it_key_tab INTO DATA(ls_key) WITH KEY name = 'KUNNR'.
    IF sy-subrc = 0. lv_kunnr = ls_key-value. ENDIF.
    READ TABLE it_key_tab INTO ls_key WITH KEY name = 'ORDER_NO'.
    IF sy-subrc = 0. lv_order = ls_key-value. ENDIF.
    IF lv_kunnr IS INITIAL. lv_kunnr = ls_in-kunnr. ENDIF.
    IF lv_order IS INITIAL. lv_order = ls_in-order_no. ENDIF.
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING input = lv_kunnr IMPORTING output = lv_kunnr.

    " only open rows can be short-closed
    SELECT SINGLE * FROM zsd_indent_nveh INTO @DATA(ls_row)
      WHERE kunnr = @lv_kunnr AND order_no = @lv_order.                 "#EC CI_NOORDER
    IF sy-subrc <> 0.
      raise_busi( 'Order not found.' ).
    ENDIF.
    IF ls_row-ord_closed IS NOT INITIAL.
      raise_busi( 'Order is already closed.' ).
    ENDIF.

    UPDATE zsd_indent_nveh SET ord_closed = 'X'
      WHERE kunnr = lv_kunnr AND order_no = lv_order.
    IF sy-subrc <> 0.
      raise_busi( 'Failed to close the order.' ).
    ENDIF.

    " echo back
    DATA ls_out TYPE ty_open.
    CLEAR ls_out.
    MOVE-CORRESPONDING ls_row TO ls_out.
    ls_out-werks    = ls_row-depot.
    ls_out-row_type = 'C'.
    copy_data_to_ref( EXPORTING is_data = ls_out CHANGING cr_data = er_entity ).

  ENDMETHOD.


  "===================================================================
  "  DELETE_ENTITY  (GetOpenIndentsSet)  - REACT_TO_DEL_ORDER
  "===================================================================
  METHOD /iwbep/if_mgw_appl_srv_runtime~delete_entity.

    IF iv_entity_set_name <> 'GetOpenIndentsSet'.
      super->/iwbep/if_mgw_appl_srv_runtime~delete_entity(
        EXPORTING iv_entity_name = iv_entity_name iv_entity_set_name = iv_entity_set_name
                  iv_source_name = iv_source_name it_key_tab = it_key_tab
                  it_navigation_path = it_navigation_path ).
      RETURN.
    ENDIF.

    DATA: lv_kunnr TYPE kunnr,
          lv_order TYPE vbeln.
    READ TABLE it_key_tab INTO DATA(ls_key) WITH KEY name = 'KUNNR'.
    IF sy-subrc = 0. lv_kunnr = ls_key-value. ENDIF.
    READ TABLE it_key_tab INTO ls_key WITH KEY name = 'ORDER_NO'.
    IF sy-subrc = 0. lv_order = ls_key-value. ENDIF.
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING input = lv_kunnr IMPORTING output = lv_kunnr.

    " only open (not short-closed) rows can be deleted
    SELECT SINGLE * FROM zsd_indent_nveh INTO @DATA(ls_del)
      WHERE kunnr = @lv_kunnr AND order_no = @lv_order.                 "#EC CI_NOORDER
    IF sy-subrc <> 0.
      raise_busi( 'Order not found.' ).
    ENDIF.
    IF ls_del-ord_closed IS NOT INITIAL.
      raise_busi( 'Closed order cannot be deleted.' ).
    ENDIF.

    " WD REACT_TO_DEL_ORDER (out.txt:5204-5243): an indent may be deleted
    " ONLY while nothing has been lifted against it - the live balance still
    " equals the ordered quantity on BOTH lines. Once any quantity is drawn
    " (QUANTITY <> BL_QTY) the order is "processed" and locked from deletion.
    IF ls_del-quantity1 <> ls_del-bl_qty1 OR ls_del-quantity2 <> ls_del-bl_qty2.
      raise_busi( 'Selected order has been processed and cannot be deleted' ).
    ENDIF.

    DELETE FROM zsd_indent_nveh
      WHERE kunnr = lv_kunnr AND order_no = lv_order.
    IF sy-subrc <> 0.
      raise_busi( 'Failed to delete the order.' ).
    ENDIF.

  ENDMETHOD.


  "===================================================================
  "  HELPERS
  "===================================================================
  METHOD get_filter_value.
    " get_filter_select_options returns the full table of select options;
    " it takes no property parameter - pick the wanted property yourself.
    DATA ls_so TYPE /iwbep/s_mgw_select_option.
    DATA(lt_so) = io_request->get_filter( )->get_filter_select_options( ).
    READ TABLE lt_so INTO ls_so WITH KEY property = iv_property.
    IF sy-subrc = 0.
      READ TABLE ls_so-select_options INTO DATA(ls_range) INDEX 1.
      IF sy-subrc = 0.
        rv_value = ls_range-low.
      ENDIF.
    ENDIF.
  ENDMETHOD.

  METHOD get_user_scope.
    " ZSD_CUST_USR_MAP: logged-in portal user -> ship-to customer(s) + depot(s)
    DATA lt_map TYPE STANDARD TABLE OF zsd_cust_usr_map.
    SELECT * FROM zsd_cust_usr_map INTO TABLE lt_map                    "#EC CI_NOORDER
      WHERE cust_user_id = iv_uname.
    LOOP AT lt_map INTO DATA(ls_map).
      DATA lv_k TYPE kunnr.
      lv_k = ls_map-kunnr.
      APPEND lv_k TO et_kunnr.
      DATA lv_d TYPE werks_d.
      lv_d = ls_map-depot.
      APPEND lv_d TO et_depot.
    ENDLOOP.
    SORT et_kunnr. DELETE ADJACENT DUPLICATES FROM et_kunnr.
    SORT et_depot. DELETE ADJACENT DUPLICATES FROM et_depot.
  ENDMETHOD.

  METHOD get_scope_customers.
    " ---- WebDynpro INDMAIN customer value-help (out.txt:561-592) --------
    " ZSD_CUST_USR_MAP holds the SOLD-TO party (Phase 0-A confirmed). Each
    " seed is expanded to the ship-to customers the portal user may indent
    " for; the resulting distinct KUNN2 set is the identity space of the
    " whole tab (dropdown / save target / open-indents filter).
    DATA lt_map   TYPE STANDARD TABLE OF zsd_cust_usr_map.
    DATA lt_knvv  TYPE STANDARD TABLE OF knvv.
    DATA lt_knvp  TYPE STANDARD TABLE OF knvp.
    DATA lt_we    TYPE STANDARD TABLE OF knvp.       " accumulated WE partners (ZKNVP1)
    DATA lv_kdgrp TYPE knvv-kdgrp.

    SELECT * FROM zsd_cust_usr_map INTO TABLE @lt_map                   "#EC CI_NOORDER
      WHERE cust_user_id = @iv_uname.

    LOOP AT lt_map INTO DATA(ls_map).
      CLEAR lv_kdgrp.
      SELECT SINGLE kdgrp FROM knvv INTO @lv_kdgrp                      "#EC CI_NOORDER
        WHERE kunnr = @ls_map-kunnr.

      IF lv_kdgrp <> 'DI' AND lv_kdgrp <> 'RE' AND lv_kdgrp <> 'TG'
         AND lv_kdgrp <> 'OI' AND lv_kdgrp <> 'EX'.
        " open group -> every customer sharing the group
        " (excludes division '11' and the restricted groups)
        SELECT * FROM knvv INTO TABLE @lt_knvv                          "#EC CI_NOORDER
          WHERE kdgrp = @lv_kdgrp AND spart <> '11'
            AND kdgrp <> 'DI' AND kdgrp <> 'TG'
            AND kdgrp <> 'OI' AND kdgrp <> 'RE'.
      ELSE.
        " restricted group -> only the seed sold-to itself
        SELECT * FROM knvv INTO TABLE @lt_knvv                          "#EC CI_NOORDER
          WHERE kunnr = @ls_map-kunnr AND spart <> '11'.
      ENDIF.
      SORT lt_knvv BY kunnr.
      DELETE ADJACENT DUPLICATES FROM lt_knvv COMPARING kunnr.

      LOOP AT lt_knvv INTO DATA(ls_knvv).
        SELECT * FROM knvp INTO TABLE @lt_knvp                          "#EC CI_NOORDER
          WHERE kunnr = @ls_knvv-kunnr AND parvw = 'WE' AND vtweg <> '11'.
        APPEND LINES OF lt_knvp TO lt_we.
      ENDLOOP.
      CLEAR lt_knvv.
    ENDLOOP.

    SORT lt_we BY kunn2.
    DELETE ADJACENT DUPLICATES FROM lt_we COMPARING kunn2.

    LOOP AT lt_we INTO DATA(ls_we).
      DATA ls_c TYPE ty_customer.
      CLEAR ls_c.
      ls_c-kunnr        = ls_we-kunn2.
      ls_c-cust_user_id = iv_uname.
      SELECT SINGLE name1 FROM kna1 INTO @ls_c-kunnr_desc              "#EC CI_NOORDER
        WHERE kunnr = @ls_we-kunn2.
      APPEND ls_c TO rt_cust.
    ENDLOOP.

    " NOTE (deferred - Low/presentation): the WebDynpro reorders the depot
    " 3100 ship-to '0000100036' and depot 3202 ship-tos '0000100192/193/194'
    " to the top of the list (out.txt:2686-2713). Purely cosmetic; not ported.
  ENDMETHOD.

  METHOD get_customer_material.
    " ---- WD ONACTIONSELECT_MAT_AND_GSTN (out.txt:9549-9615) -------------
    " 1) normalize the customer's KNVV group into (DI,EX,OI,TG,ON)
    " 2) enable flags: material-1 slot for all 5 groups; material-2 slot for
    "    OI/TG/ON only
    " 3) eligible materials = ZSD_INDT_NO_VEH rows for that group
    DATA lv_kdgrp TYPE knvv-kdgrp.
    DATA lv_act1  TYPE char1.
    DATA lv_act2  TYPE char1.

    lv_kdgrp = resolve_cust_group( iv_kunnr ).

    IF lv_kdgrp = 'DI' OR lv_kdgrp = 'EX' OR lv_kdgrp = 'OI'
       OR lv_kdgrp = 'TG' OR lv_kdgrp = 'ON'.
      lv_act1 = 'X'.
    ENDIF.
    IF lv_kdgrp = 'OI' OR lv_kdgrp = 'TG' OR lv_kdgrp = 'ON'.
      lv_act2 = 'X'.
    ENDIF.

    SELECT matnr, description FROM zsd_indt_no_veh                      "#EC CI_NOORDER
      INTO TABLE @DATA(lt_t)
      WHERE cust_group = @lv_kdgrp.
    LOOP AT lt_t INTO DATA(ls_t).
      APPEND VALUE #( kunnr   = iv_kunnr
                      matnr   = ls_t-matnr
                      matdesc = ls_t-description
                      active1 = lv_act1
                      active2 = lv_act2 ) TO rt_mat.
    ENDLOOP.
  ENDMETHOD.

  METHOD resolve_cust_group.
    " A customer carries several KNVV rows (one per sales area) that may span
    " more than one eligible group. The WebDynpro's "first row, else re-read"
    " used SELECT SINGLE without ORDER BY, which is non-deterministic on HANA:
    " the GetCustomerSet eligibility flag and the MaterialSet lookup could
    " resolve the SAME customer to DIFFERENT groups and disagree ("green in the
    " list, then No material configured on select"). We resolve deterministically
    " and, among the customer's eligible groups, PREFER one that actually has
    " materials in ZSD_INDT_NO_VEH - so the flag and MaterialSet agree by
    " construction. (Deliberate correctness change over the WD port.)
    SELECT DISTINCT kdgrp FROM knvv INTO TABLE @DATA(lt_grp)            "#EC CI_NOORDER
      WHERE kunnr = @iv_kunnr
        AND ( kdgrp = 'DI' OR kdgrp = 'EX' OR kdgrp = 'OI'
           OR kdgrp = 'TG' OR kdgrp = 'ON' )
      ORDER BY kdgrp.
    LOOP AT lt_grp INTO DATA(ls_g).
      SELECT SINGLE cust_group FROM zsd_indt_no_veh INTO @DATA(lv_has)  "#EC CI_NOORDER
        WHERE cust_group = @ls_g-kdgrp.
      IF sy-subrc = 0.
        rv_kdgrp = ls_g-kdgrp.
        RETURN.
      ENDIF.
    ENDLOOP.
    " none of the eligible groups have materials -> return the first eligible
    " one consistently so both checks agree the customer is NOT eligible
    READ TABLE lt_grp INTO ls_g INDEX 1.
    IF sy-subrc = 0.
      rv_kdgrp = ls_g-kdgrp.
    ENDIF.
  ENDMETHOD.

  METHOD get_contract_available.
    " ordered (VBAP-ZMENG) - delivered (VBFA) - open commitments, x1000 (KG)
    DATA: lv_tqty  TYPE vbap-zmeng,
          lv_tuom  TYPE vbap-zieme,
          lv_posnr TYPE vbap-posnr,
          lv_eqty  TYPE vbfa-rfmng_flo,
          lv_ord   TYPE ty_qty,
          lv_ordc  TYPE ty_qty.

    SELECT SINGLE zmeng zieme posnr FROM vbap                          "#EC CI_NOORDER
      INTO ( lv_tqty, lv_tuom, lv_posnr )
      WHERE vbeln = iv_vbeln AND matnr = iv_matnr.
    IF sy-subrc <> 0.
      rv_rqty = -1.          " contract/material pair does not exist -> unavailable
      RETURN.
    ENDIF.

    SELECT SUM( rfmng_flo ) FROM vbfa INTO lv_eqty
      WHERE vbelv = iv_vbeln AND vbtyp_n = 'C' AND posnv = lv_posnr.
    rv_rqty = lv_tqty - lv_eqty.

    " open commitments already booked against this contract
    SELECT SUM( bl_qty1 ) FROM zsd_indent_nveh INTO @lv_ord            "#EC CI_NOORDER
      WHERE contract1 = @iv_vbeln AND ord_closed = @space.
    SELECT order_no FROM zsd_indent_nveh INTO TABLE @DATA(lt_hdr)      "#EC CI_NOORDER
      WHERE contract1 = @iv_vbeln AND ord_closed = @space.
    LOOP AT lt_hdr INTO DATA(ls_hdr).
      CLEAR lv_ordc.
      SELECT SUM( quantity1 ) FROM zindt_nveh_item INTO @lv_ordc
        WHERE order_no = @ls_hdr-order_no AND shipment = @space.
      lv_ord = lv_ord + lv_ordc.
    ENDLOOP.
    IF lv_tuom = 'KG'.
      lv_ord = lv_ord * 1000.
    ENDIF.
    rv_rqty = rv_rqty - lv_ord.
  ENDMETHOD.

  METHOD raise_busi.
    " Free-text business error. message_unlimited is a STRING, so iv_msg
    " (also STRING) is directly compatible and the Gateway framework maps
    " it straight into the OData error response - no message container
    " plumbing required.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING
        textid            = /iwbep/cx_mgw_busi_exception=>business_error
        message_unlimited = iv_msg.
  ENDMETHOD.

ENDCLASS.
