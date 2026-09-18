/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19  Distrib 10.11.14-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: radius
-- ------------------------------------------------------
-- Server version	10.11.14-MariaDB-0ubuntu0.24.04.1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `batch_history`
--

DROP TABLE IF EXISTS `batch_history`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `batch_history` (
  `id` int(32) NOT NULL AUTO_INCREMENT,
  `batch_name` varchar(64) DEFAULT NULL COMMENT 'an identifier name of the batch instance',
  `batch_description` varchar(256) DEFAULT NULL COMMENT 'general description of the entry',
  `hotspot_id` int(32) DEFAULT 0 COMMENT 'the hotspot business id associated with this batch instance',
  `batch_status` varchar(128) NOT NULL DEFAULT 'Pending' COMMENT 'the batch status',
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `batch_name` (`batch_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billing_history`
--

DROP TABLE IF EXISTS `billing_history`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `billing_history` (
  `id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(128) DEFAULT NULL,
  `planId` int(32) DEFAULT NULL,
  `billAmount` varchar(200) DEFAULT NULL,
  `billAction` varchar(128) NOT NULL DEFAULT 'Unavailable',
  `billPerformer` varchar(200) DEFAULT NULL,
  `billReason` varchar(200) DEFAULT NULL,
  `paymentmethod` varchar(200) DEFAULT NULL,
  `cash` varchar(200) DEFAULT NULL,
  `creditcardname` varchar(200) DEFAULT NULL,
  `creditcardnumber` varchar(200) DEFAULT NULL,
  `creditcardverification` varchar(200) DEFAULT NULL,
  `creditcardtype` varchar(200) DEFAULT NULL,
  `creditcardexp` varchar(200) DEFAULT NULL,
  `coupon` varchar(200) DEFAULT NULL,
  `discount` varchar(200) DEFAULT NULL,
  `notes` varchar(200) DEFAULT NULL,
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billing_merchant`
--

DROP TABLE IF EXISTS `billing_merchant`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `billing_merchant` (
  `id` int(8) NOT NULL AUTO_INCREMENT,
  `username` varchar(128) NOT NULL DEFAULT '',
  `password` varchar(128) NOT NULL DEFAULT '',
  `mac` varchar(200) NOT NULL DEFAULT '',
  `pin` varchar(200) NOT NULL DEFAULT '',
  `txnId` varchar(200) NOT NULL DEFAULT '',
  `planName` varchar(128) NOT NULL DEFAULT '',
  `planId` int(32) NOT NULL,
  `quantity` varchar(200) NOT NULL DEFAULT '',
  `business_email` varchar(200) NOT NULL DEFAULT '',
  `business_id` varchar(200) NOT NULL DEFAULT '',
  `txn_type` varchar(200) NOT NULL DEFAULT '',
  `txn_id` varchar(200) NOT NULL DEFAULT '',
  `payment_type` varchar(200) NOT NULL DEFAULT '',
  `payment_tax` varchar(200) NOT NULL DEFAULT '',
  `payment_cost` varchar(200) NOT NULL DEFAULT '',
  `payment_fee` varchar(200) NOT NULL DEFAULT '',
  `payment_total` varchar(200) NOT NULL DEFAULT '',
  `payment_currency` varchar(200) NOT NULL DEFAULT '',
  `first_name` varchar(200) NOT NULL DEFAULT '',
  `last_name` varchar(200) NOT NULL DEFAULT '',
  `payer_email` varchar(200) NOT NULL DEFAULT '',
  `payer_address_name` varchar(200) NOT NULL DEFAULT '',
  `payer_address_street` varchar(200) NOT NULL DEFAULT '',
  `payer_address_country` varchar(200) NOT NULL DEFAULT '',
  `payer_address_country_code` varchar(200) NOT NULL DEFAULT '',
  `payer_address_city` varchar(200) NOT NULL DEFAULT '',
  `payer_address_state` varchar(200) NOT NULL DEFAULT '',
  `payer_address_zip` varchar(200) NOT NULL DEFAULT '',
  `payment_date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `payment_status` varchar(200) NOT NULL DEFAULT '',
  `pending_reason` varchar(200) NOT NULL DEFAULT '',
  `reason_code` varchar(200) NOT NULL DEFAULT '',
  `receipt_ID` varchar(200) NOT NULL DEFAULT '',
  `payment_address_status` varchar(200) NOT NULL DEFAULT '',
  `vendor_type` varchar(200) NOT NULL DEFAULT '',
  `payer_status` varchar(200) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billing_paypal`
--

DROP TABLE IF EXISTS `billing_paypal`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `billing_paypal` (
  `id` int(8) NOT NULL AUTO_INCREMENT,
  `username` varchar(128) DEFAULT NULL,
  `password` varchar(128) DEFAULT NULL,
  `mac` varchar(200) DEFAULT NULL,
  `pin` varchar(200) DEFAULT NULL,
  `txnId` varchar(200) DEFAULT NULL,
  `planName` varchar(128) DEFAULT NULL,
  `planId` varchar(200) DEFAULT NULL,
  `quantity` varchar(200) DEFAULT NULL,
  `receiver_email` varchar(200) DEFAULT NULL,
  `business` varchar(200) DEFAULT NULL,
  `tax` varchar(200) DEFAULT NULL,
  `mc_gross` varchar(200) DEFAULT NULL,
  `mc_fee` varchar(200) DEFAULT NULL,
  `mc_currency` varchar(200) DEFAULT NULL,
  `first_name` varchar(200) DEFAULT NULL,
  `last_name` varchar(200) DEFAULT NULL,
  `payer_email` varchar(200) DEFAULT NULL,
  `address_name` varchar(200) DEFAULT NULL,
  `address_street` varchar(200) DEFAULT NULL,
  `address_country` varchar(200) DEFAULT NULL,
  `address_country_code` varchar(200) DEFAULT NULL,
  `address_city` varchar(200) DEFAULT NULL,
  `address_state` varchar(200) DEFAULT NULL,
  `address_zip` varchar(200) DEFAULT NULL,
  `payment_date` datetime DEFAULT NULL,
  `payment_status` varchar(200) DEFAULT NULL,
  `payment_address_status` varchar(200) DEFAULT NULL,
  `payer_status` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billing_plans`
--

DROP TABLE IF EXISTS `billing_plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `billing_plans` (
  `id` int(8) NOT NULL AUTO_INCREMENT,
  `planName` varchar(128) DEFAULT NULL,
  `planId` varchar(128) DEFAULT NULL,
  `planType` varchar(128) DEFAULT NULL,
  `planTimeBank` varchar(128) DEFAULT NULL,
  `planTimeType` varchar(128) DEFAULT NULL,
  `planTimeRefillCost` varchar(128) DEFAULT NULL,
  `planBandwidthUp` varchar(128) DEFAULT NULL,
  `planBandwidthDown` varchar(128) DEFAULT NULL,
  `planTrafficTotal` varchar(128) DEFAULT NULL,
  `planTrafficUp` varchar(128) DEFAULT NULL,
  `planTrafficDown` varchar(128) DEFAULT NULL,
  `planTrafficRefillCost` varchar(128) DEFAULT NULL,
  `planRecurring` varchar(128) DEFAULT NULL,
  `planRecurringPeriod` varchar(128) DEFAULT NULL,
  `planRecurringBillingSchedule` varchar(128) NOT NULL DEFAULT 'Fixed',
  `planCost` varchar(128) DEFAULT NULL,
  `planSetupCost` varchar(128) DEFAULT NULL,
  `planTax` varchar(128) DEFAULT NULL,
  `planCurrency` varchar(128) DEFAULT NULL,
  `planGroup` varchar(128) DEFAULT NULL,
  `planActive` varchar(32) NOT NULL DEFAULT 'yes',
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `planName` (`planName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billing_plans_profiles`
--

DROP TABLE IF EXISTS `billing_plans_profiles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `billing_plans_profiles` (
  `id` int(32) NOT NULL AUTO_INCREMENT,
  `plan_name` varchar(128) NOT NULL COMMENT 'the name of the plan',
  `profile_name` varchar(256) DEFAULT NULL COMMENT 'the profile/group name',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `billing_rates`
--

DROP TABLE IF EXISTS `billing_rates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `billing_rates` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `rateName` varchar(128) NOT NULL DEFAULT '',
  `rateType` varchar(128) NOT NULL DEFAULT '',
  `rateCost` int(32) NOT NULL DEFAULT 0,
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `rateName` (`rateName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `hotspots`
--

DROP TABLE IF EXISTS `hotspots`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `hotspots` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `name` varchar(200) DEFAULT NULL,
  `mac` varchar(200) DEFAULT NULL,
  `geocode` varchar(200) DEFAULT NULL,
  `owner` varchar(200) DEFAULT NULL,
  `email_owner` varchar(200) DEFAULT NULL,
  `manager` varchar(200) DEFAULT NULL,
  `email_manager` varchar(200) DEFAULT NULL,
  `address` varchar(200) DEFAULT NULL,
  `company` varchar(200) DEFAULT NULL,
  `phone1` varchar(200) DEFAULT NULL,
  `phone2` varchar(200) DEFAULT NULL,
  `type` varchar(200) DEFAULT NULL,
  `companywebsite` varchar(200) DEFAULT NULL,
  `companyemail` varchar(200) DEFAULT NULL,
  `companycontact` varchar(200) DEFAULT NULL,
  `companyphone` varchar(200) DEFAULT NULL,
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `name` (`name`),
  KEY `mac` (`mac`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `invoice`
--

DROP TABLE IF EXISTS `invoice`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `invoice` (
  `id` int(32) NOT NULL AUTO_INCREMENT,
  `user_id` int(32) DEFAULT NULL COMMENT 'user id of the userbillinfo table',
  `batch_id` int(32) DEFAULT NULL COMMENT 'batch id of the batch_history table',
  `date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `status_id` int(10) NOT NULL DEFAULT 1 COMMENT 'the status of the invoice from invoice_status',
  `type_id` int(10) NOT NULL DEFAULT 1 COMMENT 'the type of the invoice from invoice_type',
  `notes` varchar(128) NOT NULL COMMENT 'general notes/description',
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `invoice_items`
--

DROP TABLE IF EXISTS `invoice_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `invoice_items` (
  `id` int(32) NOT NULL AUTO_INCREMENT,
  `invoice_id` int(32) NOT NULL COMMENT 'invoice id of the invoices table',
  `plan_id` int(32) DEFAULT NULL COMMENT 'the plan_id of the billing_plans table',
  `amount` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT 'the amount cost of an item',
  `tax_amount` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT 'the tax amount for an item',
  `total` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT 'the total amount',
  `notes` varchar(128) NOT NULL COMMENT 'general notes/description',
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `invoice_status`
--

DROP TABLE IF EXISTS `invoice_status`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `invoice_status` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `value` varchar(32) NOT NULL DEFAULT '' COMMENT 'status value',
  `notes` varchar(128) NOT NULL COMMENT 'general notes/description',
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `invoice_type`
--

DROP TABLE IF EXISTS `invoice_type`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `invoice_type` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `value` varchar(32) NOT NULL DEFAULT '' COMMENT 'type value',
  `notes` varchar(128) NOT NULL COMMENT 'general notes/description',
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `messages`
--

DROP TABLE IF EXISTS `messages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `messages` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `type` enum('login','support','dashboard') NOT NULL,
  `content` longtext NOT NULL,
  `created_on` datetime DEFAULT NULL,
  `created_by` varchar(32) DEFAULT NULL,
  `modified_on` datetime DEFAULT NULL,
  `modified_by` varchar(32) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `nas`
--

DROP TABLE IF EXISTS `nas`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `nas` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `nasname` varchar(128) NOT NULL,
  `shortname` varchar(32) DEFAULT NULL,
  `type` varchar(30) DEFAULT 'other',
  `ports` int(5) DEFAULT NULL,
  `secret` varchar(60) NOT NULL DEFAULT 'secret',
  `server` varchar(64) DEFAULT NULL,
  `community` varchar(50) DEFAULT NULL,
  `description` varchar(200) DEFAULT 'RADIUS Client',
  PRIMARY KEY (`id`),
  KEY `nasname` (`nasname`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `node`
--

DROP TABLE IF EXISTS `node`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `node` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `time` datetime NOT NULL DEFAULT '0000-00-00 00:00:00' COMMENT 'Time of last checkin',
  `netid` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` varchar(100) NOT NULL,
  `latitude` varchar(20) NOT NULL,
  `longitude` varchar(20) NOT NULL,
  `owner_name` varchar(50) NOT NULL COMMENT 'node owner''s name',
  `owner_email` varchar(50) NOT NULL COMMENT 'node owner''s email address',
  `owner_phone` varchar(25) NOT NULL COMMENT 'node owner''s phone number',
  `owner_address` varchar(100) NOT NULL COMMENT 'node owner''s address',
  `approval_status` varchar(1) NOT NULL COMMENT 'approval status: A (accepted), R (rejected), P (pending)',
  `ip` varchar(20) NOT NULL COMMENT 'ROBIN',
  `mac` varchar(20) NOT NULL COMMENT 'ROBIN',
  `uptime` varchar(100) NOT NULL COMMENT 'ROBIN',
  `robin` varchar(20) NOT NULL COMMENT 'ROBIN: robin version',
  `batman` varchar(20) NOT NULL COMMENT 'ROBIN: batman version',
  `memfree` varchar(20) NOT NULL COMMENT 'ROBIN',
  `nbs` mediumtext NOT NULL COMMENT 'ROBIN: neighbor list',
  `gateway` varchar(20) NOT NULL COMMENT 'ROBIN: nearest gateway',
  `gw-qual` varchar(20) NOT NULL COMMENT 'ROBIN: quality of nearest gateway',
  `routes` mediumtext NOT NULL COMMENT 'ROBIN: route to nearest gateway',
  `users` char(3) NOT NULL COMMENT 'ROBIN: current number of users',
  `kbdown` varchar(20) NOT NULL COMMENT 'ROBIN: downloaded kb',
  `kbup` varchar(20) NOT NULL COMMENT 'ROBIN: uploaded kb',
  `hops` varchar(3) NOT NULL COMMENT 'ROBIN: hops to gateway',
  `rank` varchar(3) NOT NULL COMMENT 'ROBIN: ???, not currently used for anything',
  `ssid` varchar(20) NOT NULL COMMENT 'ROBIN: ssid, not currently used for anything',
  `pssid` varchar(20) NOT NULL COMMENT 'ROBIN: pssid, not currently used for anything',
  `gateway_bit` tinyint(1) NOT NULL COMMENT 'ROBIN derivation: is this node a gateway?',
  `memlow` varchar(20) NOT NULL COMMENT 'ROBIN derivation: lowest reported memory on the node',
  `usershi` char(3) NOT NULL COMMENT 'ROBIN derivation: highest number of users',
  `cpu` float NOT NULL DEFAULT 0,
  `wan_iface` varchar(128) DEFAULT NULL,
  `wan_ip` varchar(128) DEFAULT NULL,
  `wan_mac` varchar(128) DEFAULT NULL,
  `wan_gateway` varchar(128) DEFAULT NULL,
  `wifi_iface` varchar(128) DEFAULT NULL,
  `wifi_ip` varchar(128) DEFAULT NULL,
  `wifi_mac` varchar(128) DEFAULT NULL,
  `wifi_ssid` varchar(128) DEFAULT NULL,
  `wifi_key` varchar(128) DEFAULT NULL,
  `wifi_channel` varchar(128) DEFAULT NULL,
  `lan_iface` varchar(128) DEFAULT NULL,
  `lan_mac` varchar(128) DEFAULT NULL,
  `lan_ip` varchar(128) DEFAULT NULL,
  `wan_bup` varchar(128) DEFAULT NULL,
  `wan_bdown` varchar(128) DEFAULT NULL,
  `firmware` varchar(128) DEFAULT NULL,
  `firmware_revision` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `mac` (`mac`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='node database';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `operators`
--

DROP TABLE IF EXISTS `operators`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `operators` (
  `id` int(32) NOT NULL AUTO_INCREMENT,
  `username` varchar(32) NOT NULL,
  `password` varchar(95) NOT NULL,
  `firstname` varchar(32) NOT NULL,
  `lastname` varchar(32) NOT NULL,
  `title` varchar(32) NOT NULL,
  `department` varchar(32) NOT NULL,
  `company` varchar(32) NOT NULL,
  `phone1` varchar(32) NOT NULL,
  `phone2` varchar(32) NOT NULL,
  `email1` varchar(32) NOT NULL,
  `email2` varchar(32) NOT NULL,
  `messenger1` varchar(32) NOT NULL,
  `messenger2` varchar(32) NOT NULL,
  `notes` varchar(128) NOT NULL,
  `lastlogin` datetime DEFAULT '0000-00-00 00:00:00',
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  `totp_enabled` tinyint(1) NOT NULL DEFAULT 0,
  `totp_secret` varchar(64) DEFAULT NULL,
  `totp_last_counter` bigint(20) DEFAULT NULL,
  `totp_confirmed_at` datetime DEFAULT NULL,
  `totp_recovery_codes` text DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `username` (`username`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `operators_acl`
--

DROP TABLE IF EXISTS `operators_acl`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `operators_acl` (
  `id` int(32) NOT NULL AUTO_INCREMENT,
  `operator_id` int(32) NOT NULL,
  `file` varchar(128) NOT NULL,
  `access` tinyint(8) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=256 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `operators_acl_files`
--

DROP TABLE IF EXISTS `operators_acl_files`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `operators_acl_files` (
  `id` int(32) NOT NULL AUTO_INCREMENT,
  `file` varchar(128) NOT NULL,
  `category` varchar(128) NOT NULL,
  `section` varchar(128) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=145 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `payment`
--

DROP TABLE IF EXISTS `payment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `payment` (
  `id` int(32) NOT NULL AUTO_INCREMENT,
  `invoice_id` int(32) NOT NULL COMMENT 'invoice id of the invoices table',
  `amount` decimal(10,2) NOT NULL COMMENT 'the amount paid',
  `date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `type_id` int(10) NOT NULL DEFAULT 1 COMMENT 'the type of the payment from payment_type',
  `notes` varchar(128) NOT NULL COMMENT 'general notes/description',
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `payment_type`
--

DROP TABLE IF EXISTS `payment_type`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `payment_type` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `value` varchar(32) NOT NULL DEFAULT '' COMMENT 'type value',
  `notes` varchar(128) NOT NULL COMMENT 'general notes/description',
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `proxys`
--

DROP TABLE IF EXISTS `proxys`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `proxys` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `proxyname` varchar(128) DEFAULT NULL,
  `retry_delay` int(8) DEFAULT NULL,
  `retry_count` int(8) DEFAULT NULL,
  `dead_time` int(8) DEFAULT NULL,
  `default_fallback` int(8) DEFAULT NULL,
  `creationdate` datetime DEFAULT NULL,
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT NULL,
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `radacct`
--

DROP TABLE IF EXISTS `radacct`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `radacct` (
  `radacctid` bigint(21) NOT NULL AUTO_INCREMENT,
  `acctsessionid` varchar(64) NOT NULL DEFAULT '',
  `acctuniqueid` varchar(32) NOT NULL DEFAULT '',
  `username` varchar(64) NOT NULL DEFAULT '',
  `groupname` varchar(64) NOT NULL DEFAULT '',
  `realm` varchar(64) DEFAULT NULL,
  `nasipaddress` varchar(15) NOT NULL DEFAULT '',
  `nasportid` varchar(32) DEFAULT NULL,
  `nasporttype` varchar(32) DEFAULT NULL,
  `acctstarttime` datetime DEFAULT NULL,
  `acctupdatetime` datetime DEFAULT NULL,
  `acctstoptime` datetime DEFAULT NULL,
  `acctinterval` int(12) DEFAULT NULL,
  `acctsessiontime` int(12) unsigned DEFAULT NULL,
  `acctauthentic` varchar(32) DEFAULT NULL,
  `connectinfo_start` varchar(50) DEFAULT NULL,
  `connectinfo_stop` varchar(50) DEFAULT NULL,
  `acctinputoctets` bigint(20) DEFAULT NULL,
  `acctoutputoctets` bigint(20) DEFAULT NULL,
  `calledstationid` varchar(50) NOT NULL DEFAULT '',
  `callingstationid` varchar(50) NOT NULL DEFAULT '',
  `acctterminatecause` varchar(32) NOT NULL DEFAULT '',
  `servicetype` varchar(32) DEFAULT NULL,
  `framedprotocol` varchar(32) DEFAULT NULL,
  `framedipaddress` varchar(15) NOT NULL DEFAULT '',
  `framedipv6address` varchar(45) NOT NULL DEFAULT '',
  `framedipv6prefix` varchar(45) NOT NULL DEFAULT '',
  `framedinterfaceid` varchar(44) NOT NULL DEFAULT '',
  `delegatedipv6prefix` varchar(45) NOT NULL DEFAULT '',
  `class` varchar(64) DEFAULT NULL,
  PRIMARY KEY (`radacctid`),
  UNIQUE KEY `acctuniqueid` (`acctuniqueid`),
  KEY `username` (`username`),
  KEY `framedipaddress` (`framedipaddress`),
  KEY `acctsessionid` (`acctsessionid`),
  KEY `acctsessiontime` (`acctsessiontime`),
  KEY `acctstarttime` (`acctstarttime`),
  KEY `acctstoptime` (`acctstoptime`),
  KEY `nasipaddress` (`nasipaddress`),
  KEY `idx_radacct_username_time` (`username`,`acctstarttime`),
  KEY `idx_radacct_status_start` (`acctstoptime`,`acctstarttime`),
  KEY `idx_radacct_top_users` (`acctstarttime`,`username`,`acctsessiontime`,`acctinputoctets`,`acctoutputoctets`),
  KEY `framedipv6address` (`framedipv6address`),
  KEY `framedipv6prefix` (`framedipv6prefix`),
  KEY `framedinterfaceid` (`framedinterfaceid`),
  KEY `delegatedipv6prefix` (`delegatedipv6prefix`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `radcheck`
--

DROP TABLE IF EXISTS `radcheck`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `radcheck` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL DEFAULT '',
  `attribute` varchar(64) NOT NULL DEFAULT '',
  `op` char(2) NOT NULL DEFAULT ':=',
  `value` varchar(253) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `username` (`username`(32)),
  KEY `idx_radcheck_username_attr` (`username`,`attribute`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `radgroupcheck`
--

DROP TABLE IF EXISTS `radgroupcheck`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `radgroupcheck` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `groupname` varchar(64) NOT NULL DEFAULT '',
  `attribute` varchar(64) NOT NULL DEFAULT '',
  `op` char(2) NOT NULL DEFAULT '==',
  `value` varchar(253) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `groupname` (`groupname`(32))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `radgroupreply`
--

DROP TABLE IF EXISTS `radgroupreply`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `radgroupreply` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `groupname` varchar(64) NOT NULL DEFAULT '',
  `attribute` varchar(64) NOT NULL DEFAULT '',
  `op` char(2) NOT NULL DEFAULT '=',
  `value` varchar(253) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `groupname` (`groupname`(32))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `radpostauth`
--

DROP TABLE IF EXISTS `radpostauth`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `radpostauth` (
  `id` bigint(21) NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL DEFAULT '',
  `pass` varchar(64) NOT NULL DEFAULT '',
  `reply` varchar(32) NOT NULL DEFAULT '',
  `authdate` timestamp(6) NOT NULL DEFAULT current_timestamp(6),
  `class` varchar(64) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `username` (`username`),
  KEY `authdate` (`authdate`),
  KEY `idx_radpostauth_authdate` (`authdate`)
) ENGINE=InnoDB AUTO_INCREMENT=11 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `radreply`
--

DROP TABLE IF EXISTS `radreply`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `radreply` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL DEFAULT '',
  `attribute` varchar(64) NOT NULL DEFAULT '',
  `op` char(2) NOT NULL DEFAULT '=',
  `value` varchar(253) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `username` (`username`(32))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `radusergroup`
--

DROP TABLE IF EXISTS `radusergroup`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `radusergroup` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(64) NOT NULL DEFAULT '',
  `groupname` varchar(64) NOT NULL DEFAULT '',
  `priority` int(11) NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `username` (`username`(32))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `realms`
--

DROP TABLE IF EXISTS `realms`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `realms` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `realmname` varchar(128) DEFAULT NULL,
  `type` varchar(32) DEFAULT NULL,
  `authhost` varchar(256) DEFAULT NULL,
  `accthost` varchar(256) DEFAULT NULL,
  `secret` varchar(128) DEFAULT NULL,
  `ldflag` varchar(64) DEFAULT NULL,
  `nostrip` int(8) DEFAULT NULL,
  `hints` int(8) DEFAULT NULL,
  `notrealm` int(8) DEFAULT NULL,
  `creationdate` datetime DEFAULT NULL,
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT NULL,
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `userbillinfo`
--

DROP TABLE IF EXISTS `userbillinfo`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `userbillinfo` (
  `id` int(8) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(128) DEFAULT NULL,
  `planName` varchar(128) DEFAULT NULL,
  `hotspot_id` int(32) DEFAULT NULL,
  `hotspotlocation` varchar(32) DEFAULT NULL,
  `contactperson` varchar(200) DEFAULT NULL,
  `company` varchar(200) DEFAULT NULL,
  `email` varchar(200) DEFAULT NULL,
  `phone` varchar(200) DEFAULT NULL,
  `address` varchar(200) DEFAULT NULL,
  `city` varchar(200) DEFAULT NULL,
  `state` varchar(200) DEFAULT NULL,
  `country` varchar(100) DEFAULT NULL,
  `zip` varchar(200) DEFAULT NULL,
  `paymentmethod` varchar(200) DEFAULT NULL,
  `cash` varchar(200) DEFAULT NULL,
  `creditcardname` varchar(200) DEFAULT NULL,
  `creditcardnumber` varchar(200) DEFAULT NULL,
  `creditcardverification` varchar(200) DEFAULT NULL,
  `creditcardtype` varchar(200) DEFAULT NULL,
  `creditcardexp` varchar(200) DEFAULT NULL,
  `notes` varchar(200) DEFAULT NULL,
  `changeuserbillinfo` varchar(128) DEFAULT NULL,
  `lead` varchar(200) DEFAULT NULL,
  `coupon` varchar(200) DEFAULT NULL,
  `ordertaker` varchar(200) DEFAULT NULL,
  `billstatus` varchar(200) DEFAULT NULL,
  `lastbill` date NOT NULL DEFAULT '0000-00-00',
  `nextbill` date NOT NULL DEFAULT '0000-00-00',
  `nextinvoicedue` int(32) DEFAULT NULL,
  `billdue` int(32) DEFAULT NULL,
  `postalinvoice` varchar(8) DEFAULT NULL,
  `faxinvoice` varchar(8) DEFAULT NULL,
  `emailinvoice` varchar(8) DEFAULT NULL,
  `batch_id` int(32) DEFAULT NULL,
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `username` (`username`),
  KEY `planname` (`planName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `userinfo`
--

DROP TABLE IF EXISTS `userinfo`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `userinfo` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(128) DEFAULT NULL,
  `firstname` varchar(200) DEFAULT NULL,
  `lastname` varchar(200) DEFAULT NULL,
  `email` varchar(200) DEFAULT NULL,
  `department` varchar(200) DEFAULT NULL,
  `company` varchar(200) DEFAULT NULL,
  `workphone` varchar(200) DEFAULT NULL,
  `homephone` varchar(200) DEFAULT NULL,
  `mobilephone` varchar(200) DEFAULT NULL,
  `address` varchar(200) DEFAULT NULL,
  `city` varchar(200) DEFAULT NULL,
  `state` varchar(200) DEFAULT NULL,
  `country` varchar(100) DEFAULT NULL,
  `zip` varchar(200) DEFAULT NULL,
  `notes` varchar(200) DEFAULT NULL,
  `changeuserinfo` varchar(128) DEFAULT NULL,
  `portalloginpassword` varchar(128) DEFAULT '',
  `enableportallogin` int(32) DEFAULT 0,
  `creationdate` datetime DEFAULT '0000-00-00 00:00:00',
  `creationby` varchar(128) DEFAULT NULL,
  `updatedate` datetime DEFAULT '0000-00-00 00:00:00',
  `updateby` varchar(128) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-09-07 15:14:49
