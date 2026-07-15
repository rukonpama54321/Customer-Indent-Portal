*&---------------------------------------------------------------------*
*&  ZCL_ZSD_CUST_PORTAL_DE_DPC_EXT
*&  Deep-entity data provider - With-Vehicle Submit / Delete.
*&
*&  ZCREATESet  (CREATE_DEEP_ENTITY) -> ONACTIONSUBMIT_INDENT  (status 4 -> 5)
*&  ZDELETESet  (CREATE_DEEP_ENTITY) -> ONACTIONDELETE_INDENT / REACT_TO_YES
*&
*&  Both post a header + an item navigation:
*&    ZCREATESet : HDR_TO_ITEM_NAV
*&    ZDELETESet : HDR_TO_ITEM_DEL_NAV
*&  Each item carries DEPOT / KUNNR / BEGDA / VEHICLE / CUST_USER_ID /
*&  ZTT_STATUS.  DEPOT + KUNNR were added (M4) so a submit/delete of one
*&  selected row cannot re-SELECT and process every same-date+vehicle
*&  indent of the user's other customers/depots.
*&---------------------------------------------------------------------*
CLASS zcl_zsd_cust_portal_de_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zsd_cust_portal_de_dpc
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS /iwbep/if_mgw_appl_srv_runtime~create_deep_entity REDEFINITION.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_item,
             depot           TYPE zsd_cust_indent-depot,
             kunnr           TYPE zsd_cust_indent-kunnr,
             begda           TYPE begda,
             vehicle         TYPE oig_vhlnmr,
             cust_user_id    TYPE xubname,
             ztt_status      TYPE zsd_cust_indent-ztt_status,
             ztt_status_desc TYPE zsd_cust_indent-ztt_status_desc,
           END OF ty_item.
    TYPES tt_item TYPE STANDARD TABLE OF ty_item WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_deep,
             smtp_addr           TYPE ad_smtpadr,
             cust_user_id        TYPE xubname,
             hdr_to_item_nav     TYPE tt_item,
             hdr_to_item_del_nav TYPE tt_item,
           END OF ty_deep.

    METHODS submit_indents IMPORTING it_item TYPE tt_item.
    METHODS delete_indents IMPORTING it_item TYPE tt_item.

    "  Submit-path plan cap (port of EXECUTE_Z_IND_QTY_CHECK_SUBMIT,
    "  VW_SV2 = 'X' branch): re-aggregate the indent per division and
    "  compare (booked with status <> '4' + this indent) against the
    "  ZPROD_GRP_INDENT plan.  Returns 'X' when any group is over plan.
    METHODS qty_plan_check_submit
      IMPORTING is_indent       TYPE zsd_cust_indent
      RETURNING VALUE(rv_error) TYPE char1.

ENDCLASS.



