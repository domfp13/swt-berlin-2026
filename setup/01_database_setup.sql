/* ============================================================================
   SWT Berlin 2026 - Cortex Code demo
   Script 01 - Database setup (run this FIRST)
   ----------------------------------------------------------------------------
   Creates the demo database. Everything lives in SWT_BERLIN_2026.PUBLIC.
   Uses the existing ADAPTIVE_WH warehouse (no warehouse is created here).

   Run as SYSADMIN.
   ============================================================================ */

USE ROLE SYSADMIN;
USE WAREHOUSE ADAPTIVE_WH;

CREATE DATABASE IF NOT EXISTS SWT_BERLIN_2026
  COMMENT = 'SWT Berlin 2026 - Cortex Code demo';

USE DATABASE SWT_BERLIN_2026;
USE SCHEMA PUBLIC;

SELECT CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA();
