CREATE TABLE `counters` (
	`name` text PRIMARY KEY,
	`value` integer NOT NULL
);
--> statement-breakpoint
-- Existing rows are numbered in the order the old timestamp cursor read them; every write after
-- this sets `version` itself, so the default is never relied on.
ALTER TABLE `profiles` ADD `version` integer NOT NULL DEFAULT 0;--> statement-breakpoint
UPDATE `profiles` SET `version` = (SELECT count(*) FROM `profiles` AS `earlier` WHERE (`earlier`.`updated_at`, `earlier`.`id`) <= (`profiles`.`updated_at`, `profiles`.`id`));--> statement-breakpoint
INSERT INTO `counters` (`name`, `value`) SELECT 'profiles', coalesce(max(`version`), 0) FROM `profiles`;--> statement-breakpoint
DROP INDEX IF EXISTS `profiles_updated`;--> statement-breakpoint
CREATE UNIQUE INDEX `profiles_version` ON `profiles` (`version`);
