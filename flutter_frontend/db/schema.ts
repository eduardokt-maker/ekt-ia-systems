import { sqliteTable, text, integer, uniqueIndex } from "drizzle-orm/sqlite-core";
import { sql } from "drizzle-orm";

export const paymentOrigins = sqliteTable(
  "payment_origins",
  {
    id: text("id").primaryKey(),
    userId: text("user_id").notNull(),
    name: text("name").notNull(),
    normalizedName: text("normalized_name").notNull(),
    createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
    updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  },
  (table) => [
    uniqueIndex("idx_payment_origins_user_name").on(table.userId, table.normalizedName),
  ],
);

export const investmentPortfolios = sqliteTable('investment_portfolios', {
  ownerId: text('owner_id').primaryKey().notNull(),
  revision: integer('revision').notNull(),
  payload: text('payload').notNull(),
  updatedAt: text('updated_at').notNull().default(sql`CURRENT_TIMESTAMP`),
});
