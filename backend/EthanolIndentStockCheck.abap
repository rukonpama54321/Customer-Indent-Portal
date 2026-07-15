FUNCTION Z_ETHANOL_INDENT_STK_CHECK.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(CUST_INDENT) TYPE  ZSD_CUST_INDENT OPTIONAL
*"     VALUE(C1_QT) TYPE  LABST OPTIONAL
*"     VALUE(C2_QT) TYPE  LABST OPTIONAL
*"     VALUE(C3_QT) TYPE  LABST OPTIONAL
*"     VALUE(C4_QT) TYPE  LABST OPTIONAL
*"     VALUE(C5_QT) TYPE  LABST OPTIONAL
*"     VALUE(C6_QT) TYPE  LABST OPTIONAL
*"     VALUE(C7_QT) TYPE  LABST OPTIONAL
*"     VALUE(C8_QT) TYPE  LABST OPTIONAL
*"     VALUE(B2B_CALL) TYPE  CHAR1 OPTIONAL
*"  EXPORTING
*"     VALUE(ERR_MSG) TYPE  STRING
*"     VALUE(ZSTK_ERR) TYPE  C1
*"----------------------------------------------------------------------

TYPES: BEGIN OF STK_CHK,
          MATNR TYPE MATNR,
          QTY TYPE LABST,
         END OF STK_CHK.
  DATA IT_STK_CHK TYPE STANDARD TABLE OF STK_CHK.
  DATA ZSTK_CHK LIKE LINE OF IT_STK_CHK.
  DATA ZBRND_CHK TYPE ZREBRAND.
  DATA ZTOT_QTY TYPE LABST.
  DATA ZMATNR TYPE MATNR.
  DATA IT_REBRAND TYPE STANDARD TABLE OF ZREBRAND.
  DATA IT_REBRAND1 TYPE STANDARD TABLE OF ZREBRAND.
  DATA: ZIND_KL(12),
        ZIND_QTY TYPE LABST,
        ZIND_TOT_QTY TYPE LABST,
        ZIND_UOM(3).
  data: ztot_clabs type mchbo1-clabs.
  data: it_mchbo1 type standard table of mchbo1,
        zmchbo1 type mchbo1.
