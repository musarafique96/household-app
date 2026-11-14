-- Each household has one main currency. Budget amounts are kept in it.
-- An expense also keeps the amount and currency it was entered in, so it can be converted again later.
ALTER TABLE households ADD COLUMN IF NOT EXISTS currency text NOT NULL DEFAULT 'PKR';
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS original_amount numeric(14, 2);
ALTER TABLE expenses ADD COLUMN IF NOT EXISTS original_currency text;
