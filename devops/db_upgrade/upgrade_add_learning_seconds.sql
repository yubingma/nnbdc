-- Add learning time fields to user table
ALTER TABLE "user" ADD COLUMN "total_learning_seconds" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "user" ADD COLUMN "today_learning_seconds" INTEGER NOT NULL DEFAULT 0;
