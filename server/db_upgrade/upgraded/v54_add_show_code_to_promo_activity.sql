-- Add show_code_to_user to promo_activity table
ALTER TABLE promo_activity ADD COLUMN IF NOT EXISTS show_code_to_user BOOLEAN NOT NULL DEFAULT FALSE;
