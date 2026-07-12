class OrderEvent < ApplicationRecord
  belongs_to :order

  ICONS = {
    "placed" => "◆", "paid" => "◈", "submitted" => "▣", "shipped" => "➤",
    "delivered" => "✦", "cancelled" => "✕", "note" => "•", "error" => "⚠"
  }.freeze

  def icon = ICONS.fetch(kind, "•")
end
