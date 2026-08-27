-- Add show_redeem_ui to promo_activity table
ALTER TABLE promo_activity ADD COLUMN IF NOT EXISTS show_redeem_ui BOOLEAN NOT NULL DEFAULT FALSE;
