# Old Shopify and Etsy URLs → where that page lives now. The table is
# config/legacy_redirects.yml; this only answers lookups against it.
module LegacyRedirects
  # Unlisted Etsy listings and Shopify collections still go somewhere useful.
  FALLBACK = "/products".freeze

  def self.table
    @table ||= YAML.load_file(Rails.root.join("config/legacy_redirects.yml")).transform_values { |v| v || {} }
  end

  # nil when the handle isn't one we know — the caller 404s as before.
  def self.for_product(handle) = table["products"][handle.to_s]

  def self.for_listing(listing_id) = table["listings"][listing_id.to_s] || FALLBACK

  def self.for_collection(handle) = table["collections"][handle.to_s] || FALLBACK

  def self.for_path(path) = table["paths"][path.to_s.chomp("/")]
end
