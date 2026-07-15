*&---------------------------------------------------------------------*
*&  ZCL_ZSDI_ODATA_CUST_PO_DPC_EXT
*&  Data provider (extension) - With-Vehicle tab.
*&
*&  Ported from WebDynpro INDMAIN (component controller + view methods).
*&  Reads + SaveIndentSet create. Submit / Delete live in the deep service
*&  (see ZCL_ZSD_CUST_PORTAL_DE_DPC_EXT).
*&
*&  Paste the redefined methods into the generated *_DPC_EXT class and add
*&  the private TYPES / METHODS to its class definition.
*&---------------------------------------------------------------------*
CLASS zcl_zsdi_odata_cust_po_dpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zsdi_odata_cust_po_dpc
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS /iwbep/if_mgw_appl_srv_runtime~get_entityset REDEFINITION.
    METHODS /iwbep/if_mgw_appl_srv_runtime~create_entity REDEFINITION.

  PRIVATE SECTION.

    "---- line types (decoupled from MPC; match metadata.xml) ----------
    TYPES: BEGIN OF ty_vehicle,
             tu_number TYPE oig_vhlnmr,
             tu_text   TYPE char40,
             smtp_addr TYPE ad_smtpadr,
             color     TYPE c LENGTH 5,
             status    TYPE char10,
           END OF ty_vehicle.
    TYPES tt_vehicle TYPE STANDARD TABLE OF ty_vehicle WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_zuser,
             kunnr        TYPE kunnr,
             cust_user_id TYPE xubname,
             kdgrp        TYPE kdgrp,
             name1        TYPE name1_gp,
             smtp_addr    TYPE ad_smtpadr,
             gstin_enable TYPE char1,
           END OF ty_zuser.
    TYPES tt_zuser TYPE STANDARD TABLE OF ty_zuser WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_license,
             vehicle  TYPE oig_vhlnmr,
             message1 TYPE bapi_msg, message2 TYPE bapi_msg, message3 TYPE bapi_msg,
             message4 TYPE bapi_msg, message5 TYPE bapi_msg, message6 TYPE bapi_msg,
             message7 TYPE bapi_msg, message8 TYPE bapi_msg, message9 TYPE bapi_msg,
             message10 TYPE bapi_msg, message11 TYPE bapi_msg, message12 TYPE bapi_msg,
             message13 TYPE bapi_msg, message14 TYPE bapi_msg,
           END OF ty_license.
    TYPES tt_license TYPE STANDARD TABLE OF ty_license WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_comp,
             vehicle      TYPE oig_vhlnmr,
             com_number   TYPE int2,          " Edm.Int16 - must be numeric, not char
             composition  TYPE char16,
             veh_type     TYPE oigv-veh_type,
             total_comp   TYPE char16,
             uom          TYPE char3,
             comp_enabled TYPE char1,
           END OF ty_comp.
    TYPES tt_comp TYPE STANDARD TABLE OF ty_comp WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_product,
             vehicle      TYPE oig_vhlnmr,
             product      TYPE char100,
             veh_type     TYPE oigv-veh_type,
             cust_user_id TYPE xubname,
             smtp_addr    TYPE ad_smtpadr,
           END OF ty_product.
    TYPES tt_product TYPE STANDARD TABLE OF ty_product WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_gstn,
             gstn  TYPE char18,
             name  TYPE char50,
             kunnr TYPE kunnr,
           END OF ty_gstn.
    TYPES tt_gstn TYPE STANDARD TABLE OF ty_gstn WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_flush,
             ddtext  TYPE val_text,
             domname TYPE domname,
           END OF ty_flush.
    TYPES tt_flush TYPE STANDARD TABLE OF ty_flush WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_contract,
             kunnr        TYPE kunnr,
             text         TYPE vbeln,
             desc         TYPE char60,
             product1     TYPE char100, product2 TYPE char100,
             product3     TYPE char100, product4 TYPE char100,
             product5     TYPE char100, product6 TYPE char100,
             product7     TYPE char100, product8 TYPE char100,
             cust_user_id TYPE xubname,
             smtp_addr    TYPE ad_smtpadr,
           END OF ty_contract.
    TYPES tt_contract TYPE STANDARD TABLE OF ty_contract WITH DEFAULT KEY.

    TYPES: BEGIN OF ty_enduse,
             vehicle         TYPE oig_vhlnmr,
             domvalue_l      TYPE domvalue_l,
             activate_enduse TYPE char1,
             ddtext          TYPE val_text,
             product1        TYPE char40, product2 TYPE char40,
             product3        TYPE char40, product4 TYPE char40,
             product5        TYPE char40, product6 TYPE char40,
             product7        TYPE char40, product8 TYPE char40,
             begda           TYPE begda,
             kunnr           TYPE kunnr,
             cust_user_id    TYPE xubname,
             smtp_addr       TYPE ad_smtpadr,
           END OF ty_enduse.
    TYPES tt_enduse TYPE STANDARD TABLE OF ty_enduse WITH DEFAULT KEY.

    "---- helpers -----------------------------------------------------
    METHODS get_filter_value
      IMPORTING io_request      TYPE REF TO /iwbep/if_mgw_req_entityset
                iv_property     TYPE string
      RETURNING VALUE(rv_value) TYPE string.

    METHODS get_user_scope
      IMPORTING iv_uname       TYPE xubname
      EXPORTING et_kunnr       TYPE STANDARD TABLE     " ship-to customers
                et_depot       TYPE STANDARD TABLE     " depots
                ev_first_depot TYPE werks_d.           " WD ZTABCUST INDEX 1, pre-sort (M10)

    METHODS veh_uom
      IMPORTING iv_veh_type    TYPE oigv-veh_type
      RETURNING VALUE(rv_uom)  TYPE char3.

    METHODS qty_plan_check
      IMPORTING is_indent      TYPE zsd_cust_indent
      RETURNING VALUE(rv_error) TYPE char1.

    METHODS raise_busi
      IMPORTING iv_msg TYPE string
      RAISING   /iwbep/cx_mgw_busi_exception.

ENDCLASS.



