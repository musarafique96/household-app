-- Each member chooses how to see group amounts: 'group' (the group's main currency) or 'own' (their account currency).
ALTER TABLE household_members ADD COLUMN IF NOT EXISTS show_currency text NOT NULL DEFAULT 'group';