CLASS zcl_zsd_cust_portal_de_dpc_ext IMPLEMENTATION.

  METHOD /iwbep/if_mgw_appl_srv_runtime~create_deep_entity.

    DATA ls_deep TYPE ty_deep.
    io_data_provider->read_entry_data( IMPORTING es_data = ls_deep ).

    CASE iv_entity_set_name.
      WHEN 'ZCREATESet'.
        submit_indents( ls_deep-hdr_to_item_nav ).
      WHEN 'ZDELETESet'.
        delete_indents( ls_deep-hdr_to_item_del_nav ).
      WHEN OTHERS.
        super->/iwbep/if_mgw_appl_srv_runtime~create_deep_entity(
          EXPORTING iv_entity_name = iv_entity_name iv_entity_set_name = iv_entity_set_name
                    iv_source_name = iv_source_name io_data_provider = io_data_provider
                    it_key_tab = it_key_tab it_navigation_path = it_navigation_path
                    io_expand = io_expand
          IMPORTING er_deep_entity = er_deep_entity ).
        RETURN.
    ENDCASE.

    " echo the request back
    copy_data_to_ref( EXPORTING is_data = ls_deep CHANGING cr_data = er_deep_entity ).

  ENDMETHOD.


  "===================================================================
  "  SUBMIT  (ONACTIONSUBMIT_INDENT)  -  status 4 -> 5
  "===================================================================
  METHOD submit_indents.

    LOOP AT it_item INTO DATA(ls_item).

      " KUNNR arrives ALPHA-stripped from GETINDENTSet but the deep item
      " field is a plain CHAR10 (no re-pad). Normalize to the internal
      " 10-char form so the key matches ZSD_CUST_INDENT-KUNNR.
      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING input  = ls_item-kunnr
        IMPORTING output = ls_item-kunnr.

      " read the saved indent(s) matching this item, status '4'.
      " DEPOT + KUNNR pin the row to the selected indent (M4) so a
      " single submit cannot sweep the user's other same-date+vehicle
      " indents into status '5'.
      SELECT * FROM zsd_cust_indent INTO TABLE @DATA(lt_ind)
        WHERE depot        = @ls_item-depot
          AND kunnr        = @ls_item-kunnr
          AND begda        = @ls_item-begda
          AND vehicle      = @ls_item-vehicle
          AND cust_user_id = @ls_item-cust_user_id
          AND ztt_status   = '4'.

      LOOP AT lt_ind INTO DATA(ls_ind).

        " Quantities are persisted with the UOM appended ("3.000KL"). The
        " staging tables (ZSAUTOMATETT_TBL/_LPG) and the ethanol stock check
        " take NUMERIC quantity fields, so moving the suffixed form into them
        " dumps (CX_SY_CONVERSION_NO_NUMBER). Mirror WD ONACTIONSUBMIT_INDENT
        " (out.txt 9896-9911): strip the UOM up front, keep the suffixed copy,
        " and restore it before the status MODIFY so the stored row keeps its
        " UOM for the report.
        DATA lt_qsuffixed TYPE STANDARD TABLE OF zsd_cust_indent-quan_comp1 WITH EMPTY KEY.
        CLEAR lt_qsuffixed.
        DO 8 TIMES.
          ASSIGN COMPONENT |QUAN_COMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<qc>).
          APPEND <qc> TO lt_qsuffixed.
          DATA(lv_clean) = CONV string( <qc> ).
          REPLACE ALL OCCURRENCES OF REGEX '[^0-9.]' IN lv_clean WITH ''.
          CONDENSE lv_clean NO-GAPS.
          <qc> = lv_clean.
        ENDDO.

        " plan cap re-check on submit (EXECUTE_Z_IND_QTY_CHECK_SUBMIT):
        " leave over-plan indents at status '4' instead of submitting.
        IF qty_plan_check_submit( ls_ind ) = 'X'.
          CONTINUE.
        ENDIF.

        " license re-check for B2B indents
        IF ls_ind-indent_type = 'B2B'.
          DATA: lv_error TYPE char1, lt_ret TYPE TABLE OF bapiret2.
          CALL FUNCTION 'Z_CHECK_VEHICLE_LICENSE'
            EXPORTING vehicle = ls_ind-vehicle
            IMPORTING error   = lv_error
            TABLES    return  = lt_ret.
          IF lv_error = 'X'. CONTINUE. ENDIF.
        ENDIF.

        " ethanol stock check for HOSP source
        DATA: lv_stk_err TYPE char1, lv_msg TYPE string,
              lv_q1 TYPE labst, lv_q2 TYPE labst, lv_q3 TYPE labst, lv_q4 TYPE labst,
              lv_q5 TYPE labst, lv_q6 TYPE labst, lv_q7 TYPE labst, lv_q8 TYPE labst.
        CLEAR lv_stk_err.
        IF ls_ind-indent_type = 'B2B'.
          " quantities already UOM-stripped above (WD out.txt 10014)
          lv_q1 = ls_ind-quan_comp1. lv_q2 = ls_ind-quan_comp2.
          lv_q3 = ls_ind-quan_comp3. lv_q4 = ls_ind-quan_comp4.
          lv_q5 = ls_ind-quan_comp5. lv_q6 = ls_ind-quan_comp6.
          lv_q7 = ls_ind-quan_comp7. lv_q8 = ls_ind-quan_comp8.
          CALL FUNCTION 'Z_ETHANOL_INDENT_STK_CHECK'
            EXPORTING cust_indent = ls_ind
                      c1_qt = lv_q1 c2_qt = lv_q2 c3_qt = lv_q3 c4_qt = lv_q4
                      c5_qt = lv_q5 c6_qt = lv_q6 c7_qt = lv_q7 c8_qt = lv_q8
            IMPORTING err_msg = lv_msg zstk_err = lv_stk_err.
          IF lv_stk_err = 'X'. CONTINUE. ENDIF.
        ENDIF.

        " volume tankers -> ZSAUTOMATETT_TBL, weight tankers -> ZSAUTOMATETT_LPG
        DATA lv_vtype TYPE oigv-veh_type.
        SELECT SINGLE veh_type FROM oigv INTO lv_vtype WHERE vehicle = ls_ind-vehicle.

        IF lv_vtype = 'TTV' OR lv_vtype = 'ATF' OR lv_vtype = 'WOIL' OR lv_vtype = 'TTVM'.
          DATA ls_tbl TYPE zsautomatett_tbl.
          CLEAR ls_tbl.
          MOVE-CORRESPONDING ls_ind TO ls_tbl.
          " ATF flushing flag: source field ATF_FLUSH, staging field
          " ATF_FLASH — names differ so MOVE-CORRESPONDING skips it (M5).
          " Mirrors WD ONACTIONSUBMIT_INDENT (out.txt 10000).
          ls_tbl-atf_flash = ls_ind-atf_flush.
          ls_tbl-ztt_status = '5'.
          IF ls_ind-kondm = '00'. CLEAR ls_tbl-kondm. ENDIF.
          INSERT zsautomatett_tbl FROM ls_tbl.
        ELSE.
          DATA ls_lpg TYPE zsautomatett_lpg.
          CLEAR ls_lpg.
          MOVE-CORRESPONDING ls_ind TO ls_lpg.
          ls_lpg-prod_cmp1 = ls_ind-prod_cmp1. ls_lpg-prod_quan1 = ls_ind-quan_comp1.
          ls_lpg-prod_cmp2 = ls_ind-prod_cmp2. ls_lpg-prod_quan2 = ls_ind-quan_comp2.
          ls_lpg-prod_cmp3 = ls_ind-prod_cmp3. ls_lpg-prod_quan3 = ls_ind-quan_comp3.
          ls_lpg-prod_cmp4 = ls_ind-prod_cmp4. ls_lpg-prod_quan4 = ls_ind-quan_comp4.
          ls_lpg-prod_cmp5 = ls_ind-prod_cmp5. ls_lpg-prod_quan5 = ls_ind-quan_comp5.
          ls_lpg-prod_cmp6 = ls_ind-prod_cmp6. ls_lpg-prod_quan6 = ls_ind-quan_comp6.
          ls_lpg-prod_cmp7 = ls_ind-prod_cmp7. ls_lpg-prod_quan7 = ls_ind-quan_comp7.
          ls_lpg-prod_cmp8 = ls_ind-prod_cmp8. ls_lpg-prod_quan8 = ls_ind-quan_comp8.
          ls_lpg-ztt_status = '5'.
          IF ls_ind-kondm = '00'. CLEAR ls_lpg-kondm. ENDIF.
          INSERT zsautomatett_lpg FROM ls_lpg.
        ENDIF.

        " mark the indent submitted
        IF sy-subrc = 0.
          " restore the UOM-suffixed quantities so the stored row keeps its
          " display form (WD out.txt 10076-10083)
          DO 8 TIMES.
            ASSIGN COMPONENT |QUAN_COMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<qr>).
            READ TABLE lt_qsuffixed INTO <qr> INDEX sy-index.
          ENDDO.
          ls_ind-ztt_status      = '5'.
          ls_ind-ztt_status_desc = 'Indent Submitted'.
          CLEAR ls_ind-chk.
          MODIFY zsd_cust_indent FROM ls_ind.
        ENDIF.

      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.


  "===================================================================
  "  SUBMIT plan cap  (EXECUTE_Z_IND_QTY_CHECK_SUBMIT, VW_SV2 = 'X')
  "===================================================================
  METHOD qty_plan_check_submit.

    rv_error = ''.

    " division -> (summary column on ZSD_CUST_INDENT, ZPROD_GRP_INDENT
    " material key).  Mirrors the save-path grouping in
    " ZCL_ZSDI_ODATA_CUST_PO_DPC_EXT=>qty_plan_check.
    TYPES: BEGIN OF ty_grp,
             col TYPE string,
             mat TYPE char10,
           END OF ty_grp.
    TYPES tt_grp TYPE STANDARD TABLE OF ty_grp WITH EMPTY KEY.
    DATA(lt_grp) = VALUE tt_grp(
      ( col = 'LPG'   mat = 'LPG' )
      ( col = 'MS'    mat = 'MS' )
      ( col = 'ATF'   mat = 'ATF' )
      ( col = 'SKO'   mat = 'SKO' )
      ( col = 'HSD'   mat = 'HSD' )
      ( col = 'ARHSD' mat = 'ARHSD' )
      ( col = 'PWAX'  mat = 'WAX' )
      ( col = 'MTO'   mat = 'MTO' )
      ( col = 'RPC'   mat = 'RPC_CPC' )
      ( col = 'SUL'   mat = 'SUL' )
      ( col = 'NTG'   mat = 'NTG' ) ).

    LOOP AT lt_grp INTO DATA(ls_grp).

      ASSIGN COMPONENT ls_grp-col OF STRUCTURE is_indent TO FIELD-SYMBOL(<qty>).
      IF sy-subrc <> 0 OR <qty> IS INITIAL. CONTINUE. ENDIF.

      " booked so far, excluding still-saved (status '4') rows, then
      " add this indent's qty (NCAP1C / NCAP1 / NCAPT).
      DATA: lv_bk_c TYPE zsd_cust_indent-hsd,
            lv_bk_g TYPE zsd_cust_indent-hsd,
            lv_bk_t TYPE zsd_cust_indent-hsd.
      " The aggregate itself must be the dynamic token — a dynamic column
      " name can't sit inside a static SUM( ), so build "SUM( <col> )" as a
      " string and pass it as the (dynamic) column list. A dynamic column
      " list isn't statically known to be aggregate-only, so ENDSELECT is
      " required (the aggregate yields one row → the loop runs once).
      DATA(lv_agg) = |SUM( { ls_grp-col } )|.
      CLEAR: lv_bk_c, lv_bk_g, lv_bk_t.
      SELECT (lv_agg) FROM zsd_cust_indent INTO @lv_bk_c
        WHERE kunnr = @is_indent-kunnr AND begda = @is_indent-begda
          AND depot = @is_indent-depot AND ztt_status <> '4'.
      ENDSELECT.
      SELECT (lv_agg) FROM zsd_cust_indent INTO @lv_bk_g
        WHERE kdgrp = @is_indent-kdgrp AND begda = @is_indent-begda
          AND depot = @is_indent-depot AND ztt_status <> '4'.
      ENDSELECT.
      SELECT (lv_agg) FROM zsd_cust_indent INTO @lv_bk_t
        WHERE begda = @is_indent-begda AND depot = @is_indent-depot
          AND ztt_status <> '4'.
      ENDSELECT.
      lv_bk_c = lv_bk_c + <qty>.
      lv_bk_g = lv_bk_g + <qty>.
      lv_bk_t = lv_bk_t + <qty>.

      " plan per customer / group / total (NCAP2C / NCAP2 / NCAP2T),
      " with the '00000000' generic-date fallback.
      DATA: lv_plan_c TYPE zprod_grp_indent-quantity,
            lv_plan_g TYPE zprod_grp_indent-quantity,
            lv_plan_t TYPE zprod_grp_indent-quantity.
      CLEAR: lv_plan_c, lv_plan_g, lv_plan_t.

      SELECT SINGLE quantity FROM zprod_grp_indent INTO @lv_plan_c "#EC CI_NOORDER
        WHERE material = @ls_grp-mat AND customer = @is_indent-kunnr
          AND ldate = @is_indent-begda AND depot = @is_indent-depot.
      IF sy-subrc <> 0.
        SELECT SINGLE quantity FROM zprod_grp_indent INTO @lv_plan_c "#EC CI_NOORDER
          WHERE material = @ls_grp-mat AND customer = @is_indent-kunnr
            AND ldate = '00000000' AND depot = @is_indent-depot.
      ENDIF.

      SELECT SINGLE quantity FROM zprod_grp_indent INTO @lv_plan_g
        WHERE material = @ls_grp-mat AND cust_group = @is_indent-kdgrp
          AND ldate = @is_indent-begda AND depot = @is_indent-depot AND customer = ' '.
      IF sy-subrc <> 0.
        SELECT SINGLE quantity FROM zprod_grp_indent INTO @lv_plan_g
          WHERE material = @ls_grp-mat AND cust_group = @is_indent-kdgrp
            AND ldate = '00000000' AND depot = @is_indent-depot AND customer = ' '.
      ENDIF.

      SELECT SINGLE quantity FROM zprod_grp_indent INTO @lv_plan_t "#EC CI_NOORDER
        WHERE material = @ls_grp-mat AND cust_group = ' ' AND customer = ' '
          AND ldate = @is_indent-begda AND depot = @is_indent-depot.
      IF sy-subrc <> 0.
        SELECT SINGLE quantity FROM zprod_grp_indent INTO @lv_plan_t "#EC CI_NOORDER
          WHERE material = @ls_grp-mat AND cust_group = ' ' AND customer = ' '
            AND ldate = '00000000' AND depot = @is_indent-depot.
      ENDIF.

      IF ( lv_plan_c > 0 AND lv_bk_c > lv_plan_c )
      OR ( lv_plan_g > 0 AND lv_bk_g > lv_plan_g )
      OR ( lv_plan_t > 0 AND lv_bk_t > lv_plan_t ).
        rv_error = 'X'.
        RETURN.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.


  "===================================================================
  "  DELETE  (ONACTIONREACT_TO_YES)
  "===================================================================
  METHOD delete_indents.

    LOOP AT it_item INTO DATA(ls_item).

      " KUNNR arrives from GETINDENTSet with leading zeros stripped (the
      " Edm property carries the ALPHA conversion), but the deep item
      " field is a plain CHAR10 that is never re-padded. Normalize to the
      " internal 10-char form so the key matches ZSD_CUST_INDENT-KUNNR
      " (mirrors create_entity, DPC_EXT ~749).
      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING input  = ls_item-kunnr
        IMPORTING output = ls_item-kunnr.

      " DEPOT + KUNNR pin the row(s) to the selected indent (M4) so a
      " single delete cannot sweep the user's other same-date+vehicle
      " indents of other customers/depots.
      SELECT * FROM zsd_cust_indent INTO TABLE @DATA(lt_ind)
        WHERE depot        = @ls_item-depot
          AND kunnr        = @ls_item-kunnr
          AND begda        = @ls_item-begda
          AND vehicle      = @ls_item-vehicle
          AND cust_user_id = @ls_item-cust_user_id
          AND ( ztt_status = '4' OR ztt_status = '5' ).

      LOOP AT lt_ind INTO DATA(ls_ind).

        " status 5 can only be deleted when flagged deletable
        IF ls_ind-ztt_status = '5' AND ls_ind-zdelete <> 'Y'.
          CONTINUE.
        ENDIF.

        " bulk-order balance to restore on a successful delete (M3):
        " read the open no-vehicle order this indent drew on and give
        " BL_QTY1 back the BULK_QTY it consumed.  Mirrors WD
        " ONACTIONREACT_TO_YES (out.txt 5430-5442 / 5478-5482): the
        " balance is recomputed here but only written back below, after
        " the indent delete succeeds and only when a real order exists.
        DATA ls_nveh TYPE zsd_indent_nveh.
        CLEAR ls_nveh.
        SELECT SINGLE * FROM zsd_indent_nveh INTO @ls_nveh
          WHERE order_no = @ls_ind-bulk_order.
        ls_nveh-bl_qty1 = ls_nveh-bl_qty1 + ls_ind-bulk_qty.

        DELETE zsd_cust_indent FROM ls_ind.
        IF sy-subrc = 0.

          " give the drawn bulk quantity back to the open order (M3)
          IF ls_nveh-order_no IS NOT INITIAL.
            MODIFY zsd_indent_nveh FROM ls_nveh.
          ENDIF.

          " staging cleanup WHERE clauses branch on status (M6):
          " status 4 -> both TBL and LPG also sweep blank-SHNUMBER
          " drafts (OR shnumber = ' '); status 5 -> both restricted to
          " ztt_status = '5'.  Mirrors WD out.txt 5446-5452 / 5484-5490.
          IF ls_ind-ztt_status = '4'.
            DELETE FROM zsautomatett_tbl
              WHERE begda   = ls_ind-begda
                AND depot   = ls_ind-depot
                AND vehicle = ls_ind-vehicle
                AND ( ztt_status = '4' OR shnumber = ' ' ).
            DELETE FROM zsautomatett_lpg
              WHERE begda   = ls_ind-begda
                AND depot   = ls_ind-depot
                AND vehicle = ls_ind-vehicle
                AND ( ztt_status = '4' OR shnumber = ' ' ).
          ELSE.
            DELETE FROM zsautomatett_tbl
              WHERE begda   = ls_ind-begda
                AND depot   = ls_ind-depot
                AND vehicle = ls_ind-vehicle
                AND ztt_status = '5'.
            DELETE FROM zsautomatett_lpg
              WHERE begda   = ls_ind-begda
                AND depot   = ls_ind-depot
                AND vehicle = ls_ind-vehicle
                AND ztt_status = '5'.
          ENDIF.
        ENDIF.

      ENDLOOP.
    ENDLOOP.

  ENDMETHOD.

ENDCLASS.
