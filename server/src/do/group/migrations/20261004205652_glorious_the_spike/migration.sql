CREATE TABLE `counter` (
	`name` text PRIMARY KEY,
	`value` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `entries` (
	`id` text PRIMARY KEY,
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
	`created_at` text NOT NULL,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	`seq` integer NOT NULL,
	CONSTRAINT `fk_entries_created_by_members_id_fk` FOREIGN KEY (`created_by`) REFERENCES `members`(`id`),
	CONSTRAINT "entries_amount_positive" CHECK("amount_minor" > 0),
	CONSTRAINT "entries_fx_rate_positive" CHECK("fx_rate" is null or "fx_rate" > 0),
	CONSTRAINT "entries_moment_complete" CHECK(("occurred_at" is null) = ("time_zone" is null)),
	CONSTRAINT "entries_fx_complete" CHECK(("fx_rate" is null) = ("fx_source" is null) and ("fx_rate" is null) = ("fx_at" is null))
);
--> statement-breakpoint
CREATE TABLE `entry_payers` (
	`entry_id` text NOT NULL,
	`member_id` text NOT NULL,
	`amount_minor` integer NOT NULL,
	CONSTRAINT `entry_payers_pk` PRIMARY KEY(`entry_id`, `member_id`),
	CONSTRAINT `fk_entry_payers_entry_id_entries_id_fk` FOREIGN KEY (`entry_id`) REFERENCES `entries`(`id`),
	CONSTRAINT `fk_entry_payers_member_id_members_id_fk` FOREIGN KEY (`member_id`) REFERENCES `members`(`id`),
	CONSTRAINT "entry_payers_amount_positive" CHECK("amount_minor" > 0)
);
--> statement-breakpoint
CREATE TABLE `entry_shares` (
	`entry_id` text NOT NULL,
	`member_id` text NOT NULL,
	`amount_minor` integer NOT NULL,
	`weight_micros` integer,
	CONSTRAINT `entry_shares_pk` PRIMARY KEY(`entry_id`, `member_id`),
	CONSTRAINT `fk_entry_shares_entry_id_entries_id_fk` FOREIGN KEY (`entry_id`) REFERENCES `entries`(`id`),
	CONSTRAINT `fk_entry_shares_member_id_members_id_fk` FOREIGN KEY (`member_id`) REFERENCES `members`(`id`),
	CONSTRAINT "entry_shares_amount_not_negative" CHECK("amount_minor" >= 0)
);
--> statement-breakpoint
CREATE TABLE `events` (
	`id` text PRIMARY KEY,
	`actor_id` text,
	`created_at` text NOT NULL,
	`kind` text NOT NULL,
	`subject_id` text,
	`entry` text,
	`member` text,
	`group` text,
	`link` text,
	`seq` integer NOT NULL,
	`ordinal` integer DEFAULT 0 NOT NULL,
	CONSTRAINT `fk_events_actor_id_members_id_fk` FOREIGN KEY (`actor_id`) REFERENCES `members`(`id`),
	CONSTRAINT "events_one_payload" CHECK(("entry" is not null) + ("member" is not null) + ("group" is not null) + ("link" is not null) = 1)
);
--> statement-breakpoint
CREATE TABLE `group_link` (
	`id` text PRIMARY KEY,
	`token` text NOT NULL,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL,
	`expires_at` text NOT NULL,
	`revoked_at` text,
	CONSTRAINT `fk_group_link_created_by_members_id_fk` FOREIGN KEY (`created_by`) REFERENCES `members`(`id`)
);
--> statement-breakpoint
CREATE TABLE `invites` (
	`token` text PRIMARY KEY,
	`member_id` text NOT NULL,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL,
	`expires_at` text NOT NULL,
	`redeemed_at` text,
	`redeemed_by` text,
	CONSTRAINT `fk_invites_member_id_members_id_fk` FOREIGN KEY (`member_id`) REFERENCES `members`(`id`),
	CONSTRAINT `fk_invites_created_by_members_id_fk` FOREIGN KEY (`created_by`) REFERENCES `members`(`id`)
);
--> statement-breakpoint
CREATE TABLE `members` (
	`id` text PRIMARY KEY,
	`profile_id` text,
	`display_name` text NOT NULL,
	`upi_vpa` text,
	`joined_at` text NOT NULL,
	`left_at` text,
	`updated_at` text NOT NULL,
	`seq` integer NOT NULL,
	CONSTRAINT "members_name_not_blank" CHECK(length(trim("display_name")) > 0)
);
--> statement-breakpoint
CREATE TABLE `meta` (
	`id` text PRIMARY KEY,
	`name` text NOT NULL,
	`default_currency` text NOT NULL,
	`is_direct` integer DEFAULT false NOT NULL,
	`simplify_debts` integer DEFAULT true NOT NULL,
	`avatar_kind` text DEFAULT 'initials' NOT NULL,
	`avatar_color` text,
	`avatar_emoji` text,
	`avatar_icon` text,
	`avatar_photo` text,
	`cover_kind` text DEFAULT 'generated' NOT NULL,
	`cover_photo` text,
	`created_by` text NOT NULL,
	`created_at` text NOT NULL,
	`last_activity_at` integer NOT NULL,
	`archived_at` text,
	`updated_at` text NOT NULL,
	`seq` integer NOT NULL,
	CONSTRAINT `fk_meta_created_by_members_id_fk` FOREIGN KEY (`created_by`) REFERENCES `members`(`id`),
	CONSTRAINT "meta_name_not_blank" CHECK(length(trim("name")) > 0),
	CONSTRAINT "meta_avatar_emoji" CHECK(("avatar_kind" = 'emoji') = ("avatar_emoji" is not null)),
	CONSTRAINT "meta_avatar_icon" CHECK(("avatar_kind" = 'icon') = ("avatar_icon" is not null)),
	CONSTRAINT "meta_avatar_photo" CHECK(("avatar_kind" = 'photo') = ("avatar_photo" is not null)),
	CONSTRAINT "meta_cover_photo" CHECK(("cover_kind" = 'photo') = ("cover_photo" is not null))
);
--> statement-breakpoint
CREATE TABLE `outbox` (
	`id` integer PRIMARY KEY AUTOINCREMENT,
	`kind` text NOT NULL,
	`payload` text NOT NULL,
	`attempts` integer DEFAULT 0 NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `schedule` (
	`name` text PRIMARY KEY,
	`due_at` integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE `tombstone` (
	`id` text PRIMARY KEY,
	`group_id` text NOT NULL,
	`purged_at` text NOT NULL,
	`seq` integer NOT NULL
);
--> statement-breakpoint
CREATE INDEX `entries_seq` ON `entries` (`seq`);--> statement-breakpoint
CREATE UNIQUE INDEX `events_position` ON `events` (`seq`,`ordinal`);--> statement-breakpoint
CREATE INDEX `events_subject` ON `events` (`subject_id`,`created_at`);--> statement-breakpoint
CREATE INDEX `invites_member` ON `invites` (`member_id`);--> statement-breakpoint
CREATE UNIQUE INDEX `members_profile` ON `members` (`profile_id`);--> statement-breakpoint
CREATE INDEX `members_seq` ON `members` (`seq`);