*  data zstk_err(1).
  data: stk_tx(20).
  data: l_cr(1) type c value cl_abap_char_utilities=>cr_lf,
        l_lf(1) type c value cl_abap_char_utilities=>newline.


  clear: ZBRND_CHK, IT_REBRAND, IT_REBRAND[], IT_REBRAND1, IT_REBRAND1[].
  select * from ZREBRAND into ZBRND_CHK.
    append ZBRND_CHK to IT_REBRAND.
  endselect.
  IT_REBRAND1[] = IT_REBRAND[].

  loop at IT_REBRAND1 into ZBRND_CHK.
    concatenate '(BRND)' ZBRND_CHK-FPROD INTO ZBRND_CHK-FPROD.
    append ZBRND_CHK to IT_REBRAND.
  endloop.
  read table IT_REBRAND into ZBRND_CHK with key fprod = CUST_INDENT-PROD_CMP1.
  if sy-subrc = 0.
    ZSTK_CHK-MATNR = ZBRND_CHK-IMAT2.
    ZSTK_CHK-QTY   = ( C1_QT * ZBRND_CHK-PERC2 ) / 100.
    APPEND ZSTK_CHK TO IT_STK_CHK.
  endif.
  read table IT_REBRAND into ZBRND_CHK with key fprod = CUST_INDENT-PROD_CMP2.
  if sy-subrc = 0.
    ZSTK_CHK-MATNR = ZBRND_CHK-IMAT2.
    ZSTK_CHK-QTY   = ( C2_QT * ZBRND_CHK-PERC2 ) / 100.
    APPEND ZSTK_CHK TO IT_STK_CHK.
  endif.
  read table IT_REBRAND into ZBRND_CHK with key fprod = CUST_INDENT-PROD_CMP3.
  if sy-subrc = 0.
    ZSTK_CHK-MATNR = ZBRND_CHK-IMAT2.
    ZSTK_CHK-QTY   = ( C3_QT * ZBRND_CHK-PERC2 ) / 100.
    APPEND ZSTK_CHK TO IT_STK_CHK.
  endif.
  read table IT_REBRAND into ZBRND_CHK with key fprod = CUST_INDENT-PROD_CMP4.
  if sy-subrc = 0.
    ZSTK_CHK-MATNR = ZBRND_CHK-IMAT2.
    ZSTK_CHK-QTY   = ( C4_QT * ZBRND_CHK-PERC2 ) / 100.
    APPEND ZSTK_CHK TO IT_STK_CHK.
  endif.
  read table IT_REBRAND into ZBRND_CHK with key fprod = CUST_INDENT-PROD_CMP5.
  if sy-subrc = 0.
    ZSTK_CHK-MATNR = ZBRND_CHK-IMAT2.
    ZSTK_CHK-QTY   = ( C5_QT * ZBRND_CHK-PERC2 ) / 100.
    APPEND ZSTK_CHK TO IT_STK_CHK.
  endif.
  read table IT_REBRAND into ZBRND_CHK with key fprod = CUST_INDENT-PROD_CMP6.
  if sy-subrc = 0.
    ZSTK_CHK-MATNR = ZBRND_CHK-IMAT2.
    ZSTK_CHK-QTY   = ( C6_QT * ZBRND_CHK-PERC2 ) / 100.
    APPEND ZSTK_CHK TO IT_STK_CHK.
  endif.
  read table IT_REBRAND into ZBRND_CHK with key fprod = CUST_INDENT-PROD_CMP7.
  if sy-subrc = 0.
    ZSTK_CHK-MATNR = ZBRND_CHK-IMAT2.
    ZSTK_CHK-QTY   = ( C7_QT * ZBRND_CHK-PERC2 ) / 100.
    APPEND ZSTK_CHK TO IT_STK_CHK.
  endif.
  read table IT_REBRAND into ZBRND_CHK with key fprod = CUST_INDENT-PROD_CMP8.
  if sy-subrc = 0.
    ZSTK_CHK-MATNR = ZBRND_CHK-IMAT2.
    ZSTK_CHK-QTY   = ( C8_QT * ZBRND_CHK-PERC2 ) / 100.
    APPEND ZSTK_CHK TO IT_STK_CHK.
  endif.
  clear: ZSTK_CHK, ZTOT_QTY.
  loop at IT_STK_CHK into ZSTK_CHK.
    ZTOT_QTY = ZTOT_QTY + ZSTK_CHK-QTY.
  endloop.

  DATA: IT_CUST_IND TYPE STANDARD TABLE OF ZSD_CUST_INDENT,
        IT_EBMS TYPE STANDARD TABLE OF ZEBMS_SHIPMENT.

  DATA: Z_IND TYPE ZSD_CUST_INDENT,
        Z_EBMS TYPE ZEBMS_SHIPMENT.

  CLEAR: IT_CUST_IND, IT_CUST_IND[], IT_EBMS, IT_EBMS[], Z_IND, Z_EBMS.
  IF ZTOT_QTY > 0.
    select * from zsd_cust_indent into Z_IND where begda >= CUST_INDENT-BEGDA
       and kdgrp = CUST_INDENT-KDGRP and depot = CUST_INDENT-depot and ztt_status <> 'D'.
      if sy-subrc = 0 .
        append Z_IND to IT_CUST_IND.
      endif.
    endselect.
    delete IT_CUST_IND where VEHICLE = CUST_INDENT-VEHICLE and ZTT_STATUS = '4'.
    select * from zebms_shipment into Z_EBMS where
      lddate = sy-datum and gi_doc <> ' '.
      if sy-subrc = 0.
        select count(*) from mseg where smbln = Z_EBMS-gi_doc.
        if sy-subrc <> 0.
          append Z_EBMS to IT_EBMS.
        endif.
      endif.
    endselect.
    loop at IT_EBMS into Z_EBMS.
      delete IT_CUST_IND where shnumber = Z_EBMS-shnumber.
    endloop.
  ENDIF.

  clear ZIND_TOT_QTY.
  loop at IT_CUST_IND into Z_IND.
    read table IT_REBRAND into ZBRND_CHK with key fprod = Z_IND-PROD_CMP1.
    if sy-subrc = 0.
      clear: ZIND_KL, ZIND_UOM, ZIND_QTY.
      split Z_IND-QUAN_COMP1 at 'KL' into ZIND_KL ZIND_UOM.
      MOVE ZIND_KL TO ZIND_QTY.
      ZIND_QTY = ( ZIND_QTY * ZBRND_CHK-PERC2 ) / 100.
      ZIND_TOT_QTY = ZIND_TOT_QTY + ZIND_QTY.
    endif.
    read table IT_REBRAND into ZBRND_CHK with key fprod = Z_IND-PROD_CMP2.
    if sy-subrc = 0.
      clear: ZIND_KL, ZIND_UOM, ZIND_QTY.
      split Z_IND-QUAN_COMP2 at 'KL' into ZIND_KL ZIND_UOM.
      MOVE ZIND_KL TO ZIND_QTY.
      ZIND_QTY = ( ZIND_QTY * ZBRND_CHK-PERC2 ) / 100.
      ZIND_TOT_QTY = ZIND_TOT_QTY + ZIND_QTY.
    endif.
    read table IT_REBRAND into ZBRND_CHK with key fprod = Z_IND-PROD_CMP3.
    if sy-subrc = 0.
      clear: ZIND_KL, ZIND_UOM, ZIND_QTY.
      split Z_IND-QUAN_COMP3 at 'KL' into ZIND_KL ZIND_UOM.
      MOVE ZIND_KL TO ZIND_QTY.
      ZIND_QTY = ( ZIND_QTY * ZBRND_CHK-PERC2 ) / 100.
      ZIND_TOT_QTY = ZIND_TOT_QTY + ZIND_QTY.
    endif.
    read table IT_REBRAND into ZBRND_CHK with key fprod = Z_IND-PROD_CMP4.
    if sy-subrc = 0.
      clear: ZIND_KL, ZIND_UOM, ZIND_QTY.
      split Z_IND-QUAN_COMP4 at 'KL' into ZIND_KL ZIND_UOM.
      MOVE ZIND_KL TO ZIND_QTY.
      ZIND_QTY = ( ZIND_QTY * ZBRND_CHK-PERC2 ) / 100.
      ZIND_TOT_QTY = ZIND_TOT_QTY + ZIND_QTY.
    endif.
    read table IT_REBRAND into ZBRND_CHK with key fprod = Z_IND-PROD_CMP5.
    if sy-subrc = 0.
      clear: ZIND_KL, ZIND_UOM, ZIND_QTY.
      split Z_IND-QUAN_COMP5 at 'KL' into ZIND_KL ZIND_UOM.
      MOVE ZIND_KL TO ZIND_QTY.
      ZIND_QTY = ( ZIND_QTY * ZBRND_CHK-PERC2 ) / 100.
      ZIND_TOT_QTY = ZIND_TOT_QTY + ZIND_QTY.
    endif.
    read table IT_REBRAND into ZBRND_CHK with key fprod = Z_IND-PROD_CMP6.
    if sy-subrc = 0.
      clear: ZIND_KL, ZIND_UOM, ZIND_QTY.
      split Z_IND-QUAN_COMP6 at 'KL' into ZIND_KL ZIND_UOM.
      MOVE ZIND_KL TO ZIND_QTY.
      ZIND_QTY = ( ZIND_QTY * ZBRND_CHK-PERC2 ) / 100.
      ZIND_TOT_QTY = ZIND_TOT_QTY + ZIND_QTY.
    endif.
    read table IT_REBRAND into ZBRND_CHK with key fprod = Z_IND-PROD_CMP7.
    if sy-subrc = 0.
      clear: ZIND_KL, ZIND_UOM, ZIND_QTY.
      split Z_IND-QUAN_COMP7 at 'KL' into ZIND_KL ZIND_UOM.
      MOVE ZIND_KL TO ZIND_QTY.
      ZIND_QTY = ( ZIND_QTY * ZBRND_CHK-PERC2 ) / 100.
      ZIND_TOT_QTY = ZIND_TOT_QTY + ZIND_QTY.
    endif.
    read table IT_REBRAND into ZBRND_CHK with key fprod = Z_IND-PROD_CMP8.
    if sy-subrc = 0.
      clear: ZIND_KL, ZIND_UOM, ZIND_QTY.
      split Z_IND-QUAN_COMP8 at 'KL' into ZIND_KL ZIND_UOM.
      MOVE ZIND_KL TO ZIND_QTY.
      ZIND_QTY = ( ZIND_QTY * ZBRND_CHK-PERC2 ) / 100.
      ZIND_TOT_QTY = ZIND_TOT_QTY + ZIND_QTY.
    endif.
  endloop.
  ZIND_TOT_QTY  = ZIND_TOT_QTY + ZTOT_QTY.

  data zval_type type bwtar_d.
  if CUST_INDENT-KDGRP = 'Z1'.
    move 'AGCL-NOVAL' to zval_type.
  endif.
  if CUST_INDENT-KDGRP = 'IP' . "OR CUST_INDENT-KDGRP = 'DI'.
    move 'IPPL-NOVAL' to zval_type.
  endif.
  if CUST_INDENT-KDGRP = 'BP'.
    move 'BPCL-NOVAL' to zval_type.
  endif.
  if CUST_INDENT-KDGRP = 'RI'.
    move 'RIL-NOVAL' to zval_type.
  endif.
  if CUST_INDENT-KDGRP = 'EO'.
    move 'ESSR-NOVAL' to zval_type.
  endif.
  if CUST_INDENT-KDGRP = 'HP'.
    move 'HPCL-NOVAL' to zval_type.
  endif.
  if CUST_INDENT-KDGRP = 'IO'.
    move 'IOCL-NOVAL' to zval_type.
  endif.
  if CUST_INDENT-KDGRP = 'SH'.
    move 'SHEL-NOVAL' to zval_type.
  endif.


  if ZTOT_QTY > 0.
    clear: ZBRND_CHK, it_mchbo1, it_mchbo1[], zmchbo1.
    read table IT_REBRAND into ZBRND_CHK index 1.
    select * from mchbo1 into zmchbo1 where
     matnr = ZBRND_CHK-IMAT2 and werks = CUST_INDENT-DEPOT and
       charg = zval_type and msehi = 'L'.
      if sy-subrc = 0.
        select count(*) from T001L where werks = CUST_INDENT-DEPOT
          and lgort = zmchbo1-lgort and oib_tnkassign = 'T'.
        if sy-subrc = 0.
          append zmchbo1 to it_mchbo1.
        endif.
      endif.
    endselect.

    clear ztot_clabs.
    loop at it_mchbo1 into zmchbo1.
      ztot_clabs = ztot_clabs + zmchbo1-clabs + zmchbo1-cinsm.
    endloop.
  endif.
  clear zstk_err.

  if ZTOT_QTY > 0 and CUST_INDENT-BEGDA > SY-DATUM.
    zstk_err = 'X'.
    move 'Indent of ethanol cannot be placed for future date' to err_msg.
  endif.

  ZIND_TOT_QTY = ZIND_TOT_QTY * 1000.
  if ZTOT_QTY > 0 and ZIND_TOT_QTY > ZTOT_CLABS and zstk_err = ' '.
    zstk_err = 'X'.
    clear stk_tx.
    move ZTOT_CLABS to stk_tx. condense stk_tx.
    IF B2B_CALL = ' '.
      err_msg = 'Ethanol stock is not sufficient.'.
      concatenate err_msg   'Available Ethanol stock-' stk_tx 'Ltrs.' into
        err_msg   separated by l_cr.
      clear stk_tx.
      move ZIND_TOT_QTY to stk_tx. condense stk_tx.
      concatenate err_msg   'Total indent quantity-' stk_tx 'Ltrs.' into
        err_msg   separated by l_lf.
    ENDIF.
    IF B2B_CALL = 'X'.
      concatenate 'Available Ethanol stock-' stk_tx 'Ltrs' into
        err_msg   separated by space.
      clear stk_tx.
      move ZIND_TOT_QTY to stk_tx. condense stk_tx.
      concatenate err_msg   'is less than Total indent quantity-' stk_tx 'Ltrs.' into
        err_msg   separated by space.
    ENDIF.
  endif.


ENDFUNCTION.