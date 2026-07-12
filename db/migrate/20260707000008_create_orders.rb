class CreateOrders < ActiveRecord::Migration[7.1]
  def change
    create_table :orders do |t|
      t.references :user, foreign_key: true
      t.references :api_key, index: true # set when created via partner API
      t.string :number, null: false
      t.string :email
      t.string :status, null: false, default: "pending"
      t.integer :subtotal_cents, null: false, default: 0
      t.integer :shipping_cents, null: false, default: 0
      t.integer :tax_cents, null: false, default: 0
      t.integer :total_cents, null: false, default: 0
      t.string :currency, null: false, default: "usd"
      t.string :stripe_session_id
      t.string :stripe_payment_intent_id
      t.jsonb :shipping_address, null: false, default: {}
      t.string :source, null: false, default: "storefront" # storefront | api
      t.text :notes
      t.datetime :placed_at
      t.timestamps
    end
    add_index :orders, :number, unique: true
    add_index :orders, :status
    add_index :orders, :stripe_session_id, unique: true, where: "stripe_session_id IS NOT NULL"
  end
end
