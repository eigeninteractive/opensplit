CREATE TABLE `counter` (
	`name` text PRIMARY KEY NOT NULL,
	`value` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `entries` (
	`id` text PRIMARY KEY NOT NULL,
	`kind` text DEFAULT 'expense' NOT NULL,
	`description` text DEFAULT '' NOT NULL,
	`category_id` text,
	`currency` text NOT NULL,
	`amount_minor` integer NOT NULL,
	`entry_date` text NOT NULL,
	`occurred_at` text,
	`time_zone` text,
	`split_kind` text DEFAULT 'equal' NOT NULL,
	`fx_rate` real,
	`fx_source` text,
	`fx_at` text,
	`notes` text,
	`created_by` text NOT NULL,
	`client_key` text,
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	`seq` integer NOT NULL,
	FOREIGN KEY (`created_by`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "entries_amount_positive" CHECK("entries"."amount_minor" > 0),
	CONSTRAINT "entries_fx_rate_positive" CHECK("entries"."fx_rate" is null or "entries"."fx_rate" > 0),
	CONSTRAINT "entries_moment_complete" CHECK(("entries"."occurred_at" is null) = ("entries"."time_zone" is null)),
	CONSTRAINT "entries_fx_complete" CHECK(("entries"."fx_rate" is null) = ("entries"."fx_source" is null) and ("entries"."fx_rate" is null) = ("entries"."fx_at" is null))
);
--> statement-breakpoint
CREATE INDEX `entries_seq` ON `entries` (`seq`);--> statement-breakpoint
CREATE UNIQUE INDEX `entries_client_key` ON `entries` (`client_key`);--> statement-breakpoint
CREATE TABLE `entry_payers` (
	`entry_id` text NOT NULL,
	`member_id` text NOT NULL,
	`amount_minor` integer NOT NULL,
	PRIMARY KEY(`entry_id`, `member_id`),
	FOREIGN KEY (`entry_id`) REFERENCES `entries`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`member_id`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "entry_payers_amount_positive" CHECK("entry_payers"."amount_minor" > 0)
);
--> statement-breakpoint
CREATE TABLE `entry_shares` (
	`entry_id` text NOT NULL,
	`member_id` text NOT NULL,
	`amount_minor` integer NOT NULL,
	`weight_micros` integer,
	PRIMARY KEY(`entry_id`, `member_id`),
	FOREIGN KEY (`entry_id`) REFERENCES `entries`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`member_id`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "entry_shares_amount_not_negative" CHECK("entry_shares"."amount_minor" >= 0)
);
--> statement-breakpoint
CREATE TABLE `events` (
	`id` text PRIMARY KEY NOT NULL,
	`actor_id` text,
	`created_at` text NOT NULL,
	`kind` text NOT NULL,
	`subject_id` text,
	`payload` text NOT NULL,
	`seq` integer NOT NULL,
	`ordinal` integer DEFAULT 0 NOT NULL,
	FOREIGN KEY (`actor_id`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE UNIQUE INDEX `events_position` ON `events` (`seq`,`ordinal`);--> statement-breakpoint
CREATE INDEX `events_subject` ON `events` (`subject_id`,`created_at`);--> statement-breakpoint
CREATE TABLE `group_link` (
	`id` text PRIMARY KEY NOT NULL,
	`token` text NOT NULL,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL,
	`expires_at` text NOT NULL,
	`revoked_at` text,
	FOREIGN KEY (`created_by`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE TABLE `invites` (
	`token` text PRIMARY KEY NOT NULL,
	`member_id` text NOT NULL,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL,
	`expires_at` text NOT NULL,
	`redeemed_at` text,
	`redeemed_by` text,
	FOREIGN KEY (`member_id`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action,
	FOREIGN KEY (`created_by`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action
);
--> statement-breakpoint
CREATE INDEX `invites_member` ON `invites` (`member_id`);--> statement-breakpoint
CREATE TABLE `members` (
	`id` text PRIMARY KEY NOT NULL,
	`profile_id` text,
	`display_name` text NOT NULL,
	`upi_vpa` text,
	`joined_at` text NOT NULL,
	`left_at` text,
	`updated_at` text NOT NULL,
	`seq` integer NOT NULL,
	CONSTRAINT "members_name_not_blank" CHECK(length(trim("members"."display_name")) > 0)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `members_profile` ON `members` (`profile_id`);--> statement-breakpoint
CREATE INDEX `members_seq` ON `members` (`seq`);--> statement-breakpoint
CREATE TABLE `meta` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`default_currency` text NOT NULL,
	`is_direct` integer DEFAULT false NOT NULL,
	`simplify_debts` integer DEFAULT true NOT NULL,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL,
	`archived_at` text,
	`updated_at` text NOT NULL,
	`seq` integer NOT NULL,
	FOREIGN KEY (`created_by`) REFERENCES `members`(`id`) ON UPDATE no action ON DELETE no action,
	CONSTRAINT "meta_name_not_blank" CHECK(length(trim("meta"."name")) > 0)
);
--> statement-breakpoint
CREATE TABLE `outbox` (
	`id` integer PRIMARY KEY AUTOINCREMENT NOT NULL,
	`kind` text NOT NULL,
	`payload` text NOT NULL,
	`attempts` integer DEFAULT 0 NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `schedule` (
	`name` text PRIMARY KEY NOT NULL,
	`due_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `tombstone` (
	`id` text PRIMARY KEY NOT NULL,
	`group_id` text NOT NULL,
	`purged_at` text NOT NULL,
	`seq` integer NOT NULL
);
