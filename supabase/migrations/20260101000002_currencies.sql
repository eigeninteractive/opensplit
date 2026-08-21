-- ============================================================================
-- Reference: currencies.
--
-- The exponent is NOT always 2. JPY/KRW = 0, KWD/BHD/JOD = 3. Hardcoding *100
-- in the client is a bug you will ship, so every conversion between a
-- user-facing amount and stored minor units reads it from here.
--
-- This table is also the app's single definition of "a currency we support":
-- fx_rates references it, so a rate can only exist for something the app can
-- actually format.
-- ============================================================================

create table currencies (
  code      char(3) primary key,
  exponent  smallint not null check (exponent between 0 and 4),
  symbol    text,
  name      text not null
);

insert into currencies (code, exponent, symbol, name) values
  ('INR', 2, '₹',  'Indian Rupee'),
  ('USD', 2, '$',  'US Dollar'),
  ('EUR', 2, '€',  'Euro'),
  ('GBP', 2, '£',  'Pound Sterling'),
  ('SGD', 2, 'S$', 'Singapore Dollar'),
  ('AED', 2, 'د.إ','UAE Dirham'),
  ('AUD', 2, 'A$', 'Australian Dollar'),
  ('JPY', 0, '¥',  'Japanese Yen'),
  ('KRW', 0, '₩',  'South Korean Won'),
  ('VND', 0, '₫',  'Vietnamese Dong'),
  ('IDR', 2, 'Rp', 'Indonesian Rupiah'),
  ('THB', 2, '฿',  'Thai Baht'),
  ('LKR', 2, 'Rs', 'Sri Lankan Rupee'),
  ('NPR', 2, 'Rs', 'Nepalese Rupee'),
  ('KWD', 3, 'د.ك','Kuwaiti Dinar'),
  ('BHD', 3, '.د.ب','Bahraini Dinar');

alter table currencies enable row level security;