CLASS zcl_zsdi_odata_cust_po_dpc_ext IMPLEMENTATION.

  "===================================================================
  "  GET_ENTITYSET  (dispatch)
  "===================================================================
  METHOD /iwbep/if_mgw_appl_srv_runtime~get_entityset.

    CASE iv_entity_set_name.

      "------------------------------------------------ VehicleSet ----
      WHEN 'VehicleSet'.
        DATA lt_veh TYPE tt_vehicle.
        SELECT vehicle AS tu_number, veh_type AS tu_text FROM oigv
          INTO CORRESPONDING FIELDS OF TABLE @lt_veh UP TO 5000 ROWS.  "#EC CI_NOWHERE
        LOOP AT lt_veh ASSIGNING FIELD-SYMBOL(<v>).
          <v>-status = 'Valid'.
        ENDLOOP.
        copy_data_to_ref( EXPORTING is_data = lt_veh CHANGING cr_data = er_entityset ).

      "-------------------------------------------------- ZUSERSet ----
      WHEN 'ZUSERSet'.
        DATA lt_user TYPE tt_zuser.
        DATA lv_uname TYPE xubname.
        lv_uname = get_filter_value( io_request = io_tech_request_context iv_property = 'CUST_USER_ID' ).
        IF lv_uname IS INITIAL. lv_uname = sy-uname. ENDIF.

        DATA lt_kunnr TYPE STANDARD TABLE OF kunnr.
        DATA lt_depot TYPE STANDARD TABLE OF werks_d.
        get_user_scope( EXPORTING iv_uname = lv_uname
                        IMPORTING et_kunnr = lt_kunnr et_depot = lt_depot ).

        LOOP AT lt_kunnr INTO DATA(lv_k).
          DATA ls_u TYPE ty_zuser.
          CLEAR ls_u.
          ls_u-kunnr        = lv_k.
          ls_u-cust_user_id = lv_uname.
          SELECT SINGLE name1 FROM kna1 INTO ls_u-name1 WHERE kunnr = lv_k.
          SELECT SINGLE kdgrp FROM knvv INTO ls_u-kdgrp WHERE kunnr = lv_k. "#EC CI_NOORDER
          IF ls_u-kdgrp = 'DI' OR ls_u-kdgrp = 'EX'.
            ls_u-gstin_enable = 'X'.
          ENDIF.
          APPEND ls_u TO lt_user.
        ENDLOOP.
        copy_data_to_ref( EXPORTING is_data = lt_user CHANGING cr_data = er_entityset ).

      "-------------------------------------------- CheckLicenseSet ---
      WHEN 'CheckLicenseSet'.
        DATA lt_lic TYPE tt_license.
        DATA ls_lic TYPE ty_license.
        ls_lic-vehicle = get_filter_value( io_request = io_tech_request_context iv_property = 'VEHICLE' ).

        " (a) open-indent check  (ONACTIONGET_VEHICLE)
        DATA: lv_idate TYPE begda,
              lv_sstsf TYPE oigs-oig_sstsf.
        SELECT MAX( begda ) FROM zsd_cust_indent INTO lv_idate
          WHERE vehicle = ls_lic-vehicle
            AND ( ztt_status = '5' OR ztt_status = '1' OR ztt_status = '2' OR ztt_status = '4' )
            AND zdelete = 'Y'.
        IF lv_idate IS NOT INITIAL.
          SELECT SINGLE shnumber FROM zsd_cust_indent INTO @DATA(lv_sh)   "#EC CI_NOORDER
            WHERE vehicle = @ls_lic-vehicle AND begda = @lv_idate
              AND ztt_status <> '1' AND ztt_status <> '2'
              AND ztt_status <> '4' AND ztt_status <> '5'.
          IF lv_sh IS NOT INITIAL.
            SELECT SINGLE oig_sstsf FROM oigs INTO @lv_sstsf WHERE shnumber = @lv_sh.
            IF lv_sstsf BETWEEN '2' AND '5'.
              CONCATENATE 'Please delete the open indent for the vehicle on'
                          lv_idate+6(2) '.' lv_idate+4(2) '.' lv_idate+0(4)
                          INTO ls_lic-message1 SEPARATED BY space.
              APPEND ls_lic TO lt_lic.
              copy_data_to_ref( EXPORTING is_data = lt_lic CHANGING cr_data = er_entityset ).
              RETURN.
            ENDIF.
          ENDIF.
        ENDIF.

        " (b) Z_CHECK_VEHICLE_LICENSE
        DATA: lv_error  TYPE char1,
              lt_return TYPE TABLE OF bapiret2.
        CALL FUNCTION 'Z_CHECK_VEHICLE_LICENSE'
          EXPORTING vehicle = ls_lic-vehicle
          IMPORTING error   = lv_error
          TABLES    return  = lt_return.
        IF lv_error = 'X'.
          DATA lv_i TYPE i.
          LOOP AT lt_return INTO DATA(ls_ret).
            lv_i = lv_i + 1.
            IF lv_i > 14. EXIT. ENDIF.
            ASSIGN COMPONENT |MESSAGE{ lv_i }| OF STRUCTURE ls_lic TO FIELD-SYMBOL(<m>).
            IF sy-subrc = 0. <m> = ls_ret-message. ENDIF.
          ENDLOOP.
        ENDIF.
        APPEND ls_lic TO lt_lic.
        copy_data_to_ref( EXPORTING is_data = lt_lic CHANGING cr_data = er_entityset ).

      "----------------------------------------- GETCompartmentNoSet --
      WHEN 'GETCompartmentNoSet'.
        DATA lt_comp TYPE tt_comp.
        DATA lv_veh TYPE oig_vhlnmr.
        lv_veh = get_filter_value( io_request = io_tech_request_context iv_property = 'VEHICLE' ).

        DATA: lv_c1 TYPE char12, lv_c2 TYPE char12, lv_c3 TYPE char12, lv_c4 TYPE char12,
              lv_c5 TYPE char12, lv_c6 TYPE char12, lv_c7 TYPE char12, lv_c8 TYPE char12,
              lt_oigcc TYPE TABLE OF oigcc.
        CALL FUNCTION 'Z_GET_COMP_CAPACITY'
          EXPORTING vehicle   = lv_veh
          IMPORTING capacity1 = lv_c1 capacity2 = lv_c2 capacity3 = lv_c3 capacity4 = lv_c4
                    capacity5 = lv_c5 capacity6 = lv_c6 capacity7 = lv_c7 capacity8 = lv_c8
          TABLES    itab_oigcc = lt_oigcc.

        DATA lv_cnt TYPE i.
        SELECT COUNT(*) FROM oigcc INTO lv_cnt WHERE tu_number = lv_veh. "#EC CI_NOORDER
        DATA lv_vtype TYPE oigv-veh_type.
        SELECT SINGLE veh_type FROM oigv INTO lv_vtype WHERE vehicle = lv_veh.

        DATA lv_uom TYPE char3.
        lv_uom = veh_uom( lv_vtype ).
        " qty editable only for non TTV/ATF/WOIL/TTVM vehicles (QN rule)
        DATA lv_qty_edit TYPE char1.
        IF lv_vtype = 'TTV' OR lv_vtype = 'ATF' OR lv_vtype = 'WOIL' OR lv_vtype = 'TTVM'.
          lv_qty_edit = ''.
        ELSE.
          lv_qty_edit = 'X'.
        ENDIF.

        DATA: lv_n TYPE i, lv_cap TYPE char12.
        DO lv_cnt TIMES.
          lv_n = sy-index.
          IF lv_n > 8. EXIT. ENDIF.
          CASE lv_n.
            WHEN 1. lv_cap = lv_c1. WHEN 2. lv_cap = lv_c2. WHEN 3. lv_cap = lv_c3. WHEN 4. lv_cap = lv_c4.
            WHEN 5. lv_cap = lv_c5. WHEN 6. lv_cap = lv_c6. WHEN 7. lv_cap = lv_c7. WHEN 8. lv_cap = lv_c8.
          ENDCASE.
          CONDENSE lv_cap.
          DATA ls_comp TYPE ty_comp.
          CLEAR ls_comp.
          ls_comp-vehicle      = lv_veh.
          ls_comp-com_number   = lv_n.
          ls_comp-composition  = lv_cap.
          ls_comp-veh_type     = lv_vtype.
          ls_comp-total_comp   = lv_cnt.
          ls_comp-uom          = lv_uom.
          ls_comp-comp_enabled = lv_qty_edit.
          APPEND ls_comp TO lt_comp.
        ENDDO.
        copy_data_to_ref( EXPORTING is_data = lt_comp CHANGING cr_data = er_entityset ).

      "------------------------------------------------ GETProductSet -
      WHEN 'GETProductSet'.
        DATA lt_prod TYPE tt_product.
        DATA lv_pveh TYPE oig_vhlnmr.
        lv_pveh = get_filter_value( io_request = io_tech_request_context iv_property = 'VEHICLE' ).
        DATA lv_puname TYPE xubname.
        lv_puname = get_filter_value( io_request = io_tech_request_context iv_property = 'CUST_USER_ID' ).
        IF lv_puname IS INITIAL. lv_puname = sy-uname. ENDIF.

        DATA lv_pvtype TYPE oigv-veh_type.
        SELECT SINGLE veh_type FROM oigv INTO lv_pvtype WHERE vehicle = lv_pveh.

        " ZSD_INDENT_PROD by category (ONACTIONGET_VEHICLE rules)
        DATA: lt_ip TYPE TABLE OF zsd_indent_prod,
              ls_ip TYPE zsd_indent_prod.
        IF lv_pvtype = 'TTV' OR lv_pvtype = 'WOIL' OR lv_pvtype = 'TTVM'.
          SELECT * FROM zsd_indent_prod INTO TABLE lt_ip WHERE category = 1 AND product <> 'ATF01'.
        ELSEIF lv_pvtype = 'ATF'.
          SELECT * FROM zsd_indent_prod INTO TABLE lt_ip WHERE category = 1 AND product = 'ATF01'.
        ELSEIF lv_pvtype = 'LPGB'.
          SELECT * FROM zsd_indent_prod INTO TABLE lt_ip WHERE category = 3.
        ELSE.
          SELECT * FROM zsd_indent_prod INTO TABLE lt_ip WHERE category = 5.
        ENDIF.

        " remove products the customer is not allowed (ZSD_CUST_NO_PRD)
        DATA lv_mapkunnr TYPE kunnr.
        SELECT SINGLE kunnr FROM zsd_cust_usr_map INTO lv_mapkunnr WHERE cust_user_id = lv_puname. "#EC CI_NOORDER
        DATA lt_noprd TYPE TABLE OF zsd_cust_no_prd.
        IF lv_mapkunnr IS NOT INITIAL.
          SELECT * FROM zsd_cust_no_prd INTO TABLE lt_noprd WHERE kunnr = lv_mapkunnr.
        ENDIF.

        LOOP AT lt_ip INTO ls_ip.
          READ TABLE lt_noprd TRANSPORTING NO FIELDS WITH KEY matnr = ls_ip-product.
          IF sy-subrc = 0. CONTINUE. ENDIF.
          DATA ls_prod TYPE ty_product.
          CLEAR ls_prod.
          ls_prod-vehicle  = lv_pveh.
          ls_prod-product  = ls_ip-product.
          ls_prod-veh_type = lv_pvtype.
          APPEND ls_prod TO lt_prod.
        ENDLOOP.
        copy_data_to_ref( EXPORTING is_data = lt_prod CHANGING cr_data = er_entityset ).

      "---------------------------------------------------- GSTNSet ---
      WHEN 'GSTNSet'.
        DATA lt_gstn TYPE tt_gstn.
        SELECT gstn AS gstn, name AS name FROM ztrans_gstn
          INTO CORRESPONDING FIELDS OF TABLE @lt_gstn.                  "#EC CI_NOWHERE
        copy_data_to_ref( EXPORTING is_data = lt_gstn CHANGING cr_data = er_entityset ).

      "---------------------------------------------- FlushreasonSet --
      WHEN 'FlushreasonSet'.
        DATA lt_flush TYPE tt_flush.
        SELECT domname AS domname, ddtext AS ddtext FROM dd07t
          INTO CORRESPONDING FIELDS OF TABLE @lt_flush
          WHERE domname = 'ZATF_FLUSH_REASON' AND ddlanguage = @sy-langu.
        SORT lt_flush BY ddtext.
        DELETE ADJACENT DUPLICATES FROM lt_flush COMPARING ddtext.
        copy_data_to_ref( EXPORTING is_data = lt_flush CHANGING cr_data = er_entityset ).

      "------------------------------------------- SalesContractSet ---
      WHEN 'SalesContractSet'.
        DATA lt_con TYPE tt_contract.
        DATA lv_cuname TYPE xubname.
        lv_cuname = get_filter_value( io_request = io_tech_request_context iv_property = 'CUST_USER_ID' ).
        IF lv_cuname IS INITIAL. lv_cuname = sy-uname. ENDIF.

        " WD ONACTIONSELECT_EXPORT keys the list on the selected customer +
        " the compartment-1 product (LV_KUNNR1 / LV_PROD1), not the whole scope.
        DATA lv_sc_kunnr TYPE kunnr.
        DATA lv_sc_prod1 TYPE matnr.
        lv_sc_kunnr = get_filter_value( io_request = io_tech_request_context iv_property = 'KUNNR' ).
        lv_sc_prod1 = get_filter_value( io_request = io_tech_request_context iv_property = 'PRODUCT1' ).

        " M12: WD shows the sales-contract list only for the special products
        " PWAX/RPC0/CPC0/SUL0/GWAX (out.txt 9049-9053) -- PWAX and GWAX are matched
        " across compartments 1-5, the others on compartment 1 only. Non-special
        " products take the IN/EP price-group path below (business decision Q2 = A).
        DATA: lv_sc_p2   TYPE matnr, lv_sc_p3 TYPE matnr,
              lv_sc_p4   TYPE matnr, lv_sc_p5 TYPE matnr,
              lv_special TYPE abap_bool.
        lv_sc_p2 = get_filter_value( io_request = io_tech_request_context iv_property = 'PRODUCT2' ).
        lv_sc_p3 = get_filter_value( io_request = io_tech_request_context iv_property = 'PRODUCT3' ).
        lv_sc_p4 = get_filter_value( io_request = io_tech_request_context iv_property = 'PRODUCT4' ).
        lv_sc_p5 = get_filter_value( io_request = io_tech_request_context iv_property = 'PRODUCT5' ).
        lv_special = abap_false.
        IF lv_sc_prod1(4) = 'PWAX' OR lv_sc_p2(4) = 'PWAX' OR lv_sc_p3(4) = 'PWAX'
           OR lv_sc_p4(4) = 'PWAX' OR lv_sc_p5(4) = 'PWAX'
           OR lv_sc_prod1(4) = 'RPC0' OR lv_sc_prod1(4) = 'CPC0' OR lv_sc_prod1(4) = 'SUL0'
           OR lv_sc_prod1(4) = 'GWAX' OR lv_sc_p2(4) = 'GWAX' OR lv_sc_p3(4) = 'GWAX'
           OR lv_sc_p4(4) = 'GWAX' OR lv_sc_p5(4) = 'GWAX'.
          lv_special = abap_true.
        ENDIF.

        " depot for this user (WD: SELECT SINGLE DEPOT FROM zsd_cust_usr_map)
        DATA lt_ck TYPE STANDARD TABLE OF kunnr.
        DATA lt_cd TYPE STANDARD TABLE OF werks_d.
        DATA lv_sc_depot TYPE werks_d.
        get_user_scope( EXPORTING iv_uname = lv_cuname IMPORTING et_kunnr = lt_ck et_depot = lt_cd ).
        READ TABLE lt_cd INTO lv_sc_depot INDEX 1.

        IF lv_sc_kunnr IS NOT INITIAL AND lv_sc_prod1 IS NOT INITIAL.
         IF lv_special = abap_true.
          " open contract for exactly this customer / product / depot (out.txt 9075-9087)
          SELECT v~vbeln, a~matnr
            FROM vbak AS v
            INNER JOIN vbpa AS p ON p~vbeln = v~vbeln
            INNER JOIN vbap AS a ON a~vbeln = v~vbeln
            INTO TABLE @DATA(lt_vb)
            WHERE v~guebg <= @sy-datum AND v~gueen >= @sy-datum
              AND p~kunnr = @lv_sc_kunnr AND p~parvw = 'WE'
              AND a~matnr = @lv_sc_prod1 AND a~bwtar = 'OWN-BOND'
              AND a~werks = @lv_sc_depot AND a~pstyv <> 'ZTAE'. "#EC CI_BUFFJOIN
          SORT lt_vb BY vbeln ASCENDING.

          DATA lt_con_pre TYPE tt_contract.
          CLEAR lt_con_pre.
          " M12: open-balance per contract via VBAP contract qty minus the
          " delivered sum from VBFA (WD out.txt 9090-9100):
          "   RQTY = ZMENG - SUM( RFMNG_FLO ).
          DATA: lv_tqty TYPE vbap-zmeng,
                lv_tuom TYPE vbap-zieme,
                lv_posnr TYPE vbap-posnr,
                lv_eqty TYPE vbfa-rfmng,
                lv_rqty TYPE vbap-zmeng,
                lv_baltxt TYPE char20.
          LOOP AT lt_vb INTO DATA(ls_vb).
            DATA ls_con TYPE ty_contract.
            CLEAR ls_con.
            ls_con-kunnr        = lv_sc_kunnr.
            ls_con-text         = ls_vb-vbeln.
            ls_con-product1     = ls_vb-matnr.
            ls_con-cust_user_id = lv_cuname.

            CLEAR: lv_tqty, lv_tuom, lv_posnr, lv_eqty, lv_rqty, lv_baltxt.
            SELECT SINGLE zmeng, zieme, posnr FROM vbap           "#EC CI_NOORDER
              INTO (@lv_tqty, @lv_tuom, @lv_posnr)
              WHERE vbeln = @ls_vb-vbeln AND matnr = @ls_vb-matnr.
            SELECT SUM( rfmng_flo ) FROM vbfa INTO @lv_eqty
              WHERE vbelv = @ls_vb-vbeln AND vbtyp_n = 'C' AND posnv = @lv_posnr.
            lv_rqty = lv_tqty - lv_eqty.
            WRITE lv_rqty TO lv_baltxt UNIT lv_tuom.
            CONDENSE lv_baltxt.
            CONCATENATE ls_vb-matnr '- Bal:' lv_baltxt lv_tuom
              INTO ls_con-desc SEPARATED BY space.

            APPEND ls_con TO lt_con_pre.
          ENDLOOP.

          " WD replacement path (out.txt 9102-9119): if any open no-vehicle
          " indent exists on these contracts, rebuild the whole list from the
          " ZSD_INDENT_NVEH order numbers instead of the contract VBELNs.
          DATA lt_nveh TYPE STANDARD TABLE OF zsd_indent_nveh.
          DATA ls_nveh TYPE zsd_indent_nveh.
          CLEAR lt_nveh.
          LOOP AT lt_con_pre INTO ls_con.
            SELECT SINGLE * FROM zsd_indent_nveh INTO ls_nveh
              WHERE contract1 = @ls_con-text AND ord_closed = @space.
            IF sy-subrc = 0.
              APPEND ls_nveh TO lt_nveh.
            ENDIF.
          ENDLOOP.

          IF lt_nveh IS NOT INITIAL.
            READ TABLE lt_con_pre INTO ls_con INDEX 1. " keep kunnr/product of first contract
            LOOP AT lt_nveh INTO ls_nveh.
              ls_con-text = ls_nveh-order_no.
              " M12: open no-vehicle order carries its own balance (WD 9116: RQTY = BL_QTY1).
              CLEAR lv_baltxt.
              WRITE ls_nveh-bl_qty1 TO lv_baltxt.
              CONDENSE lv_baltxt.
              CONCATENATE ls_con-product1 '- Bal:' lv_baltxt INTO ls_con-desc SEPARATED BY space.
              APPEND ls_con TO lt_con.
            ENDLOOP.
          ELSE.
            lt_con = lt_con_pre.
          ENDIF.
         ELSE.
          " M12 non-special products: WD lists the T178 material price-group
          " codes IN / EP instead of contracts (out.txt 9139-9161). Full WD
          " parity per business decision Q2 = A.
          " Enhancement (beyond WD): carry the configured price-group text
          " (T178T-VTEXT, e.g. Inland / Export) as DESC so the value-help shows
          " a meaningful subtitle instead of repeating the code.
          SELECT t~kondm, x~vtext
            FROM t178 AS t
            LEFT JOIN t178t AS x ON x~kondm = t~kondm AND x~spras = @sy-langu
            INTO TABLE @DATA(lt_t178)
            WHERE t~kondm = 'IN' OR t~kondm = 'EP'.        "#EC CI_BUFFJOIN
          LOOP AT lt_t178 INTO DATA(ls_t178).
            CLEAR ls_con.
            ls_con-kunnr        = lv_sc_kunnr.
            ls_con-text         = ls_t178-kondm.
            " title already shows the code (TEXT); keep DESC as the plain
            " price-group text so the dialog reads e.g. "IN / Inland".
            ls_con-desc         = COND #( WHEN ls_t178-vtext IS NOT INITIAL
                                          THEN ls_t178-vtext
                                          ELSE ls_t178-kondm ).
            ls_con-product1     = lv_sc_prod1.
            ls_con-cust_user_id = lv_cuname.
            APPEND ls_con TO lt_con.
          ENDLOOP.
         ENDIF.
        ENDIF.

        SORT lt_con BY text.
        DELETE ADJACENT DUPLICATES FROM lt_con COMPARING text.
        copy_data_to_ref( EXPORTING is_data = lt_con CHANGING cr_data = er_entityset ).

      "-------------------------------------------------- GetEndUseSet -
      WHEN 'GetEndUseSet'.
        DATA lt_eu TYPE tt_enduse.
        DATA: lv_euveh TYPE oig_vhlnmr,
              lv_eukun TYPE kunnr,
              lv_eubeg TYPE begda.
        lv_euveh = get_filter_value( io_request = io_tech_request_context iv_property = 'VEHICLE' ).
        lv_eukun = get_filter_value( io_request = io_tech_request_context iv_property = 'KUNNR' ).
        lv_eubeg = get_filter_value( io_request = io_tech_request_context iv_property = 'BEGDA' ).

        " derive the user's depot for the M11 3100 exclusion (WD reads
        " SELECT SINGLE DEPOT FROM zsd_cust_usr_map WHERE cust_user_id = sy-uname)
        DATA lv_eu_user TYPE xubname.
        lv_eu_user = get_filter_value( io_request = io_tech_request_context iv_property = 'CUST_USER_ID' ).
        IF lv_eu_user IS INITIAL. lv_eu_user = sy-uname. ENDIF.
        DATA: lt_eu_k TYPE STANDARD TABLE OF kunnr,
              lt_eu_d TYPE STANDARD TABLE OF werks_d,
              lv_eu_depot TYPE werks_d.
        get_user_scope( EXPORTING iv_uname = lv_eu_user IMPORTING et_kunnr = lt_eu_k et_depot = lt_eu_d ).
        READ TABLE lt_eu_d INTO lv_eu_depot INDEX 1.

        " collect chosen products
        DATA: lt_chosen TYPE TABLE OF char100, lv_pn TYPE i.
        DO 8 TIMES.
          lv_pn = sy-index.
          DATA(lv_pv) = get_filter_value( io_request = io_tech_request_context
                                          iv_property = |PRODUCT{ lv_pn }| ).
          IF lv_pv IS NOT INITIAL. APPEND lv_pv TO lt_chosen. ENDIF.
        ENDDO.

        DATA: lv_act_ms  TYPE char1,
              lv_act_hsd TYPE char1,
              lv_cnt2    TYPE i.
        " MS06 -> needs KNVV 10/25 and date >= 01.11.2022
        READ TABLE lt_chosen TRANSPORTING NO FIELDS WITH KEY table_line = 'MS06'.
        IF sy-subrc = 0 AND lv_eubeg >= '20221101'.
          SELECT COUNT(*) FROM knvv INTO lv_cnt2
            WHERE vtweg = '10' AND spart = '25' AND kunnr = lv_eukun.
          IF lv_cnt2 > 0. lv_act_ms = 'X'. ENDIF.
        ENDIF.
        " HSD06 -> needs KNVV 10/40 and date >= 01.04.2028 (per WebDynpro guard)
        READ TABLE lt_chosen TRANSPORTING NO FIELDS WITH KEY table_line = 'HSD06'.
        IF sy-subrc = 0 AND lv_eubeg >= '20280401'.
          SELECT COUNT(*) FROM knvv INTO lv_cnt2
            WHERE vtweg = '10' AND spart = '40' AND kunnr = lv_eukun.
          IF lv_cnt2 > 0. lv_act_hsd = 'X'. ENDIF.
        ENDIF.

        IF lv_act_ms = 'X' OR lv_act_hsd = 'X'.
          DATA: lt_dd TYPE TABLE OF dd07t,
                ls_dd TYPE dd07t.
          SELECT * FROM dd07t INTO TABLE lt_dd
            WHERE domname = 'ZIND_END_USE' AND ddlanguage = sy-langu.
          LOOP AT lt_dd INTO ls_dd.
            DATA ls_eu TYPE ty_enduse.
            " M11: NORM_OBLND / BRND_OBLND end-uses are not offered at
            " depot 3100 (WD out.txt 9265-9272).
            IF lv_eu_depot = '3100'
               AND ( ls_dd-domvalue_l = 'NORM_OBLND' OR ls_dd-domvalue_l = 'BRND_OBLND' ).
              CONTINUE.
            ENDIF.
            IF lv_act_ms = 'X'.
              CLEAR ls_eu.
              ls_eu-vehicle         = lv_euveh.
              ls_eu-domvalue_l      = ls_dd-domvalue_l.
              ls_eu-activate_enduse = 'X'.
              CONCATENATE 'MS-' ls_dd-ddtext INTO ls_eu-ddtext.
              APPEND ls_eu TO lt_eu.
            ENDIF.
            IF lv_act_hsd = 'X'.
              CLEAR ls_eu.
              ls_eu-vehicle         = lv_euveh.
              ls_eu-domvalue_l      = ls_dd-domvalue_l.
              ls_eu-activate_enduse = 'X'.
              CONCATENATE 'HSD-' ls_dd-ddtext INTO ls_eu-ddtext.
              APPEND ls_eu TO lt_eu.
            ENDIF.
          ENDLOOP.
        ENDIF.
        copy_data_to_ref( EXPORTING is_data = lt_eu CHANGING cr_data = er_entityset ).

      "------------------------------------------------- GETINDENTSet -
      WHEN 'GETINDENTSet'.
        DATA lt_out TYPE STANDARD TABLE OF zsd_cust_indent.
        DATA: lv_giuname TYPE xubname,
              lv_gibeg   TYPE begda,
              lv_giveh   TYPE oig_vhlnmr,
              lv_gimode  TYPE char10,
              lv_gidel   TYPE char1,
              lv_gifirst TYPE werks_d.
        lv_giuname = get_filter_value( io_request = io_tech_request_context iv_property = 'CUST_USER_ID' ).
        IF lv_giuname IS INITIAL. lv_giuname = sy-uname. ENDIF.
        lv_gibeg  = get_filter_value( io_request = io_tech_request_context iv_property = 'BEGDA' ).
        lv_giveh  = get_filter_value( io_request = io_tech_request_context iv_property = 'VEHICLE' ).
        lv_gimode = get_filter_value( io_request = io_tech_request_context iv_property = 'INDENT_TYPE' ).
        lv_gidel  = get_filter_value( io_request = io_tech_request_context iv_property = 'ZDELETE' ).

        " Z_GET_CUSTOMER_INDENT filters on VEHICLE, so a blank vehicle
        " returns nothing. When the caller supplies no vehicle, list every
        " indent for the loading date + customer user id directly; the
        " depot/ship-to scope loop below still restricts what is returned.
        IF lv_giveh IS INITIAL.
          SELECT * FROM zsd_cust_indent INTO TABLE lt_out
            WHERE begda = lv_gibeg AND cust_user_id = lv_giuname.
        ELSE.
          CALL FUNCTION 'Z_GET_CUSTOMER_INDENT'
            EXPORTING vehicle    = lv_giveh
                      ind_date   = lv_gibeg
                      zuname     = lv_giuname
            TABLES    itab_indent = lt_out.
        ENDIF.

        " restrict to the user's depots + ship-to partners
        DATA lt_gk TYPE STANDARD TABLE OF kunnr.
        DATA lt_gd TYPE STANDARD TABLE OF werks_d.
        get_user_scope( EXPORTING iv_uname = lv_giuname
                        IMPORTING et_kunnr = lt_gk et_depot = lt_gd ev_first_depot = lv_gifirst ).

        " M10: when a type/deletable filter is applied, WD narrows the list to the
        " first mapped depot only (out.txt 597-612); an unfiltered list spans all
        " mapped depots (634-646). Match WebDynpro (business decision Q1 = A).
        DATA(lv_gifilter) = xsdbool( lv_gimode IS NOT INITIAL OR lv_gidel IS NOT INITIAL ).

        DATA lt_gi TYPE STANDARD TABLE OF zsd_cust_indent.
        LOOP AT lt_out INTO DATA(ls_o).
          IF lv_gifilter = abap_true.
            IF ls_o-depot <> lv_gifirst. CONTINUE. ENDIF.
          ELSE.
            READ TABLE lt_gd TRANSPORTING NO FIELDS WITH KEY table_line = ls_o-depot.
            IF sy-subrc <> 0. CONTINUE. ENDIF.
          ENDIF.
          " Keep rows whose ship-to is in the user's expanded scope, OR that
          " the requesting user created themselves. A saved indent must stay
          " visible even if its ship-to later dropped out of the KNVV->KNVP
          " scope expansion (otherwise it blocks new saves but is invisible).
          READ TABLE lt_gk TRANSPORTING NO FIELDS WITH KEY table_line = ls_o-kunnr.
          IF sy-subrc <> 0 AND ls_o-cust_user_id <> lv_giuname. CONTINUE. ENDIF.
          IF lv_gimode IS NOT INITIAL AND ls_o-indent_type <> lv_gimode. CONTINUE. ENDIF.
          IF lv_gidel  IS NOT INITIAL AND ls_o-zdelete     <> lv_gidel.  CONTINUE. ENDIF.
          APPEND ls_o TO lt_gi.
        ENDLOOP.
        SORT lt_gi BY ztt_status DESCENDING.

        " map to GETINDENT entity (+ customer name)
        DATA: BEGIN OF ls_gi,
                vehicle         TYPE oig_vhlnmr,
                begda           TYPE begda,
                depot           TYPE zsd_cust_indent-depot,
                kunnr           TYPE kunnr,
                name1           TYPE name1_gp,
                cust_user_id    TYPE xubname,
                prod_cmp1       TYPE matnr, quan_comp1 TYPE zsd_cust_indent-quan_comp1, val_comp1 TYPE bwtar_d,
                prod_cmp2       TYPE matnr, quan_comp2 TYPE zsd_cust_indent-quan_comp2, val_comp2 TYPE bwtar_d,
                prod_cmp3       TYPE matnr, quan_comp3 TYPE zsd_cust_indent-quan_comp3, val_comp3 TYPE bwtar_d,
                prod_cmp4       TYPE matnr, quan_comp4 TYPE zsd_cust_indent-quan_comp4, val_comp4 TYPE bwtar_d,
                prod_cmp5       TYPE matnr, quan_comp5 TYPE zsd_cust_indent-quan_comp5, val_comp5 TYPE bwtar_d,
                prod_cmp6       TYPE matnr, quan_comp6 TYPE zsd_cust_indent-quan_comp6, val_comp6 TYPE bwtar_d,
                prod_cmp7       TYPE matnr, quan_comp7 TYPE zsd_cust_indent-quan_comp7, val_comp7 TYPE bwtar_d,
                prod_cmp8       TYPE matnr, quan_comp8 TYPE zsd_cust_indent-quan_comp8, val_comp8 TYPE bwtar_d,
                ztt_status      TYPE zsd_cust_indent-ztt_status,
                ztt_status_desc TYPE zsd_cust_indent-ztt_status_desc,
                color           TYPE c LENGTH 7,
                zdelete         TYPE zsd_cust_indent-zdelete,
                tpt_gstn        TYPE zsd_cust_indent-tpt_gstn,
                flush_reason    TYPE zsd_cust_indent-flush_reason,
                atf_flush       TYPE char1,
                ms_end_use      TYPE zsd_cust_indent-ms_end_use,
                hsd_end_use     TYPE zsd_cust_indent-hsd_end_use,
                kondm           TYPE zsd_cust_indent-kondm,
                contract        TYPE zsd_cust_indent-contract,
                indent_type     TYPE zsd_cust_indent-indent_type,
                error           TYPE zsd_cust_indent-error,
                smtp_addr       TYPE ad_smtpadr,
                begda_disp      TYPE char10,
              END OF ls_gi.
        DATA lt_gi_out LIKE STANDARD TABLE OF ls_gi.

        LOOP AT lt_gi ASSIGNING FIELD-SYMBOL(<ind>).
          CLEAR ls_gi.
          MOVE-CORRESPONDING <ind> TO ls_gi.
          SELECT SINGLE name1 FROM kna1 INTO ls_gi-name1 WHERE kunnr = <ind>-kunnr.
          " display date dd.mm.yyyy (table shows BEGDA_DISP; BEGDA stays internal)
          IF <ind>-begda IS NOT INITIAL.
            CONCATENATE <ind>-begda+6(2) <ind>-begda+4(2) <ind>-begda+0(4)
                        INTO ls_gi-begda_disp SEPARATED BY '.'.
          ENDIF.
          APPEND ls_gi TO lt_gi_out.
        ENDLOOP.
        copy_data_to_ref( EXPORTING is_data = lt_gi_out CHANGING cr_data = er_entityset ).

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
  "  CREATE_ENTITY  (SaveIndentSet)  - ONACTIONSAVE_INDENT
  "===================================================================
  METHOD /iwbep/if_mgw_appl_srv_runtime~create_entity.

    " SaveIndentSet   = create a new draft indent (status 4)
    " IndentUpdateSet = re-save an existing draft. The WebDynpro "modify"
    "                   flow is ONACTIONSAVE_INDENT with LV_ZT2 = 'X':
    "                   identical save logic, but the existing status-4
    "                   row is deleted first (see below).
    DATA lv_update TYPE abap_bool.
    CASE iv_entity_set_name.
      WHEN 'SaveIndentSet'.   lv_update = abap_false.
      WHEN 'IndentUpdateSet'. lv_update = abap_true.
      WHEN OTHERS.
        super->/iwbep/if_mgw_appl_srv_runtime~create_entity(
          EXPORTING iv_entity_name = iv_entity_name iv_entity_set_name = iv_entity_set_name
                    iv_source_name = iv_source_name io_data_provider = io_data_provider
                    it_key_tab = it_key_tab it_navigation_path = it_navigation_path
          IMPORTING er_entity = er_entity ).
        RETURN.
    ENDCASE.

    " --- read the posted entry (SaveIndent / IndentUpdate share it) -
    DATA: BEGIN OF ls_in,
            begda        TYPE begda,
            vehicle      TYPE oig_vhlnmr,
            kunnr        TYPE kunnr,
            kunnr_desc   TYPE char30,
            cust_user_id TYPE xubname,
            smtp_addr    TYPE ad_smtpadr,
            contract     TYPE zsd_cust_indent-contract,
            tpt_gstn     TYPE zsd_cust_indent-tpt_gstn,
            ms_end_use   TYPE zsd_cust_indent-ms_end_use,
            hsd_end_use  TYPE zsd_cust_indent-hsd_end_use,
            atf_flush    TYPE char1,
            flush_reason TYPE zsd_cust_indent-flush_reason,
            prod_cmp1 TYPE matnr, quan_comp1 TYPE char16,
            prod_cmp2 TYPE matnr, quan_comp2 TYPE char16,
            prod_cmp3 TYPE matnr, quan_comp3 TYPE char16,
            prod_cmp4 TYPE matnr, quan_comp4 TYPE char16,
            prod_cmp5 TYPE matnr, quan_comp5 TYPE char16,
            prod_cmp6 TYPE matnr, quan_comp6 TYPE char16,
            prod_cmp7 TYPE matnr, quan_comp7 TYPE char16,
            prod_cmp8 TYPE matnr, quan_comp8 TYPE char16,
            error     TYPE zsd_cust_indent-error,
          END OF ls_in.
    io_data_provider->read_entry_data( IMPORTING es_data = ls_in ).

    DATA lv_uname TYPE xubname.
    lv_uname = COND #( WHEN ls_in-cust_user_id IS NOT INITIAL THEN ls_in-cust_user_id ELSE sy-uname ).
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING input = ls_in-kunnr IMPORTING output = ls_in-kunnr.

    " depot + veh_type
    DATA lv_plant TYPE werks_d.
    SELECT SINGLE depot FROM zsd_cust_usr_map INTO lv_plant         "#EC CI_NOORDER
      WHERE cust_user_id = lv_uname.
    DATA lv_vtype TYPE oigv-veh_type.
    SELECT SINGLE veh_type FROM oigv INTO lv_vtype WHERE vehicle = ls_in-vehicle.

    " ---------- validations (mirror the WebDynpro popups) -----------
    IF ls_in-vehicle IS INITIAL.
      raise_busi( 'Please enter a Vehicle.' ).
    ENDIF.
    IF ls_in-kunnr IS INITIAL.
      raise_busi( 'Please select Customer.' ).
    ENDIF.
    IF lv_plant IS INITIAL.
      raise_busi( 'User is not mapped in ZSD_CUST_USR_MAP.' ).
    ENDIF.

    " ATF flushing
    IF lv_vtype = 'ATF'.
      IF ls_in-atf_flush IS INITIAL.
        raise_busi( 'Please select Flushing requirement for ATF tanker.' ).
      ENDIF.
      IF ls_in-atf_flush = 'Y' AND ls_in-flush_reason IS INITIAL.
        raise_busi( 'Please select Flushing reason.' ).
      ENDIF.
    ENDIF.

    " number of compartments
    DATA lv_cnt TYPE i.
    SELECT COUNT(*) FROM oigcc INTO lv_cnt WHERE tu_number = ls_in-vehicle. "#EC CI_NOORDER

    " product for every compartment up to cnt
    DATA: lv_idx TYPE i, lv_prod TYPE matnr.
    DO lv_cnt TIMES.
      lv_idx = sy-index.
      IF lv_idx > 8. EXIT. ENDIF.
      ASSIGN COMPONENT |PROD_CMP{ lv_idx }| OF STRUCTURE ls_in TO FIELD-SYMBOL(<p>).
      IF <p> IS INITIAL.
        raise_busi( 'Please select Product for all compartments.' ).
      ENDIF.
    ENDDO.

    " GSTN for DI/EX customers
    DATA lv_kdgrp TYPE kdgrp.
    SELECT SINGLE kdgrp FROM knvv INTO lv_kdgrp WHERE kunnr = ls_in-kunnr. "#EC CI_NOORDER
    DATA lv_spart TYPE spart.
    SELECT SINGLE spart FROM mara INTO lv_spart WHERE matnr = ls_in-prod_cmp1. "#EC CI_NOORDER
    IF ( lv_kdgrp = 'DI' OR lv_kdgrp = 'EX' )
       AND ls_in-tpt_gstn IS INITIAL
       AND lv_spart <> '40' AND lv_spart <> '25' AND lv_spart <> '30'.
      raise_busi( 'Please enter GSTN of Transporter.' ).
    ENDIF.

    " sales contract for PWAX (comps 1-6) / SUL0/RPC0/CPC0 (comp 1)
    "  mirror WebDynpro ONACTIONSAVE_INDENT contract check (out.txt 6449-6455):
    "  PWAX anywhere in prod1..6, or SUL0/RPC0/CPC0 in prod1, needs a contract.
    IF ls_in-contract IS INITIAL
       AND ( ls_in-prod_cmp1(4) = 'PWAX' OR ls_in-prod_cmp2(4) = 'PWAX'
          OR ls_in-prod_cmp3(4) = 'PWAX' OR ls_in-prod_cmp4(4) = 'PWAX'
          OR ls_in-prod_cmp5(4) = 'PWAX' OR ls_in-prod_cmp6(4) = 'PWAX'
          OR ls_in-prod_cmp1(4) = 'SUL0' OR ls_in-prod_cmp1(4) = 'RPC0'
          OR ls_in-prod_cmp1(4) = 'CPC0' ).
      raise_busi( 'Please select SALES CONTRACT.' ).
    ENDIF.

    " CHANGE flow: drop the existing status-4 draft before re-saving
    " (WebDynpro ONACTIONSAVE_INDENT, LV_ZT2 = 'X' branch)
    IF lv_update = abap_true.
      DELETE FROM zsd_cust_indent
        WHERE begda = ls_in-begda AND vehicle = ls_in-vehicle
          AND depot = lv_plant AND ztt_status = '4'.
    ENDIF.

    " indent already available for the vehicle/date/depot
    "  mirror WebDynpro ONACTIONSAVE_INDENT (out.txt 6234-6251):
    "  a blank-SHNUMBER draft blocks; otherwise an existing indent whose
    "  assigned shipment is still in progress (OIGS-OIG_SSTSF < 6) blocks too.
    DATA lv_exists TYPE i.
    SELECT COUNT(*) FROM zsd_cust_indent INTO lv_exists
      WHERE begda = ls_in-begda AND vehicle = ls_in-vehicle
        AND depot = lv_plant AND shnumber = ' '.
    IF lv_exists > 0.
      raise_busi( 'Indent already available for the vehicle.' ).
    ELSE.
      DATA lv_shnum TYPE zsd_cust_indent-shnumber.
      SELECT SINGLE shnumber FROM zsd_cust_indent INTO lv_shnum      "#EC CI_NOORDER
        WHERE begda = ls_in-begda AND vehicle = ls_in-vehicle AND depot = lv_plant.
      IF lv_shnum IS NOT INITIAL.
        DATA lv_sstsf TYPE oigs-oig_sstsf.
        SELECT SINGLE oig_sstsf FROM oigs INTO lv_sstsf WHERE shnumber = lv_shnum.
        IF sy-subrc = 0 AND lv_sstsf < 6.
          raise_busi( 'Indent already available for the vehicle.' ).
        ENDIF.
      ENDIF.
    ENDIF.

    " qty <= compartment capacity (ONACTIONCHECK_QUANTITY)
    DATA: lv_c1 TYPE char12, lv_c2 TYPE char12, lv_c3 TYPE char12, lv_c4 TYPE char12,
          lv_c5 TYPE char12, lv_c6 TYPE char12, lv_c7 TYPE char12, lv_c8 TYPE char12,
          lt_oigcc TYPE TABLE OF oigcc.
    CALL FUNCTION 'Z_GET_COMP_CAPACITY'
      EXPORTING vehicle   = ls_in-vehicle
      IMPORTING capacity1 = lv_c1 capacity2 = lv_c2 capacity3 = lv_c3 capacity4 = lv_c4
                capacity5 = lv_c5 capacity6 = lv_c6 capacity7 = lv_c7 capacity8 = lv_c8
      TABLES    itab_oigcc = lt_oigcc.

    DATA: lv_capn TYPE p DECIMALS 3, lv_qtyn TYPE p DECIMALS 3, lv_capc TYPE char12.
    DO 8 TIMES.
      lv_idx = sy-index.
      ASSIGN COMPONENT |QUAN_COMP{ lv_idx }| OF STRUCTURE ls_in TO FIELD-SYMBOL(<q>).
      CASE lv_idx.
        WHEN 1. lv_capc = lv_c1. WHEN 2. lv_capc = lv_c2. WHEN 3. lv_capc = lv_c3. WHEN 4. lv_capc = lv_c4.
        WHEN 5. lv_capc = lv_c5. WHEN 6. lv_capc = lv_c6. WHEN 7. lv_capc = lv_c7. WHEN 8. lv_capc = lv_c8.
      ENDCASE.
      IF <q> IS NOT INITIAL.
        CALL FUNCTION 'MOVE_CHAR_TO_NUM' EXPORTING chr = <q>     IMPORTING num = lv_qtyn.
        CALL FUNCTION 'MOVE_CHAR_TO_NUM' EXPORTING chr = lv_capc IMPORTING num = lv_capn.
        IF lv_capn > 0 AND lv_qtyn > lv_capn.
          raise_busi( 'Indent quantity cannot be more than compartment capacity.' ).
        ENDIF.
      ENDIF.
    ENDDO.

    " ---------- numeric compartment quantities ----------------------
    "  (reused by the contract-balance, ethanol and bulk-order checks)
    DATA: lv_qty1 TYPE p DECIMALS 3, lv_qty2 TYPE p DECIMALS 3,
          lv_qty3 TYPE p DECIMALS 3, lv_qty4 TYPE p DECIMALS 3,
          lv_qty5 TYPE p DECIMALS 3, lv_qty6 TYPE p DECIMALS 3,
          lv_qty7 TYPE p DECIMALS 3, lv_qty8 TYPE p DECIMALS 3,
          lv_qsum TYPE p DECIMALS 3, lv_qnum TYPE p DECIMALS 3.
    CLEAR lv_qsum.
    DO 8 TIMES.
      lv_idx = sy-index.
      ASSIGN COMPONENT |QUAN_COMP{ lv_idx }| OF STRUCTURE ls_in TO FIELD-SYMBOL(<qn>).
      CLEAR lv_qnum.
      IF <qn> IS NOT INITIAL.
        CALL FUNCTION 'MOVE_CHAR_TO_NUM' EXPORTING chr = <qn> IMPORTING num = lv_qnum.
      ENDIF.
      CASE lv_idx.
        WHEN 1. lv_qty1 = lv_qnum. WHEN 2. lv_qty2 = lv_qnum.
        WHEN 3. lv_qty3 = lv_qnum. WHEN 4. lv_qty4 = lv_qnum.
        WHEN 5. lv_qty5 = lv_qnum. WHEN 6. lv_qty6 = lv_qnum.
        WHEN 7. lv_qty7 = lv_qnum. WHEN 8. lv_qty8 = lv_qnum.
      ENDCASE.
      lv_qsum = lv_qsum + lv_qnum.
    ENDDO.

    " ---------- contract balance quantity check (WAX/SUL/RPC/CPC) ---
    "  WebDynpro: ZSD_INDENT_NVEH -> VBAP (ordered) minus VBFA (delivered)
    DATA: lv_vbeln  TYPE vbeln,
          zblk_ord  TYPE char10,
          znveh_ind TYPE zsd_indent_nveh.
    lv_vbeln = ls_in-contract.
    CONDENSE lv_vbeln.
    IF lv_vbeln IS NOT INITIAL
       AND ( ls_in-prod_cmp1(4) = 'PWAX' OR ls_in-prod_cmp2(4) = 'PWAX'
          OR ls_in-prod_cmp3(4) = 'PWAX' OR ls_in-prod_cmp4(4) = 'PWAX'
          OR ls_in-prod_cmp5(4) = 'PWAX' OR ls_in-prod_cmp6(4) = 'PWAX'
          OR ls_in-prod_cmp1(4) = 'SUL0' OR ls_in-prod_cmp1(4) = 'RPC0'
          OR ls_in-prod_cmp1(4) = 'CPC0' ).
      SELECT SINGLE * FROM zsd_indent_nveh INTO znveh_ind WHERE order_no = lv_vbeln.
      IF sy-subrc = 0.
        zblk_ord = lv_vbeln.
        " bulk-order balance guard (WebDynpro ONACTIONCHECK_QUANTITY,
        "  out.txt 3544-3567): comp-1 qty must not exceed the remaining
        "  open-order balance (BL_QTY1 stored in KL, compared in litres).
        IF znveh_ind-ord_closed = space
           AND lv_qty1 > znveh_ind-bl_qty1 * 1000.
          DATA lv_balmsg TYPE string.
          lv_balmsg = znveh_ind-bl_qty1. CONDENSE lv_balmsg.
          CONCATENATE 'Order balance =' lv_balmsg
                      'is less than indent quantity. You may close the order.'
                 INTO lv_balmsg SEPARATED BY space.
          raise_busi( lv_balmsg ).
        ENDIF.
        lv_vbeln = znveh_ind-contract1.
      ENDIF.
      DATA: lv_tqty  TYPE vbfa-rfmng,
            lv_tuom  TYPE vbap-zieme,
            lv_posnr TYPE vbap-posnr,
            lv_eqty  TYPE vbfa-rfmng,
            lv_rqty  TYPE vbfa-rfmng.
      CLEAR: lv_tqty, lv_tuom, lv_posnr, lv_eqty, lv_rqty.
      SELECT SINGLE zmeng zieme posnr FROM vbap                      "#EC CI_NOORDER
        INTO ( lv_tqty, lv_tuom, lv_posnr )
        WHERE vbeln = lv_vbeln AND matnr = ls_in-prod_cmp1.
      SELECT SUM( rfmng_flo ) FROM vbfa INTO lv_eqty
        WHERE vbelv = lv_vbeln AND vbtyp_n = 'C' AND posnv = lv_posnr.
      lv_rqty = lv_tqty - lv_eqty.
      IF lv_rqty < lv_qsum.
        raise_busi( 'Balance quantity in the contract is not sufficient' ).
      ENDIF.
    ENDIF.

    " ---------- SKO / MTO : same material in every compartment ------
    DATA lv_zproduct TYPE matnr.
    CLEAR lv_zproduct.
    DO 8 TIMES.
      ASSIGN COMPONENT |PROD_CMP{ sy-index }| OF STRUCTURE ls_in TO FIELD-SYMBOL(<sp>).
      IF <sp> = 'SKO01' OR <sp> = 'SKO02' OR <sp> = 'MTO01'.
        lv_zproduct = <sp>.
      ENDIF.
    ENDDO.
    IF lv_zproduct IS NOT INITIAL.
      DATA lv_prderr TYPE abap_bool.
      CLEAR lv_prderr.
      DO lv_cnt TIMES.
        lv_idx = sy-index.
        IF lv_idx > 8. EXIT. ENDIF.
        ASSIGN COMPONENT |PROD_CMP{ lv_idx }| OF STRUCTURE ls_in TO FIELD-SYMBOL(<cp>).
        IF <cp> <> ls_in-prod_cmp1.
          lv_prderr = abap_true.
        ENDIF.
      ENDDO.
      IF lv_prderr = abap_true.
        raise_busi( 'Please select the same material for all compartments' ).
      ENDIF.
    ENDIF.

    " ---------- build ZSD_CUST_INDENT record ------------------------
    DATA ls_ind TYPE zsd_cust_indent.
    CLEAR ls_ind.
    ls_ind-begda        = ls_in-begda.
    ls_ind-vehicle      = ls_in-vehicle.
    ls_ind-depot        = lv_plant.
    ls_ind-indent_date  = sy-datum.
    ls_ind-indent_time  = sy-uzeit.
    ls_ind-cust_user_id = lv_uname.
    ls_ind-kunnr        = ls_in-kunnr.
    ls_ind-kdgrp        = lv_kdgrp.
    ls_ind-shtype       = COND #( WHEN lv_vtype = 'TTV' OR lv_vtype = 'ATF'
                                    OR lv_vtype = 'WOIL' OR lv_vtype = 'TTVM'
                                  THEN '1111' ELSE '1112' ).
    ls_ind-atf_flush      = ls_in-atf_flush.
    ls_ind-flush_reason   = ls_in-flush_reason.
    ls_ind-tpt_gstn       = ls_in-tpt_gstn(15).
    ls_ind-ms_end_use     = ls_in-ms_end_use.
    ls_ind-hsd_end_use    = ls_in-hsd_end_use.
    ls_ind-contract       = COND #( WHEN lv_vbeln = 'IN' OR lv_vbeln = 'EP'
                                    THEN space ELSE lv_vbeln ).
    ls_ind-kondm          = COND #( WHEN lv_vbeln = 'IN' OR lv_vbeln = 'EP'
                                    THEN lv_vbeln ELSE space ).
    ls_ind-ztt_status      = '4'.
    ls_ind-ztt_status_desc = 'Indent Saved'.
    ls_ind-indent_type     = 'PORTAL'.
    ls_ind-zdelete         = 'Y'.

    " default valuation by plant / contract
    DATA lv_val TYPE bwtar_d.
    lv_val = COND #( WHEN lv_plant = '3100' THEN 'OWN-BOND' ELSE 'OWN-DTPD' ).
    IF lv_plant <> '3100' AND lv_vbeln = 'EP'. lv_val = 'OWN-NILDTY'. ENDIF.
    IF lv_plant <> '3100' AND lv_vbeln = 'IN'. lv_val = 'OWN-DTPDIN'. ENDIF.

    " customer/depot mapping - drives the ZDESP_STOCK_PLNT valuation
    DATA ls_cust_map TYPE zsd_cust_usr_map.
    SELECT SINGLE * FROM zsd_cust_usr_map INTO ls_cust_map           "#EC CI_NOORDER
      WHERE cust_user_id = lv_uname AND depot = lv_plant.

    " products + quantities (append UOM) + per-compartment valuation:
    "   (1) default lv_val
    "   (2) ZDESP_STOCK_PLNT override (customer-specific, ZCUST_MAP-KUNNR)
    "   (3) ZSET_MAT_VALTYPE override (plant/material)
    DATA lv_uom TYPE char3.
    lv_uom = veh_uom( lv_vtype ).
    DATA: lv_qc      TYPE char16,
          lv_val_new TYPE bwtar_d.
    DO 8 TIMES.
      lv_idx = sy-index.
      ASSIGN COMPONENT |PROD_CMP{ lv_idx }| OF STRUCTURE ls_in  TO FIELD-SYMBOL(<ip>).
      ASSIGN COMPONENT |QUAN_COMP{ lv_idx }| OF STRUCTURE ls_in TO FIELD-SYMBOL(<iq>).
      ASSIGN COMPONENT |PROD_CMP{ lv_idx }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<op>).
      ASSIGN COMPONENT |QUAN_COMP{ lv_idx }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<oq>).
      ASSIGN COMPONENT |VAL_COMP{ lv_idx }| OF STRUCTURE ls_ind  TO FIELD-SYMBOL(<ov>).
      <op> = <ip>.
      IF <ip> IS NOT INITIAL.
        lv_qc = <iq>. CONDENSE lv_qc.
        IF lv_uom IS NOT INITIAL.
          CONCATENATE lv_qc lv_uom INTO lv_qc.
        ENDIF.
        <oq> = lv_qc.
        " (2) customer-specific valuation from ZDESP_STOCK_PLNT
        CLEAR lv_val_new.
        SELECT SINGLE valuation FROM zdesp_stock_plnt INTO lv_val_new
          WHERE plant = lv_plant AND customer = ls_cust_map-kunnr AND matnr = <ip>.
        <ov> = COND #( WHEN lv_val_new IS NOT INITIAL THEN lv_val_new ELSE lv_val ).
        " (3) plant/material valuation override from ZSET_MAT_VALTYPE
        SELECT SINGLE val_type FROM zset_mat_valtype INTO @DATA(lv_vt)
          WHERE plant = @lv_plant AND matnr = @<ip>.
        IF sy-subrc = 0. <ov> = lv_vt. ENDIF.
      ELSE.
        CLEAR <ov>.
      ENDIF.
    ENDDO.

    " ---------- per-SPART summary columns (H1) ----------------------
    "  Aggregate each compartment quantity by division into the LPG/MS/
    "  ATF/... columns (mirror of WebDynpro out.txt 994-1018). These are
    "  the values SELECT SUM( <col> ) reads back for the plan cap, and
    "  they must be written before both the check below and the INSERT.
    CLEAR: ls_ind-lpg, ls_ind-ms,  ls_ind-atf,  ls_ind-sko,  ls_ind-hsd,
           ls_ind-arhsd, ls_ind-pwax, ls_ind-mto, ls_ind-rpc, ls_ind-sul,
           ls_ind-ntg, ls_ind-other.
    DATA: lv_sqc TYPE char16,
          lv_sn  TYPE p LENGTH 8 DECIMALS 3,
          lv_ssp TYPE spart.
    DO 8 TIMES.
      lv_idx = sy-index.
      ASSIGN COMPONENT |PROD_CMP{ lv_idx }| OF STRUCTURE ls_in  TO <sp>.
      ASSIGN COMPONENT |QUAN_COMP{ lv_idx }| OF STRUCTURE ls_in TO FIELD-SYMBOL(<sq>).
      IF <sp> IS INITIAL. CONTINUE. ENDIF.
      lv_sqc = <sq>. CONDENSE lv_sqc.
      CALL FUNCTION 'MOVE_CHAR_TO_NUM' EXPORTING chr = lv_sqc IMPORTING num = lv_sn.
      SELECT SINGLE spart FROM mara INTO lv_ssp WHERE matnr = <sp>.  "#EC CI_NOORDER
      CASE lv_ssp.
        WHEN '10'. ls_ind-lpg  = ls_ind-lpg  + lv_sn.
        WHEN '25'. ls_ind-ms   = ls_ind-ms   + lv_sn.
        WHEN '30'. ls_ind-atf  = ls_ind-atf  + lv_sn.
        WHEN '35'. ls_ind-sko  = ls_ind-sko  + lv_sn.
        WHEN '40'.
          IF <sp>+0(5) = 'HSDAR'. ls_ind-arhsd = ls_ind-arhsd + lv_sn.
          ELSE.                   ls_ind-hsd   = ls_ind-hsd   + lv_sn.  ENDIF.
        WHEN '50'. ls_ind-pwax = ls_ind-pwax + lv_sn.
        WHEN '60'. ls_ind-mto  = ls_ind-mto  + lv_sn.
        WHEN '80'. ls_ind-rpc  = ls_ind-rpc  + lv_sn.
        WHEN '85'. ls_ind-ntg  = ls_ind-ntg  + lv_sn.
        WHEN '90'. ls_ind-sul  = ls_ind-sul  + lv_sn.
        WHEN OTHERS. ls_ind-other = ls_ind-other + lv_sn.
      ENDCASE.
    ENDDO.

    " qty-vs-plan check (EXECUTE_Z_INDENT_QTY_CHECK)
    IF qty_plan_check( ls_ind ) = 'X'.
      raise_busi( 'Indent quantity exceeded from plan.' ).
    ENDIF.

    " ---------- end-use driven product group / valuation ------------
    "  (WebDynpro: DD07T domain ZIND_END_USE -> KONDM / KONDM2 + value)
    DATA: lv_dval       TYPE domvalue_l,
          lv_prgrp_ms   TYPE kondm,
          lv_prdval_ms  TYPE bwtar_d,
          lv_prgrp_hsd  TYPE kondm,
          lv_prdval_hsd TYPE bwtar_d,
          lv_use_ms     TYPE c LENGTH 100,
          lv_use_hsd    TYPE c LENGTH 100.
    lv_use_ms  = ls_in-ms_end_use.
    lv_use_hsd = ls_in-hsd_end_use.

    IF lv_use_ms IS NOT INITIAL.
      CLEAR lv_dval.
      SELECT SINGLE domvalue_l FROM dd07t INTO lv_dval
        WHERE domname = 'ZIND_END_USE' AND ddtext = lv_use_ms+3(97).
      IF lv_dval(4) = 'NORM'.
        lv_prdval_ms = COND #( WHEN lv_plant = '3100' THEN 'OWN-BOND'
                               WHEN lv_plant = '3202' THEN 'OWN-DTPD' ELSE lv_prdval_ms ).
      ELSEIF lv_dval(4) = 'BRND'.
        lv_prdval_ms = COND #( WHEN lv_plant = '3100' THEN 'OWN-BONDBR'
                               WHEN lv_plant = '3202' THEN 'OWN-DTPDBR' ELSE lv_prdval_ms ).
      ENDIF.
      IF lv_dval+5(5) = 'BLND'.       CLEAR lv_prgrp_ms.
      ELSEIF lv_dval+5(5) = 'NBLND'.  lv_prgrp_ms = 'AD'.
      ENDIF.
    ENDIF.

    IF lv_use_hsd IS NOT INITIAL.
      CLEAR lv_dval.
      SELECT SINGLE domvalue_l FROM dd07t INTO lv_dval
        WHERE domname = 'ZIND_END_USE' AND ddtext = lv_use_hsd+4(96).
      IF lv_dval(4) = 'NORM'.
        lv_prdval_hsd = COND #( WHEN lv_plant = '3100' THEN 'OWN-BOND'
                                WHEN lv_plant = '3202' THEN 'OWN-DTPD' ELSE lv_prdval_hsd ).
      ELSEIF lv_dval(4) = 'BRND'.
        lv_prdval_hsd = COND #( WHEN lv_plant = '3100' THEN 'OWN-BONDBR'
                                WHEN lv_plant = '3202' THEN 'OWN-DTPDBR' ELSE lv_prdval_hsd ).
      ENDIF.
      IF lv_dval+5(5) = 'BLND'.       CLEAR lv_prgrp_hsd.
      ELSEIF lv_dval+5(5) = 'NBLND'.  lv_prgrp_hsd = 'AD'.
      ENDIF.
    ENDIF.

    " MS06 / HSD06 : mandatory end-use + KONDM/KONDM2 + valuation (date gated)
    DATA: lv_raise_err TYPE abap_bool,
          lv_valchg    TYPE abap_bool,
          lv_n         TYPE i.
    IF ls_ind-kondm IS INITIAL.
      IF ls_ind-begda >= '20221101'.
        IF lv_use_ms IS INITIAL.
          lv_n = 0.
          DO 8 TIMES.
            ASSIGN COMPONENT |PROD_CMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<mp>).
            IF <mp> = 'MS06'. lv_n = lv_n + 1. ENDIF.
          ENDDO.
          IF lv_n > 0. lv_raise_err = abap_true. ELSE. ls_ind-kondm = lv_prgrp_ms. ENDIF.
        ELSE.
          ls_ind-kondm = lv_prgrp_ms.
        ENDIF.
        CLEAR lv_valchg.
        SELECT COUNT(*) FROM zdesp_stock_plnt
          WHERE plant = lv_plant AND matnr = 'MS06' AND customer = ls_cust_map-kunnr.
        IF sy-subrc = 0. lv_valchg = abap_true. ENDIF.
        IF lv_valchg = abap_false.
          DO 8 TIMES.
            ASSIGN COMPONENT |PROD_CMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<mp2>).
            ASSIGN COMPONENT |VAL_COMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<mv>).
            IF <mp2> = 'MS06'. <mv> = lv_prdval_ms. ENDIF.
          ENDDO.
        ENDIF.
      ENDIF.
      IF ls_ind-begda >= '20280401'.
        IF lv_use_hsd IS INITIAL.
          lv_n = 0.
          DO 8 TIMES.
            ASSIGN COMPONENT |PROD_CMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<hp>).
            IF <hp> = 'HSD06'. lv_n = lv_n + 1. ENDIF.
          ENDDO.
          IF lv_n > 0. lv_raise_err = abap_true. ELSE. ls_ind-kondm2 = lv_prgrp_hsd. ENDIF.
        ELSE.
          ls_ind-kondm2 = lv_prgrp_hsd.
        ENDIF.
        CLEAR lv_valchg.
        SELECT COUNT(*) FROM zdesp_stock_plnt
          WHERE plant = lv_plant AND matnr = 'HSD06' AND customer = ls_cust_map-kunnr.
        IF sy-subrc = 0. lv_valchg = abap_true. ENDIF.
        IF lv_valchg = abap_false.
          DO 8 TIMES.
            ASSIGN COMPONENT |PROD_CMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<hp2>).
            ASSIGN COMPONENT |VAL_COMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<hv>).
            IF <hp2> = 'HSD06'. <hv> = lv_prdval_hsd. ENDIF.
          ENDDO.
        ENDIF.
      ENDIF.
    ENDIF.
    IF lv_raise_err = abap_true.
      raise_busi( 'Please select end use' ).
    ENDIF.

    " store end-use text on the record
    ls_ind-ms_end_use  = ls_in-ms_end_use.
    ls_ind-hsd_end_use = ls_in-hsd_end_use.

    " ---------- multi-source ethanol remap / stock check ------------
    "  (WebDynpro: ZEBMS_SRS source, ZEBMS_MAT_MAP material remap)
    DATA: ls_zknvv  TYPE knvv,
          ls_zsrc   TYPE zebms_srs,
          ls_matmap TYPE zebms_mat_map,
          lv_source TYPE zebms_srs-zebms_source.
    SELECT SINGLE * FROM knvv INTO ls_zknvv                          "#EC CI_NOORDER
      WHERE kunnr = ls_ind-kunnr AND vtweg = '10' AND spart = '25'.
    SELECT SINGLE * FROM zebms_srs INTO ls_zsrc
      WHERE werks_d = ls_ind-depot AND kdgrp = ls_zknvv-kdgrp.
    lv_source = COND #( WHEN sy-subrc = 0 THEN ls_zsrc-zebms_source ELSE 'HOSP' ).

    IF lv_source <> 'HOSP'.
      ls_ind-ztran = lv_source.
      DO 8 TIMES.
        ASSIGN COMPONENT |PROD_CMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<ep>).
        ASSIGN COMPONENT |VAL_COMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<ev>).
        IF <ep> IS INITIAL. CONTINUE. ENDIF.
        SELECT SINGLE * FROM zebms_mat_map INTO ls_matmap WHERE hosp_mat = <ep>.
        IF sy-subrc = 0.
          <ep> = ls_matmap-own_mat.
          IF lv_source = 'ABRPL'. <ev> = 'OWN-ABRPL'. ENDIF.
          IF lv_source = 'NRL' AND ls_matmap-hosp_mat(6) = '(BRND)'.
            CONCATENATE <ev> 'BR' INTO <ev>.
          ENDIF.
        ELSE.
          SELECT SINGLE * FROM zebms_mat_map INTO ls_matmap WHERE hosp_mat = <ep>+6(12).
          IF sy-subrc = 0 AND <ep>(6) = '(BRND)'.
            <ep> = ls_matmap-own_mat.
            <ev> = 'OWN-ABRPLBR'.
          ENDIF.
        ENDIF.
      ENDDO.
    ELSE.
      " HOSP source - ethanol stock availability check
      ls_ind-ztran = 'HOSP'.
      DATA: lv_stk_err TYPE char1,
            lv_err_msg TYPE string,
            lv_e1 TYPE labst, lv_e2 TYPE labst, lv_e3 TYPE labst, lv_e4 TYPE labst,
            lv_e5 TYPE labst, lv_e6 TYPE labst, lv_e7 TYPE labst, lv_e8 TYPE labst.
      lv_e1 = lv_qty1. lv_e2 = lv_qty2. lv_e3 = lv_qty3. lv_e4 = lv_qty4.
      lv_e5 = lv_qty5. lv_e6 = lv_qty6. lv_e7 = lv_qty7. lv_e8 = lv_qty8.
      CALL FUNCTION 'Z_ETHANOL_INDENT_STK_CHECK'
        EXPORTING cust_indent = ls_ind
                  c1_qt = lv_e1 c2_qt = lv_e2 c3_qt = lv_e3 c4_qt = lv_e4
                  c5_qt = lv_e5 c6_qt = lv_e6 c7_qt = lv_e7 c8_qt = lv_e8
        IMPORTING err_msg = lv_err_msg zstk_err = lv_stk_err.
      IF lv_stk_err = 'X'.
        raise_busi( CONV string( lv_err_msg ) ).
      ENDIF.
    ENDIF.

    " ---------- AD additive valuation (ZINDENT_CUSSTOCK) ------------
    IF lv_prgrp_ms = 'AD' OR ls_in-hsd_end_use = 'AD'.
      DO 8 TIMES.
        ASSIGN COMPONENT |PROD_CMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<ap>).
        ASSIGN COMPONENT |VAL_COMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<av>).
        IF <ap> IS INITIAL. CONTINUE. ENDIF.
        SELECT SINGLE val_type FROM zindent_cusstock INTO @DATA(lv_adval)
          WHERE plant = @ls_ind-depot AND kdgrp = @ls_ind-kdgrp AND matnr = @<ap>.
        IF sy-subrc = 0. <av> = lv_adval. ENDIF.
      ENDDO.
    ENDIF.

    " ---------- (BRND) product stripping + 'BR' valuation suffix -----
    IF ls_in-ms_end_use IS INITIAL.
      DO 8 TIMES.
        ASSIGN COMPONENT |PROD_CMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<bp>).
        ASSIGN COMPONENT |VAL_COMP{ sy-index }| OF STRUCTURE ls_ind TO FIELD-SYMBOL(<bv>).
        IF <bp>(6) = '(BRND)'.
          <bp> = <bp>+6(20).
          CONCATENATE <bv> 'BR' INTO <bv>.
        ENDIF.
      ENDDO.
    ENDIF.

    " ---------- bulk-order linkage (ZSD_INDENT_NVEH) ----------------
    IF znveh_ind-order_no IS NOT INITIAL.
      DATA lv_bulk TYPE p DECIMALS 3.
      lv_bulk = lv_qty1 / 1000.
      znveh_ind-bl_qty1 = znveh_ind-bl_qty1 - lv_bulk.
      ls_ind-bulk_qty   = lv_bulk.
    ENDIF.
    ls_ind-bulk_order = zblk_ord.

    " ---------- persist ---------------------------------------------
    INSERT zsd_cust_indent FROM ls_ind.
    IF sy-subrc <> 0.
      raise_busi( 'Indent could not be saved (duplicate key).' ).
    ENDIF.
    IF znveh_ind-order_no IS NOT INITIAL.
      MODIFY zsd_indent_nveh FROM znveh_ind.
    ENDIF.

    " ---------- response entity (MUST carry every SaveIndent field, --
    "            or the POST response Simple Transformation dumps with --
    "            CX_ST_REF_ACCESS even though the row was inserted) -----
    DATA: BEGIN OF ls_out,
            begda           TYPE c LENGTH 10,
            endda           TYPE c LENGTH 10,
            shnumber        TYPE zsd_cust_indent-shnumber,
            vehicle         TYPE oig_vhlnmr,
            depot           TYPE werks_d,
            indent_date     TYPE c LENGTH 10,
            indent_time     TYPE c LENGTH 8,
            cust_user_id    TYPE xubname,
            kunnr           TYPE kunnr,
            kunnr_desc      TYPE char30,
            shtype          TYPE zsd_cust_indent-shtype,
            kondm           TYPE zsd_cust_indent-kondm,
            prod_cmp1 TYPE matnr, val_comp1 TYPE bwtar_d, quan_comp1 TYPE c LENGTH 16,
            prod_cmp2 TYPE matnr, val_comp2 TYPE bwtar_d, quan_comp2 TYPE c LENGTH 16,
            prod_cmp3 TYPE matnr, val_comp3 TYPE bwtar_d, quan_comp3 TYPE c LENGTH 16,
            prod_cmp4 TYPE matnr, val_comp4 TYPE bwtar_d, quan_comp4 TYPE c LENGTH 16,
            prod_cmp5 TYPE matnr, val_comp5 TYPE bwtar_d, quan_comp5 TYPE c LENGTH 16,
            prod_cmp6 TYPE matnr, val_comp6 TYPE bwtar_d, quan_comp6 TYPE c LENGTH 16,
            prod_cmp7 TYPE matnr, val_comp7 TYPE bwtar_d, quan_comp7 TYPE c LENGTH 16,
            prod_cmp8 TYPE matnr, val_comp8 TYPE bwtar_d, quan_comp8 TYPE c LENGTH 16,
            summary         TYPE c LENGTH 200,
            ztt_status      TYPE zsd_cust_indent-ztt_status,
            ztt_status_desc TYPE zsd_cust_indent-ztt_status_desc,
            atf_flush       TYPE c LENGTH 1,
            chk             TYPE c LENGTH 1,
            contract        TYPE zsd_cust_indent-contract,
            hsd  TYPE f, arhsd TYPE f, ms TYPE f, atf TYPE f, sko TYPE f,
            mto  TYPE f, lpg   TYPE f, pwax TYPE f, sul TYPE f, rpc TYPE f,
            cpc  TYPE f, ntg   TYPE f, other TYPE f,
            kdgrp           TYPE kdgrp,
            indent_type     TYPE zsd_cust_indent-indent_type,
            tpt_gstn        TYPE zsd_cust_indent-tpt_gstn,
            flush_reason    TYPE zsd_cust_indent-flush_reason,
            error           TYPE zsd_cust_indent-error,
            zdelete         TYPE zsd_cust_indent-zdelete,
            delv_chaln      TYPE c LENGTH 10,
            hosp_delv       TYPE c LENGTH 10,
            ztran           TYPE zsd_cust_indent-ztran,
            kondm2          TYPE c LENGTH 10,
            ms_end_use      TYPE zsd_cust_indent-ms_end_use,
            hsd_end_use     TYPE c LENGTH 70,
            bulk_order      TYPE c LENGTH 10,
            bulk_qty        TYPE p LENGTH 7 DECIMALS 3,
            smtp_addr       TYPE ad_smtpadr,
          END OF ls_out.

    MOVE-CORRESPONDING ls_ind TO ls_out.
    ls_out-kunnr_desc = ls_in-kunnr_desc.
    ls_out-smtp_addr  = ls_in-smtp_addr.
    CLEAR ls_out-error.
    copy_data_to_ref( EXPORTING is_data = ls_out CHANGING cr_data = er_entity ).

  ENDMETHOD.


  "===================================================================
  "  HELPERS
  "===================================================================
  METHOD get_filter_value.
    DATA lt_so TYPE /iwbep/t_mgw_select_option.
    DATA ls_r  TYPE /iwbep/s_cod_select_option.
    TRY.
        lt_so = io_request->get_filter( )->get_filter_select_options( ).
      CATCH cx_root.
        RETURN.
    ENDTRY.
    READ TABLE lt_so INTO DATA(ls_so) WITH KEY property = iv_property.
    IF sy-subrc = 0.
      READ TABLE ls_so-select_options INTO ls_r INDEX 1.
      IF sy-subrc = 0. rv_value = ls_r-low. ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD get_user_scope.
    " WDDOINIT / EXECUTE_Z_GET_CUSTOMER_INDENT customer + depot derivation
    DATA: lt_map  TYPE TABLE OF zsd_cust_usr_map,
          ls_map  TYPE zsd_cust_usr_map,
          lv_kdg  TYPE knvv-kdgrp,
          lt_knvv TYPE TABLE OF knvv,
          ls_knvv TYPE knvv,
          lt_knvp TYPE TABLE OF knvp,
          ls_knvp TYPE knvp.

    SELECT * FROM zsd_cust_usr_map INTO TABLE lt_map WHERE cust_user_id = iv_uname.

    " M10: WD reads ZTABCUST INDEX 1 in raw (unsorted) map order (out.txt 595);
    " capture it before et_depot is sorted so callers can replicate that scope.
    READ TABLE lt_map INTO ls_map INDEX 1.
    IF sy-subrc = 0. ev_first_depot = ls_map-depot. ENDIF.

    LOOP AT lt_map INTO ls_map.
      APPEND ls_map-depot TO et_depot.

      CLEAR lv_kdg.
      SELECT SINGLE kdgrp FROM knvv INTO lv_kdg WHERE kunnr = ls_map-kunnr. "#EC CI_NOORDER
      REFRESH lt_knvv.
      IF lv_kdg <> 'DI' AND lv_kdg <> 'RE' AND lv_kdg <> 'TG'
         AND lv_kdg <> 'OI' AND lv_kdg <> 'EX'.
        SELECT * FROM knvv INTO TABLE lt_knvv
          WHERE kdgrp = lv_kdg AND spart <> '11'
            AND kdgrp <> 'DI' AND kdgrp <> 'TG' AND kdgrp <> 'OI' AND kdgrp <> 'RE'.
      ELSE.
        SELECT * FROM knvv INTO TABLE lt_knvv
          WHERE kunnr = ls_map-kunnr AND spart <> '11'.
      ENDIF.
      SORT lt_knvv BY kunnr.
      DELETE ADJACENT DUPLICATES FROM lt_knvv COMPARING kunnr.

      LOOP AT lt_knvv INTO ls_knvv.
        SELECT * FROM knvp INTO TABLE lt_knvp
          WHERE kunnr = ls_knvv-kunnr AND parvw = 'WE' AND vtweg <> '11'.
        LOOP AT lt_knvp INTO ls_knvp.
          APPEND ls_knvp-kunn2 TO et_kunnr.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    SORT et_kunnr. DELETE ADJACENT DUPLICATES FROM et_kunnr.
    SORT et_depot. DELETE ADJACENT DUPLICATES FROM et_depot.

    " ---- depot-conditioned special ship-to exclusions (M1) --------
    " WD WDDOINIT (out.txt 2723-2731): 0000100036 is valid only where a
    " '3100' depot is mapped; 0000100192-195 only where '3202' is mapped.
    " Applied after the KUNN2 set is built so wrong-depot users cannot
    " select (and therefore save/submit against) these customers.
    " et_kunnr/et_depot are generic STANDARD TABLE, so the WHERE / WITH KEY
    " operations run on typed local copies (row type must be static).
    DATA: lt_scope_k TYPE STANDARD TABLE OF kunnr,
          lt_scope_d TYPE STANDARD TABLE OF werks_d.
    lt_scope_k = et_kunnr.
    lt_scope_d = et_depot.

    READ TABLE lt_scope_d TRANSPORTING NO FIELDS WITH KEY table_line = '3100'.
    IF sy-subrc <> 0.
      DELETE lt_scope_k WHERE table_line = '0000100036'.
    ENDIF.
    READ TABLE lt_scope_d TRANSPORTING NO FIELDS WITH KEY table_line = '3202'.
    IF sy-subrc <> 0.
      DELETE lt_scope_k WHERE table_line = '0000100192'.
      DELETE lt_scope_k WHERE table_line = '0000100193'.
      DELETE lt_scope_k WHERE table_line = '0000100194'.
      DELETE lt_scope_k WHERE table_line = '0000100195'.
    ENDIF.

    et_kunnr = lt_scope_k.
  ENDMETHOD.


  METHOD veh_uom.
    CASE iv_veh_type.
      WHEN 'ATF' OR 'TTV' OR 'WOIL' OR 'TTVM'. rv_uom = 'KL'.
      WHEN 'OPTR' OR 'LPGB'.                   rv_uom = 'KG'.
      WHEN OTHERS.                             CLEAR rv_uom.
    ENDCASE.
  ENDMETHOD.


  METHOD qty_plan_check.
    " Port of EXECUTE_Z_INDENT_QTY_CHECK: compare summed indent qty per
    " product group against the plan in ZPROD_GRP_INDENT.
    " Returns 'X' when any group exceeds its (customer / group / total) plan.
    rv_error = ''.

    TYPES: BEGIN OF ty_pq,
             material TYPE char10,
             spart    TYPE spart,
             qty      TYPE p LENGTH 8 DECIMALS 3,
           END OF ty_pq.
    DATA lt_pq TYPE TABLE OF ty_pq.

    DATA: lv_i TYPE i, lv_qc TYPE char16, lv_num TYPE p DECIMALS 3,
          lv_prod TYPE matnr, lv_spart TYPE spart, lv_lng TYPE i.

    DO 8 TIMES.
      lv_i = sy-index.
      ASSIGN COMPONENT |PROD_CMP{ lv_i }| OF STRUCTURE is_indent TO FIELD-SYMBOL(<p>).
      ASSIGN COMPONENT |QUAN_COMP{ lv_i }| OF STRUCTURE is_indent TO FIELD-SYMBOL(<q>).
      IF <p> IS INITIAL. CONTINUE. ENDIF.
      lv_prod = <p>.
      lv_qc = <q>.
      " strip trailing UOM (KL/KG/..) - keep leading numeric
      lv_lng = strlen( lv_qc ) - 2.
      IF lv_lng > 0. lv_qc = lv_qc(lv_lng). ENDIF.
      CALL FUNCTION 'MOVE_CHAR_TO_NUM' EXPORTING chr = lv_qc IMPORTING num = lv_num.
      SELECT SINGLE spart FROM mara INTO lv_spart WHERE matnr = lv_prod. "#EC CI_NOORDER

      DATA lv_mat TYPE char10.
      CASE lv_spart.
        WHEN '10'. lv_mat = 'LPG'.  WHEN '25'. lv_mat = 'MS'.   WHEN '30'. lv_mat = 'ATF'.
        WHEN '35'. lv_mat = 'SKO'.  WHEN '50'. lv_mat = 'WAX'.  WHEN '60'. lv_mat = 'MTO'.
        WHEN '80'. lv_mat = 'RPC_CPC'. WHEN '85'. lv_mat = 'NTG'. WHEN '90'. lv_mat = 'SUL'.
        WHEN '40'. lv_mat = COND #( WHEN lv_prod(5) = 'HSDAR' THEN 'ARHSD' ELSE 'HSD' ).
        WHEN OTHERS. CLEAR lv_mat.
      ENDCASE.
      IF lv_mat IS INITIAL. CONTINUE. ENDIF.

      READ TABLE lt_pq ASSIGNING FIELD-SYMBOL(<pq>) WITH KEY material = lv_mat.
      IF sy-subrc <> 0.
        APPEND VALUE ty_pq( material = lv_mat spart = lv_spart qty = lv_num ) TO lt_pq.
      ELSE.
        <pq>-qty = <pq>-qty + lv_num.
      ENDIF.
    ENDDO.

    LOOP AT lt_pq ASSIGNING <pq>.
      DATA: lv_plan_c TYPE zprod_grp_indent-quantity,
            lv_plan_g TYPE zprod_grp_indent-quantity,
            lv_plan_t TYPE zprod_grp_indent-quantity.

      " customer-level plan
      SELECT SINGLE quantity FROM zprod_grp_indent INTO lv_plan_c    "#EC CI_NOORDER
        WHERE material = <pq>-material AND customer = is_indent-kunnr
          AND ldate = is_indent-begda AND depot = is_indent-depot.
      IF sy-subrc <> 0.
        SELECT SINGLE quantity FROM zprod_grp_indent INTO lv_plan_c  "#EC CI_NOORDER
          WHERE material = <pq>-material AND customer = is_indent-kunnr
            AND ldate = '00000000' AND depot = is_indent-depot.
      ENDIF.

      " group-level plan
      SELECT SINGLE quantity FROM zprod_grp_indent INTO lv_plan_g
        WHERE material = <pq>-material AND cust_group = is_indent-kdgrp
          AND ldate = is_indent-begda AND depot = is_indent-depot AND customer = ' '.
      IF sy-subrc <> 0.
        SELECT SINGLE quantity FROM zprod_grp_indent INTO lv_plan_g
          WHERE material = <pq>-material AND cust_group = is_indent-kdgrp
            AND ldate = '00000000' AND depot = is_indent-depot AND customer = ' '.
      ENDIF.

      " total plan
      SELECT SINGLE quantity FROM zprod_grp_indent INTO lv_plan_t
        WHERE material = <pq>-material AND cust_group = ' ' AND customer = ' '
          AND ldate = is_indent-begda AND depot = is_indent-depot.
      IF sy-subrc <> 0.
        SELECT SINGLE quantity FROM zprod_grp_indent INTO lv_plan_t  "#EC CI_NOORDER
          WHERE material = <pq>-material AND cust_group = ' ' AND customer = ' '
            AND ldate = '00000000' AND depot = is_indent-depot.
      ENDIF.

      " existing booked qty for the day (customer / group / total).
      " SELECT SUM( <col> ) over the summary column that matches this
      " product group, then add the new indent's qty (WebDynpro out.txt
      " 1028-1148: NCAP1C/NCAP1/NCAPT).
      DATA: lv_bk_c TYPE zsd_cust_indent-hsd,
            lv_bk_g TYPE zsd_cust_indent-hsd,
            lv_bk_t TYPE zsd_cust_indent-hsd,
            lv_col  TYPE string.
      lv_col = SWITCH #( <pq>-material
                         WHEN 'WAX'     THEN 'PWAX'
                         WHEN 'RPC_CPC' THEN 'RPC'
                         ELSE <pq>-material ).
      " The aggregate itself must be the dynamic token — a dynamic column
      " name can't sit inside a static SUM( ), so build "SUM( <col> )" as a
      " string and pass it as the (dynamic) column list. A dynamic column
      " list isn't statically known to be aggregate-only, so ENDSELECT is
      " required (the aggregate yields one row → the loop runs once).
      DATA(lv_agg) = |SUM( { lv_col } )|.
      CLEAR: lv_bk_c, lv_bk_g, lv_bk_t.
      SELECT (lv_agg) FROM zsd_cust_indent INTO @lv_bk_c
        WHERE kunnr = @is_indent-kunnr AND begda = @is_indent-begda
          AND depot = @is_indent-depot.
      ENDSELECT.
      SELECT (lv_agg) FROM zsd_cust_indent INTO @lv_bk_g
        WHERE kdgrp = @is_indent-kdgrp AND begda = @is_indent-begda
          AND depot = @is_indent-depot.
      ENDSELECT.
      SELECT (lv_agg) FROM zsd_cust_indent INTO @lv_bk_t
        WHERE begda = @is_indent-begda AND depot = @is_indent-depot.
      ENDSELECT.
      lv_bk_c = lv_bk_c + <pq>-qty.
      lv_bk_g = lv_bk_g + <pq>-qty.
      lv_bk_t = lv_bk_t + <pq>-qty.

      IF ( lv_plan_c > 0 AND lv_bk_c > lv_plan_c )
      OR ( lv_plan_g > 0 AND lv_bk_g > lv_plan_g )
      OR ( lv_plan_t > 0 AND lv_bk_t > lv_plan_t ).
        rv_error = 'X'.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD raise_busi.
    RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
      EXPORTING textid  = /iwbep/cx_mgw_busi_exception=>business_error
                message = CONV bapi_msg( iv_msg ).
  ENDMETHOD.

ENDCLASS.
