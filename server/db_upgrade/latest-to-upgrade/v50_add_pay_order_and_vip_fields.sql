-- Upgrade database to support universal payment & orders (v50)

-- 1. Create pay_order table
CREATE TABLE IF NOT EXISTS pay_order (
    id VARCHAR(32) PRIMARY KEY,
    user_id VARCHAR(32) NOT NULL,
    product_id VARCHAR(50) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    channel VARCHAR(30) NOT NULL,
    status VARCHAR(20) NOT NULL,
    outer_trade_no VARCHAR(128),
    pay_time TIMESTAMP,
    create_time TIMESTAMP NOT NULL,
    update_time TIMESTAMP NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_payorder_userid ON pay_order(user_id);
CREATE INDEX IF NOT EXISTS idx_payorder_outertradeno ON pay_order(outer_trade_no);

-- 2. Add universal VIP fields to user table
ALTER TABLE "user" ADD COLUMN IF NOT EXISTS vip_expire_date TIMESTAMP;
ALTER TABLE "user" ADD COLUMN IF NOT EXISTS vip_type VARCHAR(20);
ALTER TABLE "user" ADD COLUMN IF NOT EXISTS last_pay_channel VARCHAR(30);
