*&---------------------------------------------------------------------*
*&  ZCL_ZSDI_ODATA_CUST_PO_MPC_EXT
*&  Model provider (extension) for the With-Vehicle entity sets.
*&
*&  NOTE: This DEFINE builds the model in code as a precise, reviewable
*&        spec. If you already model these entities in SEGW so that the
*&        generated metadata matches webapp/localService/mainService/
*&        metadata.xml, you can KEEP that model and skip this class -
*&        only the DPC_EXT carries the behaviour.
*&
*&  Paste the body of DEFINE into the generated *_MPC_EXT->DEFINE method.
*&---------------------------------------------------------------------*
CLASS zcl_zsdi_odata_cust_po_mpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zsdi_odata_cust_po_mpc
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS define REDEFINITION.
ENDCLASS.

CLASS zcl_zsdi_odata_cust_po_mpc_ext IMPLEMENTATION.

  METHOD define.

    super->define( ).

    DATA: lo_type TYPE REF TO /iwbep/if_mgw_odata_entity_typ,
          lo_prop TYPE REF TO /iwbep/if_mgw_odata_property,
          lo_set  TYPE REF TO /iwbep/if_mgw_odata_entity_set.

    " ---- helper macros (string property / key property / set) ----------
    DEFINE _p.
      lo_prop = lo_type->create_property( iv_property_name = &1 iv_abap_fieldname = &1 ).
      lo_prop->set_type_edm_string( ).
    END-OF-DEFINITION.

    DEFINE _pk.
      _p &1.
      lo_prop->set_is_key( abap_true ).
    END-OF-DEFINITION.

    DEFINE _set.
      lo_set = lo_type->create_entity_set( &1 ).
    END-OF-DEFINITION.

    "==================================================================
    " Vehicle / VehicleSet
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'Vehicle' iv_def_entity_set = abap_false ).
    _pk 'TU_NUMBER'.
    _p  'TU_TEXT'.  _p 'SMTP_ADDR'.  _p 'COLOR'.  _p 'STATUS'.
    _set 'VehicleSet'.

    "==================================================================
    " ZUSER / ZUSERSet
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'ZUSER' iv_def_entity_set = abap_false ).
    _pk 'KUNNR'.
    _p  'CUST_USER_ID'. _p 'KDGRP'. _p 'NAME1'. _p 'SMTP_ADDR'. _p 'GSTIN_ENABLE'.
    _set 'ZUSERSet'.

    "==================================================================
    " CheckLicense / CheckLicenseSet
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'CheckLicense' iv_def_entity_set = abap_false ).
    _pk 'VEHICLE'.
    _p 'MESSAGE1'.  _p 'MESSAGE2'.  _p 'MESSAGE3'.  _p 'MESSAGE4'.
    _p 'MESSAGE5'.  _p 'MESSAGE6'.  _p 'MESSAGE7'.  _p 'MESSAGE8'.
    _p 'MESSAGE9'.  _p 'MESSAGE10'. _p 'MESSAGE11'. _p 'MESSAGE12'.
    _p 'MESSAGE13'. _p 'MESSAGE14'.
    _set 'CheckLicenseSet'.

    "==================================================================
    " GETCompartmentNo / GETCompartmentNoSet
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'GETCompartmentNo' iv_def_entity_set = abap_false ).
    _pk 'VEHICLE'. _pk 'COM_NUMBER'.
    _p 'COMPOSITION'. _p 'VEH_TYPE'. _p 'TOTAL_COMP'. _p 'UOM'. _p 'COMP_ENABLED'.
    _set 'GETCompartmentNoSet'.

    "==================================================================
    " GETProduct / GETProductSet
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'GETProduct' iv_def_entity_set = abap_false ).
    _pk 'VEHICLE'. _pk 'PRODUCT'.
    _p 'VEH_TYPE'. _p 'CUST_USER_ID'. _p 'SMTP_ADDR'.
    _set 'GETProductSet'.

    "==================================================================
    " GSTN / GSTNSet
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'GSTN' iv_def_entity_set = abap_false ).
    _pk 'GSTIN'.
    _p 'NAME'. _p 'KUNNR'.
    _set 'GSTNSet'.

    "==================================================================
    " Flushreason / FlushreasonSet
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'Flushreason' iv_def_entity_set = abap_false ).
    _pk 'DDTEXT'.
    _p 'DOMNAME'.
    _set 'FlushreasonSet'.

    "==================================================================
    " SalesContract / SalesContractSet
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'SalesContract' iv_def_entity_set = abap_false ).
    _pk 'KUNNR'. _pk 'TEXT'.
    _p 'PRODUCT1'. _p 'PRODUCT2'. _p 'PRODUCT3'. _p 'PRODUCT4'.
    _p 'PRODUCT5'. _p 'PRODUCT6'. _p 'PRODUCT7'. _p 'PRODUCT8'.
    _p 'CUST_USER_ID'. _p 'SMTP_ADDR'. _p 'DESC'.
    _set 'SalesContractSet'.

    "==================================================================
    " GetEndUse / GetEndUseSet
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'GetEndUse' iv_def_entity_set = abap_false ).
    _pk 'VEHICLE'. _pk 'DOMVALUE_L'.
    _p 'ACTIVATE_ENDUSE'. _p 'DDTEXT'.
    _p 'PRODUCT1'. _p 'PRODUCT2'. _p 'PRODUCT3'. _p 'PRODUCT4'.
    _p 'PRODUCT5'. _p 'PRODUCT6'. _p 'PRODUCT7'. _p 'PRODUCT8'.
    _p 'BEGDA'. _p 'KUNNR'. _p 'CUST_USER_ID'. _p 'SMTP_ADDR'.
    _set 'GetEndUseSet'.

    "==================================================================
    " GETINDENT / GETINDENTSet
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'GETINDENT' iv_def_entity_set = abap_false ).
    _pk 'BEGDA'. _pk 'VEHICLE'. _pk 'KUNNR'.
    _p 'DEPOT'. _p 'CUST_USER_ID'. _p 'SMTP_ADDR'. _p 'NAME1'.
    _p 'PROD_CMP1'. _p 'VAL_COMP1'. _p 'QUAN_COMP1'.
    _p 'PROD_CMP2'. _p 'VAL_COMP2'. _p 'QUAN_COMP2'.
    _p 'PROD_CMP3'. _p 'VAL_COMP3'. _p 'QUAN_COMP3'.
    _p 'PROD_CMP4'. _p 'VAL_COMP4'. _p 'QUAN_COMP4'.
    _p 'PROD_CMP5'. _p 'VAL_COMP5'. _p 'QUAN_COMP5'.
    _p 'PROD_CMP6'. _p 'VAL_COMP6'. _p 'QUAN_COMP6'.
    _p 'PROD_CMP7'. _p 'VAL_COMP7'. _p 'QUAN_COMP7'.
    _p 'PROD_CMP8'. _p 'VAL_COMP8'. _p 'QUAN_COMP8'.
    _p 'ZTT_STATUS'. _p 'ZTT_STATUS_DESC'. _p 'ZDELETE'. _p 'COLOR'.
    _p 'TPT_GSTN'. _p 'FLUSH_REASON'. _p 'ATF_FLUSH'. _p 'MS_END_USE'.
    _p 'HSD_END_USE'.
    _p 'KONDM'. _p 'CONTRACT'. _p 'INDENT_TYPE'. _p 'ERROR'.
    _set 'GETINDENTSet'.

    "==================================================================
    " SaveIndent / SaveIndentSet  (create)
    "==================================================================
    lo_type = model->create_entity_type( iv_entity_type_name = 'SaveIndent' iv_def_entity_set = abap_false ).
    _pk 'BEGDA'. _pk 'VEHICLE'. _pk 'KUNNR'. _pk 'CUST_USER_ID'.
    _p 'ENDDA'. _p 'SHNUMBER'. _p 'DEPOT'. _p 'INDENT_DATE'. _p 'INDENT_TIME'.
    _p 'KUNNR_DESC'. _p 'SHTYPE'. _p 'KONDM'. _p 'KONDM2'.
    _p 'PROD_CMP1'. _p 'VAL_COMP1'. _p 'QUAN_COMP1'.
    _p 'PROD_CMP2'. _p 'VAL_COMP2'. _p 'QUAN_COMP2'.
    _p 'PROD_CMP3'. _p 'VAL_COMP3'. _p 'QUAN_COMP3'.
    _p 'PROD_CMP4'. _p 'VAL_COMP4'. _p 'QUAN_COMP4'.
    _p 'PROD_CMP5'. _p 'VAL_COMP5'. _p 'QUAN_COMP5'.
    _p 'PROD_CMP6'. _p 'VAL_COMP6'. _p 'QUAN_COMP6'.
    _p 'PROD_CMP7'. _p 'VAL_COMP7'. _p 'QUAN_COMP7'.
    _p 'PROD_CMP8'. _p 'VAL_COMP8'. _p 'QUAN_COMP8'.
    _p 'SUMMARY'. _p 'ZTT_STATUS'. _p 'ZTT_STATUS_DESC'. _p 'ATF_FLUSH'.
    _p 'CHK'. _p 'CONTRACT'. _p 'HSD'. _p 'ARHSD'. _p 'MS'. _p 'ATF'.
    _p 'SKO'. _p 'MTO'. _p 'LPG'. _p 'PWAX'. _p 'SUL'. _p 'RPC'. _p 'CPC'.
    _p 'NTG'. _p 'OTHER'. _p 'KDGRP'. _p 'INDENT_TYPE'. _p 'TPT_GSTN'.
    _p 'FLUSH_REASON'. _p 'ERROR'. _p 'ZDELETE'. _p 'DELV_CHALN'.
    _p 'HOSP_DELV'. _p 'ZTRAN'. _p 'MS_END_USE'. _p 'HSD_END_USE'.
    _p 'BULK_ORDER'. _p 'BULK_QTY'. _p 'SMTP_ADDR'.
    _set 'SaveIndentSet'.

  ENDMETHOD.

ENDCLASS.
