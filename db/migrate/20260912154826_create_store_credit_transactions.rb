class CreateStoreCreditTransactions < ActiveRecord::Migration[7.1]
  def change
    create_table :store_credit_transactions do |t|
      t.references :user, null: false, foreign_key: true
      # Nullable: manual admin adjustments have no order behind them.
      t.references :order, null: true, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :kind, null: false
      t.string :note

      t.timestamps
    end
  end
end
