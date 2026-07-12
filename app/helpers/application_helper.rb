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
end
