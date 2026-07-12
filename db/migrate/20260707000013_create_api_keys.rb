class CreateApiKeys < ActiveRecord::Migration[7.1]
  def change
    create_table :api_keys do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :prefix, null: false # first chars, shown in admin for identification
      t.string :scopes, array: true, null: false, default: ["products:read", "orders:write"]
      t.string :partner_url
      t.boolean :active, null: false, default: true
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :api_keys, :token_digest, unique: true
  end
end
