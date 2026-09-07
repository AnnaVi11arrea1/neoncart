module ApplicationHelper
  include Pagy::Frontend

  def format_money(cents, currency = "usd")
    number_to_currency(cents.to_i / 100.0, unit: currency == "usd" ? "$" : currency.upcase + " ")
  end

  def status_chip(status)
    tag.span(status.to_s.humanize, class: "chip chip--#{status}")
  end

  def nav_link(name, path, **opts)
    active = current_page?(path) || (path != root_path && request.path.start_with?(path))
    link_to name, path, **opts, class: "#{opts[:class]} #{'is-active' if active}".strip
  end

  # Multi-line, copy-ready shipping address from an Order#shipping_address hash.
  def shipping_address_text(addr)
    a = addr.is_a?(Hash) ? addr : {}
    city_line = [a["city"], [a["state"], a["postal_code"]].reject(&:blank?).join(" ")]
                .reject(&:blank?).join(", ")
    [a["name"], a["line1"], a["line2"], city_line, a["country"],
     (a["phone"].present? ? "Phone: #{a['phone']}" : nil)].reject(&:blank?).join("\n")
  end
end
