SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;

SET search_path = public, pg_catalog;

CREATE TYPE plan_type AS ENUM (
    'ios-monthly',
    'ios-annual',
    'all-monthly',
    'all-annual',
    'android-monthly',
    'android-annual'
);

CREATE TYPE receipt_type AS ENUM (
    'ios',
    'android',
    'stripe'
);

SET default_with_oids = false;

/*****************************************************/
/******************** CERTIFICATES *******************/
/*****************************************************/

CREATE TABLE certificates (
    serial text NOT NULL,
    source_id text NOT NULL,
    user_id text NOT NULL,
    revoked boolean DEFAULT false NOT NULL,
    assigned boolean DEFAULT false NOT NULL,
    p12_encrypted text NOT NULL
);

CREATE INDEX user_id_index ON certificates USING btree (user_id);

CREATE INDEX unassigned_index ON certificates USING btree (assigned, source_id);
    
/*****************************************************/
/*********************** USERS ***********************/
/*****************************************************/

CREATE TABLE users (
    id text,
    email text,
    email_encrypted text,
    password text,
    stripe_id text,
    email_confirmed boolean DEFAULT false NOT NULL,
    email_confirm_code text NOT NULL,
    change_email text,
    password_reset_code text,
    month_usage_megabytes integer DEFAULT '0' NOT NULL,
    month_usage_update timestamp with time zone DEFAULT now() NOT NULL,
    referral_code text NOT NULL DEFAULT upper(substring(md5(random()::text) from 0 for 10)),
    referred_by text,
    create_date timestamp with time zone DEFAULT now() NOT NULL,
    delete_date timestamp with time zone,
    delete_reason text,
    banned boolean DEFAULT false NOT NULL,
    do_not_email boolean DEFAULT false NOT NULL,
    do_not_email_code text DEFAULT upper(substring(md5(random()::text) from 0 for 20)) NOT NULL
);

ALTER TABLE ONLY users
    ADD CONSTRAINT users_email_key UNIQUE (email);

ALTER TABLE ONLY users
    ADD CONSTRAINT users_id_key UNIQUE (id);
    
/*****************************************************/
/******************* ADMIN USERS *******************/
/*****************************************************/

CREATE TABLE admin_users (
    email text NOT NULL,
    password text NOT NULL,
    email_confirmed boolean DEFAULT false NOT NULL,
    email_confirm_code text NOT NULL,
    password_reset_code text
);

ALTER TABLE ONLY admin_users
    ADD CONSTRAINT admin_users_email_pkey PRIMARY KEY (email);
    
/*****************************************************/
/******************* SUPPORT USERS *******************/
/*****************************************************/

CREATE TABLE support_users (
    email text NOT NULL,
    password text NOT NULL,
    email_confirmed boolean DEFAULT false NOT NULL,
    email_confirm_code text NOT NULL,
    password_reset_code text
);

ALTER TABLE ONLY support_users
    ADD CONSTRAINT support_users_email_pkey PRIMARY KEY (email);

/*****************************************************/
/******************* SUBSCRIPTIONS *******************/
/*****************************************************/

CREATE TABLE subscriptions (
    user_id text NOT NULL,
    receipt_id text NOT NULL,
    receipt_type receipt_type NOT NULL,
    plan_type plan_type NOT NULL,
    expiration_date timestamp with time zone NOT NULL,
    cancellation_date timestamp with time zone,
    receipt_data text,
    in_trial boolean DEFAULT true NOT NULL,
    failed_last_check boolean DEFAULT false NOT NULL,
    renew_enabled boolean DEFAULT true NOT NULL,
    updated timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_receipt_id_pkey PRIMARY KEY (receipt_id);

ALTER TABLE ONLY subscriptions
    ADD CONSTRAINT subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON UPDATE CASCADE;
    
CREATE INDEX subscriptions_user_id_index ON subscriptions USING btree (user_id);

/*****************************************************/
/************************ ROLES **********************/
/*****************************************************/

CREATE USER main WITH ENCRYPTED PASSWORD '{{ main_password }}';
GRANT SELECT, UPDATE(assigned) ON certificates TO main;
GRANT SELECT, INSERT, UPDATE ON subscriptions TO main;
GRANT SELECT, INSERT, UPDATE ON users TO main;

CREATE USER helper WITH ENCRYPTED PASSWORD '{{ helper_password }}';
GRANT SELECT(user_id, cancellation_date, expiration_date) ON subscriptions TO helper;
GRANT SELECT(source_id, user_id, revoked, assigned) ON certificates TO helper;
GRANT SELECT(id, month_usage_megabytes, month_usage_update), UPDATE(month_usage_megabytes, month_usage_update) ON users TO helper;

CREATE USER renewer WITH ENCRYPTED PASSWORD '{{ renewer_password }}';
GRANT SELECT, UPDATE ON subscriptions TO renewer;

CREATE USER support WITH ENCRYPTED PASSWORD '{{ support_password }}';
GRANT SELECT(id, email, email_encrypted, stripe_id, create_date, referred_by, delete_date, delete_reason, banned, month_usage_megabytes, month_usage_update, email_confirmed, do_not_email, do_not_email_code) ON users TO support;
GRANT SELECT ON subscriptions TO support;
GRANT SELECT, UPDATE, INSERT ON support_users TO support;

CREATE USER webhook WITH ENCRYPTED PASSWORD '{{ webhook_password }}';
GRANT SELECT(id, email, email_encrypted, stripe_id, email_confirmed, referred_by, referral_code, do_not_email, do_not_email_code) ON users TO webhook;
GRANT SELECT(user_id, receipt_type, plan_type, expiration_date, cancellation_date, in_trial, failed_last_check, renew_enabled, updated) ON subscriptions TO webhook;

CREATE USER debug WITH ENCRYPTED PASSWORD '{{ debug_password }}';
GRANT SELECT ON admin_users TO debug;
GRANT SELECT(serial, source_id, user_id, revoked, assigned) ON certificates TO debug;
GRANT SELECT(user_id, receipt_type, plan_type, expiration_date, cancellation_date, in_trial, failed_last_check, renew_enabled, updated) ON subscriptions TO debug;
GRANT SELECT ON support_users TO debug;
GRANT SELECT(id, email_confirmed, month_usage_megabytes, month_usage_update, do_not_email, do_not_email_code) ON users TO debug;