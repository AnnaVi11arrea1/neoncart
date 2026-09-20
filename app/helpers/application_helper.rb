module ApplicationHelper
  include Pagy::Frontend

  def format_money(cents, currency = "usd")
    number_to_currency(cents.to_i / 100.0, unit: currency == "usd" ? "$" : currency.upcase + " ")
  end

  # Variants carry their option name in the jsonb ("Size", "Color", ...).
  # Use it when every variant agrees, so a shirt says "Size", not "Option".
  def variant_option_label(variants)
    keys = variants.map { |v| v.options.keys.first }.uniq
    keys.length == 1 && keys.first.present? ? keys.first : "Option"
  end

  def status_chip(status)
    tag.span(status.to_s.humanize, class: "chip chip--#{status}")
  end

  # Renders one product-gallery slide — see Product#gallery_items. Only used
  # for the first (server-rendered) slide; gallery_controller.js builds the
  # rest client-side using the same type/url/alt data via data attributes.
  def gallery_media_tag(item)
    case item[:type]
    when "video-file"
      video_tag(item[:url], controls: true, playsinline: true, class: "product-page__video")
    when "video-embed"
      tag.iframe(src: item[:url], class: "product-page__video-embed",
                 allow: "autoplay; encrypted-media; picture-in-picture", allowfullscreen: true, frameborder: 0)
    when "video-link"
      link_to "▶ Watch on #{item[:alt]}", item[:url], target: "_blank", rel: "noopener",
              class: "product-page__video-link"
    else
      image_tag item[:url], alt: item[:alt], class: "product-page__main-img"
    end
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
