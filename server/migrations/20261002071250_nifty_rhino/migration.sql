CREATE TABLE `device_tokens` (
	`token` text PRIMARY KEY,
	`profile_id` text NOT NULL,
	`platform` text NOT NULL,
	`updated_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `link_tokens` (
	`token` text PRIMARY KEY,
	`group_id` text NOT NULL,
	`kind` text NOT NULL,
	`created_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `memberships` (
	`profile_id` text NOT NULL,
	`group_id` text NOT NULL,
	`left_at` text,
	`updated_at` text NOT NULL,
	`version` integer NOT NULL,
	CONSTRAINT `memberships_pk` PRIMARY KEY(`profile_id`, `group_id`)
);
--> statement-breakpoint
CREATE TABLE `profiles` (
	`id` text PRIMARY KEY,
	`display_name` text,
	`upi_vpa` text,
	`avatar_kind` text DEFAULT 'initials' NOT NULL,
	`avatar_color` text,
	`avatar_emoji` text,
	`avatar_icon` text,
	`avatar_photo` text,
	`updated_at` text NOT NULL,
	`deleted_at` text,
	CONSTRAINT "profiles_avatar_emoji" CHECK(("avatar_kind" = 'emoji') = ("avatar_emoji" is not null)),
	CONSTRAINT "profiles_avatar_icon" CHECK(("avatar_kind" = 'icon') = ("avatar_icon" is not null)),
	CONSTRAINT "profiles_avatar_photo" CHECK(("avatar_kind" = 'photo') = ("avatar_photo" is not null))
);
--> statement-breakpoint
CREATE TABLE `purged_groups` (
	`group_id` text PRIMARY KEY,
	`purged_at` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `account` (
	`id` text PRIMARY KEY,
	`account_id` text NOT NULL,
	`provider_id` text NOT NULL,
	`user_id` text NOT NULL,
	`access_token` text,
	`refresh_token` text,
	`id_token` text,
	`access_token_expires_at` integer,
	`refresh_token_expires_at` integer,
	`scope` text,
	`password` text,
	`created_at` integer DEFAULT (cast(unixepoch('subsecond') * 1000 as integer)) NOT NULL,
	`updated_at` integer NOT NULL,
	CONSTRAINT `fk_account_user_id_user_id_fk` FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `session` (
	`id` text PRIMARY KEY,
	`expires_at` integer NOT NULL,
	`token` text NOT NULL UNIQUE,
	`created_at` integer DEFAULT (cast(unixepoch('subsecond') * 1000 as integer)) NOT NULL,
	`updated_at` integer NOT NULL,
	`ip_address` text,
	`user_agent` text,
	`user_id` text NOT NULL,
	CONSTRAINT `fk_session_user_id_user_id_fk` FOREIGN KEY (`user_id`) REFERENCES `user`(`id`) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE `user` (
	`id` text PRIMARY KEY,
	`name` text NOT NULL,
	`email` text NOT NULL UNIQUE,
	`email_verified` integer DEFAULT false NOT NULL,
	`image` text,
	`created_at` integer DEFAULT (cast(unixepoch('subsecond') * 1000 as integer)) NOT NULL,
	`updated_at` integer DEFAULT (cast(unixepoch('subsecond') * 1000 as integer)) NOT NULL,
	`is_anonymous` integer DEFAULT false
);
--> statement-breakpoint
CREATE TABLE `verification` (
	`id` text PRIMARY KEY,
	`identifier` text NOT NULL,
	`value` text NOT NULL,
	`expires_at` integer NOT NULL,
	`created_at` integer DEFAULT (cast(unixepoch('subsecond') * 1000 as integer)) NOT NULL,
	`updated_at` integer DEFAULT (cast(unixepoch('subsecond') * 1000 as integer)) NOT NULL
);
--> statement-breakpoint
CREATE INDEX `device_tokens_profile` ON `device_tokens` (`profile_id`);--> statement-breakpoint
CREATE INDEX `link_tokens_group` ON `link_tokens` (`group_id`);--> statement-breakpoint
CREATE INDEX `memberships_group` ON `memberships` (`group_id`);--> statement-breakpoint
CREATE INDEX `profiles_updated` ON `profiles` (`updated_at`,`id`);--> statement-breakpoint
CREATE INDEX `account_userId_idx` ON `account` (`user_id`);--> statement-breakpoint
CREATE INDEX `session_userId_idx` ON `session` (`user_id`);--> statement-breakpoint
CREATE INDEX `verification_identifier_idx` ON `verification` (`identifier`);