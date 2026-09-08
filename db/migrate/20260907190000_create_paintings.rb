class CreatePaintings < ActiveRecord::Migration[7.1]
  def change
    create_table :paintings do |t|
      t.string  :title,       null: false
      t.string  :slug,        null: false
      t.text    :description
      t.string  :medium                         # "Acrylic and UV pigment on canvas"
      t.string  :dimensions                     # "24 × 36 in"
      t.integer :year
      t.boolean :published,   null: false, default: true
      t.integer :position,    null: false, default: 0
      t.timestamps
    end

    add_index :paintings, :slug, unique: true
    add_index :paintings, %i[published position]
  end
end
