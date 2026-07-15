class ZCL_ZSD_CUST_IND_INBND_DPC_EXT definition
  public
  inheriting from ZCL_ZSD_CUST_IND_INBND_DPC
  create public .

public section.
protected section.

  methods INBOUNDINDENTSET_CREATE_ENTITY
    redefinition .
  methods INBOUNDINDENTSET_GET_ENTITY
    redefinition .
  methods INBOUNDINDENTSET_GET_ENTITYSET
    redefinition .
  methods INBOUNDINDENTSET_UPDATE_ENTITY
    redefinition .
  methods MATERIALSET_GET_ENTITYSET
    redefinition .
  methods STOCKSET_GET_ENTITYSET
    redefinition .
  methods INBOUNDINITSET_GET_ENTITYSET
    redefinition .
  PRIVATE SECTION.
    METHODS get_filter
      IMPORTING iv_prop         TYPE string
                it_filter       TYPE /iwbep/t_mgw_select_option
      RETURNING VALUE(rv_value) TYPE string.

    METHODS raise_error
      IMPORTING iv_text TYPE string
      RAISING   /iwbep/cx_mgw_busi_exception.

    METHODS check_numeric
      IMPORTING iv_value TYPE any
                iv_label TYPE string
      RAISING   /iwbep/cx_mgw_busi_exception.

    METHODS get_stock_for_uom
      IMPORTING iv_matnr TYPE matnr
                iv_werks TYPE werks_d
                iv_charg TYPE charg_d
                iv_msehi TYPE msehi
      EXPORTING ev_tank  TYPE mchbo1-clabs
                ev_line  TYPE mchbo1-clabs.

    METHODS calc_open_indt
      IMPORTING iv_kdgrp TYPE kdgrp
                iv_depot TYPE werks_d
      EXPORTING ev_open  TYPE labst.

ENDCLASS.



