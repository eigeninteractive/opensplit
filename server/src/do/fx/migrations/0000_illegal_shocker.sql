CREATE TABLE `backfill_requests` (
	`as_of` text PRIMARY KEY NOT NULL,
	`attempted_at` integer NOT NULL,
	`attempts` integer DEFAULT 1 NOT NULL
);
--> statement-breakpoint
CREATE TABLE `fx_rates` (
	`as_of` text NOT NULL,
	`currency` text NOT NULL,
	`rate` real NOT NULL,
	`source` text NOT NULL,
	`created_at` text NOT NULL,
	PRIMARY KEY(`as_of`, `currency`)
);
--> statement-breakpoint
CREATE INDEX `fx_rates_currency` ON `fx_rates` (`currency`,`as_of`);--> statement-breakpoint
CREATE TABLE `provider_health` (
	`name` text PRIMARY KEY NOT NULL,
	`last_attempt_at` text,
	`last_success_at` text,
	`last_error` text
);
