class CreateSuppliers < ActiveRecord::Migration[7.1]
  def change
    create_table :suppliers do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :adapter, null: false # e.g. Dropshipping::PrintifyAdapter
      t.string :api_base_url
      t.string :api_key
      t.string :api_secret
      t.string :shop_id
      t.boolean :active, null: false, default: true
      t.string :fulfillment_mode, null: false, default: "auto" # auto | manual
      t.jsonb :settings, null: false, default: {}
      t.datetime :last_synced_at
      t.text :last_sync_log
      t.timestamps
    end
    add_index :suppliers, :slug, unique: true
  end
end
