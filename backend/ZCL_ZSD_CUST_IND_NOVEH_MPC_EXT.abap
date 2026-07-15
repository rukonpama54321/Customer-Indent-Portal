*&---------------------------------------------------------------------*
*&  ZCL_ZSD_CUST_IND_NOVEH_MPC_EXT
*&  Model provider (extension) for the Without-Vehicle entity sets.
*&
*&  Service: ZSD_CUST_IND_NOVEH_SRV  (manifest model: withoutvehModel)
*&
*&  The generated base MPC (ZCL_ZSD_CUST_IND_NOVEH_MPC) already builds the
*&  full model - all entity types and sets (incl. the GetTransGSTIN NAME
*&  property, which is now modelled in SEGW). So we do NOT re-declare
*&  anything here (that would raise a duplicate-name
*&  /iwbep/cx_mgw_med_exception at metadata load).
*&
*&  The ONLY adjustment needed: the base marks GetOpenIndentsSet as
*&  non-creatable/updatable/deletable, but the DPC_EXT implements
*&  create/update/delete for it. We flip those flags on the already-created
*&  entity set after super->define( ).  (If you instead tick
*&  Creatable/Updatable/Deletable on the entity set in SEGW, this whole
*&  redefinition can be removed.)
*&---------------------------------------------------------------------*
CLASS zcl_zsd_cust_ind_noveh_mpc_ext DEFINITION
  PUBLIC
  INHERITING FROM zcl_zsd_cust_ind_noveh_mpc
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS define REDEFINITION.
ENDCLASS.

CLASS zcl_zsd_cust_ind_noveh_mpc_ext IMPLEMENTATION.

  METHOD define.

    " build the generated model (all entity types / sets)
    super->define( ).

    " GetOpenIndentsSet carries write behaviour in the DPC_EXT
    " (create / short-close via update / delete). The generated base
    " leaves it read-only, so enable the operations here.
    DATA(lo_set) = model->get_entity_set( 'GetOpenIndentsSet' ).
    lo_set->set_creatable( abap_true ).
    lo_set->set_updatable( abap_true ).
    lo_set->set_deletable( abap_true ).

    " ---- Material entity: multi-row dropdown model --------------------
    " The Without-Vehicle material value help is a per-customer-group DROPDOWN
    " (WD SELECT_MAT_AND_GSTN, out.txt:9595-9615) - e.g. group DI offers five
    " materials. The generated Material entity is keyed by KUNNR alone with the
    " single-value MATNR1/MATNR2 slots, which cannot represent the list. The
    " DPC_EXT now returns one row per eligible material, so extend the model:
    "   * add MATNR to the key  -> KUNNR+MATNR uniquely identifies each row
    "   * add MATDESC           -> ZSD_INDT_NO_VEH-DESCRIPTION
    " ACTIVE1/ACTIVE2 are reused as the per-group slot-enable flags (material-1
    " slot for all five groups; material-2 slot for OI/TG/ON), now repeated on
    " every row. The legacy MATNR1/MATNR2 properties are left in place (unused,
    " always blank); drop them in SEGW for a fully clean model.
    DATA(lo_mat) = model->get_entity_type( 'Material' ).

    DATA(lo_prop) = lo_mat->create_property(
      iv_property_name = 'MATNR' iv_abap_fieldname = 'MATNR' ).
    lo_prop->set_is_key( ).
    lo_prop->set_type_edm_string( ).
    lo_prop->set_maxlength( iv_max_length = 40 ).
    lo_prop->set_creatable( abap_false ).
    lo_prop->set_updatable( abap_false ).
    lo_prop->set_sortable( abap_false ).
    lo_prop->set_nullable( abap_false ).
    lo_prop->set_filterable( abap_false ).

    lo_prop = lo_mat->create_property(
      iv_property_name = 'MATDESC' iv_abap_fieldname = 'MATDESC' ).
    lo_prop->set_type_edm_string( ).
    lo_prop->set_maxlength( iv_max_length = 100 ).
    lo_prop->set_creatable( abap_false ).
    lo_prop->set_updatable( abap_false ).
    lo_prop->set_sortable( abap_false ).
    lo_prop->set_nullable( abap_true ).
    lo_prop->set_filterable( abap_false ).

  ENDMETHOD.

ENDCLASS.
