class CreateShipments < ActiveRecord::Migration[7.1]
  def change
    create_table :shipments do |t|
      t.references :order, null: false, foreign_key: true
      t.references :supplier, foreign_key: true
      t.string :carrier
      t.string :tracking_number
      t.string :tracking_url
      t.string :status, null: false, default: "in_transit" # in_transit | delivered
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.jsonb :raw, null: false, default: {}
      t.timestamps
    end
    add_index :shipments, %i[order_id tracking_number], unique: true, where: "tracking_number IS NOT NULL"
  end
end