CLASS ZCL_ZSD_CUST_IND_INBND_DPC_EXT IMPLEMENTATION.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->CALC_OPEN_INDT
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_KDGRP                       TYPE        KDGRP
* | [--->] IV_DEPOT                       TYPE        WERKS_D
* | [<---] EV_OPEN                        TYPE        LABST
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD calc_open_indt.
  DATA: it_cust_ind TYPE STANDARD TABLE OF zsd_cust_indent,
        z_ind       TYPE zsd_cust_indent,
        it_ebms     TYPE STANDARD TABLE OF zebms_shipment,
        z_ebms      TYPE zebms_shipment,
        it_rebrand  TYPE STANDARD TABLE OF zrebrand,
        it_rebrand1 TYPE STANDARD TABLE OF zrebrand,
        z_brnd      TYPE zrebrand,
        lv_kl(12)   TYPE c,
        lv_uom(3)   TYPE c,
        lv_qty      TYPE labst,
        lv_total    TYPE labst.
  FIELD-SYMBOLS: <fprod> TYPE any, <fqty> TYPE any.

  " rebrand list + (BRND) variants
  SELECT * FROM zrebrand INTO z_brnd.
    APPEND z_brnd TO it_rebrand.
  ENDSELECT.
  it_rebrand1[] = it_rebrand[].
  LOOP AT it_rebrand1 INTO z_brnd.
    CONCATENATE '(BRND)' z_brnd-fprod INTO z_brnd-fprod.
    APPEND z_brnd TO it_rebrand.
  ENDLOOP.

  SELECT * FROM zsd_cust_indent INTO z_ind
    WHERE begda >= sy-datum AND kdgrp = iv_kdgrp
      AND depot = iv_depot AND ztt_status <> 'D'.
    APPEND z_ind TO it_cust_ind.
  ENDSELECT.

  SELECT * FROM zebms_shipment INTO z_ebms
    WHERE lddate = sy-datum AND gi_doc <> ' '.
    SELECT COUNT(*) FROM mseg WHERE smbln = z_ebms-gi_doc.
    IF sy-subrc <> 0.
      APPEND z_ebms TO it_ebms.
    ENDIF.
  ENDSELECT.
  LOOP AT it_ebms INTO z_ebms.
    DELETE it_cust_ind WHERE shnumber = z_ebms-shnumber.
  ENDLOOP.

  CLEAR lv_total.
  LOOP AT it_cust_ind INTO z_ind.
    DO 8 TIMES.
      DATA(lv_n) = sy-index.
      ASSIGN COMPONENT |PROD_CMP{ lv_n }| OF STRUCTURE z_ind TO <fprod>.
      ASSIGN COMPONENT |QUAN_COMP{ lv_n }| OF STRUCTURE z_ind TO <fqty>.
      READ TABLE it_rebrand INTO z_brnd WITH KEY fprod = <fprod>.
      IF sy-subrc = 0.
        CLEAR: lv_kl, lv_uom, lv_qty.
        SPLIT <fqty> AT 'KL' INTO lv_kl lv_uom.
        lv_qty   = lv_kl.
        lv_qty   = ( lv_qty * z_brnd-perc2 ) / 100.
        lv_total = lv_total + lv_qty.
      ENDIF.
    ENDDO.
  ENDLOOP.
  ev_open = lv_total.
ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->CHECK_NUMERIC
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_VALUE                       TYPE        ANY
* | [--->] IV_LABEL                       TYPE        STRING
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD check_numeric.
  DATA: lv_str(200) TYPE c,
        lv_type     TYPE dd01v-datatype.
  IF iv_value IS INITIAL.
    RETURN.
  ENDIF.
  lv_str = iv_value.
  REPLACE FIRST OCCURRENCE OF '.' IN lv_str WITH ' '.
  CONDENSE lv_str.
  CALL FUNCTION 'NUMERIC_CHECK'
    EXPORTING string_in = lv_str
    IMPORTING htype     = lv_type.
  IF lv_type <> 'NUMC'.
    raise_error( |{ iv_label } quantity format is incorrect| ).
  ENDIF.
ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->GET_FILTER
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_PROP                        TYPE        STRING
* | [--->] IT_FILTER                      TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [<-()] RV_VALUE                       TYPE        STRING
* +--------------------------------------------------------------------------------------</SIGNATURE>
  METHOD get_filter.
  FIELD-SYMBOLS: <fs> TYPE /iwbep/s_mgw_select_option,
                 <so> TYPE /iwbep/s_cod_select_option.
  READ TABLE it_filter ASSIGNING <fs> WITH KEY property = iv_prop.
  IF sy-subrc = 0.
    READ TABLE <fs>-select_options ASSIGNING <so> INDEX 1.
    IF sy-subrc = 0.
      rv_value = <so>-low.
    ENDIF.
  ENDIF.
ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->GET_STOCK_FOR_UOM
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_MATNR                       TYPE        MATNR
* | [--->] IV_WERKS                       TYPE        WERKS_D
* | [--->] IV_CHARG                       TYPE        CHARG_D
* | [--->] IV_MSEHI                       TYPE        MSEHI
* | [<---] EV_TANK                        TYPE        MCHBO1-CLABS
* | [<---] EV_LINE                        TYPE        MCHBO1-CLABS
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD get_stock_for_uom.
  DATA ls_mchbo1 TYPE mchbo1.
  CLEAR: ev_tank, ev_line.
  SELECT * FROM mchbo1 INTO ls_mchbo1
    WHERE matnr = iv_matnr AND werks = iv_werks
      AND charg = iv_charg AND msehi = iv_msehi.
    SELECT COUNT(*) FROM t001l
      WHERE werks = iv_werks AND lgort = ls_mchbo1-lgort
        AND oib_tnkassign = 'T'.
    IF sy-subrc = 0.
      ev_tank = ev_tank + ls_mchbo1-clabs + ls_mchbo1-cinsm.   " TANK
    ELSE.
      ev_line = ev_line + ls_mchbo1-clabs + ls_mchbo1-cinsm.   " LINE
    ENDIF.
  ENDSELECT.
  ev_tank = ev_tank / 1000.
  ev_line = ev_line / 1000.
ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->INBOUNDINDENTSET_CREATE_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY_C(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IO_DATA_PROVIDER               TYPE REF TO /IWBEP/IF_MGW_ENTRY_PROVIDER(optional)
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_IND_INBND_MPC=>TS_INBOUNDINDENT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD inboundindentset_create_entity.
  DATA: ls_in    TYPE zcl_zsd_cust_ind_inbnd_mpc=>ts_inboundindent,
        ls_db    TYPE zinb_indent_tab,
        ls_exist TYPE zinb_indent_tab,
        lv_msg   TYPE string.

  DATA lv_user TYPE zsd_cust_usr_map-cust_user_id.


  io_data_provider->read_entry_data( IMPORTING es_data = ls_in ).

  lv_user = ls_in-cust_user_id.
  IF lv_user IS INITIAL. lv_user = sy-uname. ENDIF.




  " quantity format checks
  check_numeric( iv_value = ls_in-ind_qty   iv_label = 'KL'   ).
  check_numeric( iv_value = ls_in-ind_qty15 iv_label = 'KL15' ).
  check_numeric( iv_value = ls_in-ind_qtymt iv_label = 'MT'   ).

  " mandatory fields
  IF ls_in-ind_veh IS INITIAL.
    raise_error( 'Please enter TT number' ).
  ENDIF.
  IF ls_in-ind_qty IS INITIAL.
    raise_error( 'Please enter KL quantity' ).
  ENDIF.
  IF ls_in-ind_inv IS INITIAL.
    raise_error( 'Please enter vendor invoice number' ).
  ENDIF.

    " …validations as before …
  SELECT SINGLE depot kunnr FROM zsd_cust_usr_map
    INTO ( ls_db-ind_plant, ls_db-ind_cust )
    WHERE cust_user_id = lv_user.       " ← was sy-uname


  " an open indent already exists for this vehicle?
  SELECT SINGLE * FROM zinb_indent_tab INTO ls_exist
    WHERE ind_veh = ls_in-ind_veh AND zstatus <> 'COMPLETE'.
  IF sy-subrc = 0.
    CONCATENATE 'Open Indent available for the vehicle on'
                ls_exist-ind_date+6(2) '.' ls_exist-ind_date+4(2) '.'
                ls_exist-ind_date+0(4) INTO lv_msg SEPARATED BY space.
    raise_error( lv_msg ).
  ENDIF.

  " NO same-day dup guard: the SELECT COUNT(*) in WDYP (out.txt:11071) only
  " picks which error message to show, it is NOT a gate - the open-indent check
  " above is WDYP's real duplicate gate. So a TT that already COMPLETED an
  " unload today may be re-indented the same day, matching WDYP behaviour.

  " build & insert (ZSTATUS left blank = open, set to COMPLETE downstream)
  ls_db-ind_date  = sy-datum.
  ls_db-ind_matnr = ls_in-ind_matnr.
  ls_db-ind_veh   = ls_in-ind_veh.
  ls_db-ind_qty   = ls_in-ind_qty.
  ls_db-ind_qty15 = ls_in-ind_qty15.
  ls_db-ind_qtymt = ls_in-ind_qtymt.
  ls_db-ind_inv   = ls_in-ind_inv.

  INSERT zinb_indent_tab FROM ls_db.
  IF sy-subrc <> 0.
    raise_error( 'Data update failed' ).
  ENDIF.
  COMMIT WORK AND WAIT.

  MOVE-CORRESPONDING ls_db TO er_entity.
ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->INBOUNDINDENTSET_GET_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_IND_INBND_MPC=>TS_INBOUNDINDENT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD inboundindentset_get_entity.
  " Read-single. The UI5 v2 ODataModel fires this automatically after a
  " create/update (refreshAfterChange), so it must exist or the change
  " round-trip ends in a 501. Data lives in zinb_indent_tab keyed by
  " (IND_DATE, IND_MATNR, IND_VEH).
  DATA: ls_key TYPE zcl_zsd_cust_ind_inbnd_mpc=>ts_inboundindent,
        ls_db  TYPE zinb_indent_tab.

  io_tech_request_context->get_converted_keys( IMPORTING es_key_values = ls_key ).

  SELECT SINGLE * FROM zinb_indent_tab INTO ls_db
    WHERE ind_date  = ls_key-ind_date
      AND ind_matnr = ls_key-ind_matnr
      AND ind_veh   = ls_key-ind_veh.
  IF sy-subrc = 0.
    MOVE-CORRESPONDING ls_db TO er_entity.
  ELSE.
    " A modify changes the TT (part of the key) via delete-old + insert-new,
    " so the original key from the refresh URL may no longer exist. Echo the
    " requested key back rather than dumping - the UI refreshes the list
    " itself via onOpenIndents().
    MOVE-CORRESPONDING ls_key TO er_entity.
  ENDIF.
ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->INBOUNDINDENTSET_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_IND_INBND_MPC=>TT_INBOUNDINDENT
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD inboundindentset_get_entityset.
  DATA: lt_out   TYPE STANDARD TABLE OF zinb_indent_tab,
        ls_out   TYPE zinb_indent_tab,
        ls_ent   TYPE zcl_zsd_cust_ind_inbnd_mpc=>ts_inboundindent,
        lv_matnr TYPE matnr,
        lv_from  TYPE string,
        lv_to    TYPE string,
        lv_frto  TYPE string.

  DATA lv_user TYPE zsd_cust_usr_map-cust_user_id.


  lv_matnr = get_filter( iv_prop = 'IND_MATNR' it_filter = it_filter_select_options ).
  lv_from  = get_filter( iv_prop = 'DATE_FROM' it_filter = it_filter_select_options ).
  lv_to    = get_filter( iv_prop = 'DATE_TO'   it_filter = it_filter_select_options ).

  " empty FR_TO_DATE -> open indents; filled (16 char) -> all in range
  IF lv_from IS NOT INITIAL AND lv_to IS NOT INITIAL.
    CONCATENATE lv_from lv_to INTO lv_frto.
  ENDIF.

  lv_user  = get_filter( iv_prop = 'CUST_USER_ID' it_filter = it_filter_select_options ).
  IF lv_user IS INITIAL. lv_user = sy-uname. ENDIF.

  " lv_matnr / lv_frto as before …
  CALL FUNCTION 'Z_GET_CUST_UNLOAD_INDENT'
    EXPORTING
      cust_id      = lv_user          " ← was sy-uname
      matnr        = lv_matnr
      fr_to_date   = lv_frto
    TABLES
      zindent_data = lt_out.


  LOOP AT lt_out INTO ls_out.
    CLEAR ls_ent.
    MOVE-CORRESPONDING ls_out TO ls_ent.   " field names match the entity
    " Z_GET_CUST_UNLOAD_INDENT fills the WDYP ZINDENT_DATA subset, which omits
    " IND_QTY15/IND_QTYMT/ZSTATUS. Back-fill the display fields from the DB by
    " primary key (IND_DATE, IND_MATNR, IND_VEH) = full key, so exact.
    SELECT SINGLE ind_qty15 ind_qtymt zstatus
      FROM zinb_indent_tab
      INTO ( ls_ent-ind_qty15, ls_ent-ind_qtymt, ls_ent-zstatus )
      WHERE ind_date  = ls_out-ind_date
        AND ind_matnr = ls_out-ind_matnr
        AND ind_veh   = ls_out-ind_veh.
    APPEND ls_ent TO et_entityset.
  ENDLOOP.
ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->INBOUNDINDENTSET_UPDATE_ENTITY
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITY_U(optional)
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IO_DATA_PROVIDER               TYPE REF TO /IWBEP/IF_MGW_ENTRY_PROVIDER(optional)
* | [<---] ER_ENTITY                      TYPE        ZCL_ZSD_CUST_IND_INBND_MPC=>TS_INBOUNDINDENT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD inboundindentset_update_entity.
  DATA: ls_in      TYPE zcl_zsd_cust_ind_inbnd_mpc=>ts_inboundindent,
        ls_key     TYPE zcl_zsd_cust_ind_inbnd_mpc=>ts_inboundindent,
        ls_db      TYPE zinb_indent_tab,
        lv_old_veh TYPE oig_vhlnmr.

  " ORIGINAL key from the URL
  io_tech_request_context->get_converted_keys( IMPORTING es_key_values = ls_key ).
  " NEW values from the payload
  io_data_provider->read_entry_data( IMPORTING es_data = ls_in ).

  SELECT SINGLE * FROM zinb_indent_tab INTO ls_db
    WHERE ind_date  = ls_key-ind_date
      AND ind_matnr = ls_key-ind_matnr
      AND ind_veh   = ls_key-ind_veh.
  IF sy-subrc <> 0.
    raise_error( 'Indent not found' ).
  ENDIF.
  IF ls_db-zstatus = 'COMPLETE'.
    raise_error( 'Completed indents cannot be modified' ).
  ENDIF.

  lv_old_veh      = ls_db-ind_veh.
  ls_db-ind_qty   = ls_in-ind_qty.
  ls_db-ind_qty15 = ls_in-ind_qty15.
  ls_db-ind_qtymt = ls_in-ind_qtymt.
  ls_db-ind_veh   = ls_in-ind_veh.     " may differ -> key change
  ls_db-ind_inv   = ls_in-ind_inv.

  DELETE FROM zinb_indent_tab
    WHERE ind_date  = ls_key-ind_date
      AND ind_matnr = ls_key-ind_matnr
      AND ind_veh   = lv_old_veh.
  MODIFY zinb_indent_tab FROM ls_db.
  IF sy-subrc <> 0.
    raise_error( 'Data update failed' ).
  ENDIF.
  COMMIT WORK AND WAIT.

  MOVE-CORRESPONDING ls_db TO er_entity.
ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->INBOUNDINITSET_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_IND_INBND_MPC=>TT_INBOUNDINIT
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD inboundinitset_get_entityset.
  DATA: ls_cust TYPE zsd_cust_usr_map,
        ls_ent  TYPE zcl_zsd_cust_ind_inbnd_mpc=>ts_inboundinit,
        lv_mat  TYPE matnr.

  DATA lv_user TYPE zsd_cust_usr_map-cust_user_id.


  lv_user = get_filter( iv_prop = 'CUST_USER_ID' it_filter = it_filter_select_options ).
  IF lv_user IS INITIAL. lv_user = sy-uname. ENDIF.

  SELECT SINGLE * FROM zsd_cust_usr_map INTO ls_cust WHERE cust_user_id = lv_user.
  ls_ent-cust_user_id = lv_user.     " return what was asked for

  ls_ent-kunnr        = ls_cust-kunnr.
  ls_ent-depot        = ls_cust-depot.
  ls_ent-ebms         = ls_cust-ebms.

  IF ls_cust-ebms = 'Y'.
    SELECT SINGLE imat2 FROM zebms_blend INTO lv_mat.
    ls_ent-matnr = lv_mat.
  ENDIF.

  APPEND ls_ent TO et_entityset.
ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->MATERIALSET_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_IND_INBND_MPC=>TT_MATERIAL
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
  method MATERIALSET_GET_ENTITYSET.
**try.
*CALL METHOD SUPER->MATERIALSET_GET_ENTITYSET
*  EXPORTING
*    IV_ENTITY_NAME           =
*    IV_ENTITY_SET_NAME       =
*    IV_SOURCE_NAME           =
*    IT_FILTER_SELECT_OPTIONS =
*    IS_PAGING                =
*    IT_KEY_TAB               =
*    IT_NAVIGATION_PATH       =
*    IT_ORDER                 =
*    IV_FILTER_STRING         =
*    IV_SEARCH_STRING         =
**    IO_TECH_REQUEST_CONTEXT  =
**  importing
**    ET_ENTITYSET             =
**    ES_RESPONSE_CONTEXT      =
*    .
**  catch /IWBEP/CX_MGW_BUSI_EXCEPTION.
**  catch /IWBEP/CX_MGW_TECH_EXCEPTION.
**endtry.
  endmethod.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Private Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->RAISE_ERROR
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_TEXT                        TYPE        STRING
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD raise_error.
  DATA: lo_msg TYPE REF TO /iwbep/if_message_container,
        lv_txt TYPE bapi_msg.            " CHAR220 — matches IV_MSG_TEXT

  lv_txt = iv_text.                       " STRING -> BAPI_MSG (auto truncates at 220)

  lo_msg = me->/iwbep/if_mgw_conv_srv_runtime~get_message_container( ).
  lo_msg->add_message_text_only(
    iv_msg_type = 'E'
    iv_msg_text = lv_txt ).

  RAISE EXCEPTION TYPE /iwbep/cx_mgw_busi_exception
    EXPORTING message_container = lo_msg.
ENDMETHOD.


* <SIGNATURE>---------------------------------------------------------------------------------------+
* | Instance Protected Method ZCL_ZSD_CUST_IND_INBND_DPC_EXT->STOCKSET_GET_ENTITYSET
* +-------------------------------------------------------------------------------------------------+
* | [--->] IV_ENTITY_NAME                 TYPE        STRING
* | [--->] IV_ENTITY_SET_NAME             TYPE        STRING
* | [--->] IV_SOURCE_NAME                 TYPE        STRING
* | [--->] IT_FILTER_SELECT_OPTIONS       TYPE        /IWBEP/T_MGW_SELECT_OPTION
* | [--->] IS_PAGING                      TYPE        /IWBEP/S_MGW_PAGING
* | [--->] IT_KEY_TAB                     TYPE        /IWBEP/T_MGW_NAME_VALUE_PAIR
* | [--->] IT_NAVIGATION_PATH             TYPE        /IWBEP/T_MGW_NAVIGATION_PATH
* | [--->] IT_ORDER                       TYPE        /IWBEP/T_MGW_SORTING_ORDER
* | [--->] IV_FILTER_STRING               TYPE        STRING
* | [--->] IV_SEARCH_STRING               TYPE        STRING
* | [--->] IO_TECH_REQUEST_CONTEXT        TYPE REF TO /IWBEP/IF_MGW_REQ_ENTITYSET(optional)
* | [<---] ET_ENTITYSET                   TYPE        ZCL_ZSD_CUST_IND_INBND_MPC=>TT_STOCK
* | [<---] ES_RESPONSE_CONTEXT            TYPE        /IWBEP/IF_MGW_APPL_SRV_RUNTIME=>TY_S_MGW_RESPONSE_CONTEXT
* | [!CX!] /IWBEP/CX_MGW_BUSI_EXCEPTION
* | [!CX!] /IWBEP/CX_MGW_TECH_EXCEPTION
* +--------------------------------------------------------------------------------------</SIGNATURE>
METHOD stockset_get_entityset.
  DATA: lv_matnr TYPE matnr,
        ls_stock TYPE zcl_zsd_cust_ind_inbnd_mpc=>ts_stock,
        ls_cust  TYPE zsd_cust_usr_map,
        lv_kdgrp TYPE kdgrp,
        lv_charg TYPE charg_d,
        lv_tank  TYPE mchbo1-clabs,
        lv_line  TYPE mchbo1-clabs,
        lv_open  TYPE labst,
        lv_bal   TYPE labst,
        lv_c(20) TYPE c.

  DATA lv_user TYPE zsd_cust_usr_map-cust_user_id.


  lv_matnr = get_filter( iv_prop = 'MATNR' it_filter = it_filter_select_options ).
  IF lv_matnr IS INITIAL.
    RETURN.
  ENDIF.

  lv_user = get_filter( iv_prop = 'CUST_USER_ID' it_filter = it_filter_select_options ).
  IF lv_user IS INITIAL. lv_user = sy-uname. ENDIF.

  SELECT SINGLE * FROM zsd_cust_usr_map INTO ls_cust WHERE cust_user_id = lv_user.
  "  …rest of the stock logic is unchanged (depot/kdgrp/charg all derive from ls_cust)

  SELECT SINGLE kdgrp FROM knvv INTO lv_kdgrp
    WHERE kunnr = ls_cust-kunnr AND spart = '25'.
  CASE lv_kdgrp.
    WHEN 'BP'. lv_charg = 'BPCL-NOVAL'.
    WHEN 'HP'. lv_charg = 'HPCL-NOVAL'.
    WHEN 'EO'. lv_charg = 'ESSR-NOVAL'.
    WHEN 'RI'. lv_charg = 'RIL-NOVAL'.
    WHEN 'SH'. lv_charg = 'SHEL-NOVAL'.
    WHEN 'IO'. lv_charg = 'IOCL-NOVAL'.
  ENDCASE.

  ls_stock-matnr = lv_matnr.

  " --- KL ---
  get_stock_for_uom( EXPORTING iv_matnr = lv_matnr iv_werks = ls_cust-depot
                               iv_charg = lv_charg iv_msehi = 'L'
                     IMPORTING ev_tank  = lv_tank  ev_line  = lv_line ).
  lv_bal = lv_tank.
  lv_c = lv_tank. CONDENSE lv_c. CONCATENATE lv_c 'KL' INTO ls_stock-unld_stock SEPARATED BY space.
  IF lv_line > 0.
    lv_c = lv_line. CONDENSE lv_c. CONCATENATE lv_c 'KL' INTO ls_stock-ln_hld_kl SEPARATED BY space.
  ENDIF.

  " --- KL15 ---
  get_stock_for_uom( EXPORTING iv_matnr = lv_matnr iv_werks = ls_cust-depot
                               iv_charg = lv_charg iv_msehi = 'L15'
                     IMPORTING ev_tank  = lv_tank  ev_line  = lv_line ).
  lv_c = lv_tank. CONDENSE lv_c. CONCATENATE lv_c 'KL15' INTO ls_stock-unld_stock15 SEPARATED BY space.
  IF lv_line > 0.
    lv_c = lv_line. CONDENSE lv_c. CONCATENATE lv_c 'KL15' INTO ls_stock-ln_hld_kl15 SEPARATED BY space.
  ENDIF.

  " --- MT (KG) ---
  get_stock_for_uom( EXPORTING iv_matnr = lv_matnr iv_werks = ls_cust-depot
                               iv_charg = lv_charg iv_msehi = 'KG'
                     IMPORTING ev_tank  = lv_tank  ev_line  = lv_line ).
  lv_c = lv_tank. CONDENSE lv_c. CONCATENATE lv_c 'MT' INTO ls_stock-unld_stockmt SEPARATED BY space.
  IF lv_line > 0.
    lv_c = lv_line. CONDENSE lv_c. CONCATENATE lv_c 'MT' INTO ls_stock-ln_hld_mt SEPARATED BY space.
  ENDIF.

  " --- open indent qty + available balance ---
  calc_open_indt( EXPORTING iv_kdgrp = lv_kdgrp iv_depot = ls_cust-depot
                  IMPORTING ev_open  = lv_open ).
  lv_bal = lv_bal - lv_open.
  lv_c = lv_open. CONDENSE lv_c. CONCATENATE lv_c 'KL' INTO ls_stock-open_indt SEPARATED BY space.
  lv_c = lv_bal.  CONDENSE lv_c. CONCATENATE lv_c 'KL' INTO ls_stock-bal_qty   SEPARATED BY space.

  APPEND ls_stock TO et_entityset.
ENDMETHOD.
ENDCLASS.