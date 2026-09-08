# Page-level SEO. Views set these with `content_for`; the layout renders them
# through shared/_seo. Everything falls back to a store-wide default so no page
# ever ships without a description or canonical URL.
module SeoHelper
  DEFAULT_DESCRIPTION =
    "UV-reactive art on apparel, prints, and gear by independent artist Anna Villarreal. " \
    "Original fluorescent designs that come alive under blacklight.".freeze

  MAX_DESCRIPTION = 160

  def page_title
    content_for(:title).presence || store_name
  end

  def page_description
    raw = content_for(:description).presence || DEFAULT_DESCRIPTION
    truncate(strip_tags(raw).squish, length: MAX_DESCRIPTION, separator: " ")
  end

  # Query strings (?q=, ?category=, ?page=) create duplicate content, so the
  # canonical is the bare path unless a view names something better.
  def canonical_url
    content_for(:canonical).presence || "#{request.base_url}#{request.path}"
  end

  def og_image_url
    content_for(:og_image).presence
  end

  # Absolute URL for a possibly-relative asset or remote image.
  def absolute_image_url(url)
    return nil if url.blank?

    url.to_s.start_with?("http") ? url : "#{request.base_url}#{url}"
  end

  # Renders a <script type="application/ld+json"> block from a Ruby hash.
  def json_ld(data)
    tag.script(raw(JSON.pretty_generate(data)), type: "application/ld+json")
  end
end
