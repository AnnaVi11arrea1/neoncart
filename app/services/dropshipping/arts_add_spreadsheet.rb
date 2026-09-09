require "nokogiri"

module Dropshipping
  # Parses an ArtsAdd seller-center product export into an array of product
  # hashes ready for BaseAdapter#upsert_product!.
  #
  # ArtsAdd's "Export" button produces a file named `.xls` that is actually
  # Microsoft SpreadsheetML (Excel 2003 XML), sprinkled with HTML entities
  # (some of them double-encoded, e.g. "&amp;#039;"). This class makes it
  # valid XML, parses it with Nokogiri, and decodes the leftover entities.
  #
  # One export row == one variant (a size). Rows are grouped into a product
  # by the numeric id in the ArtsAdd product Link, which matches the SKU
  # prefix — e.g. SKU "D7326428-XL" + link ".._model_l16-7326428.html"
  # collapse into product "D7326428" with a variant per size.
  class ArtsAddSpreadsheet
    # Named HTML entities that appear in ArtsAdd exports but are NOT valid in
    # raw XML — mapped to codepoints so the document parses. The five
    # predefined XML entities and every numeric (&#..;) entity are left as-is.
    ENTITIES = {
      "nbsp" => 160, "bull" => 8226, "hellip" => 8230, "middot" => 183,
      "rsquo" => 8217, "lsquo" => 8216, "rdquo" => 8221, "ldquo" => 8220,
      "mdash" => 8212, "ndash" => 8211, "plusmn" => 177, "times" => 215,
      "divide" => 247, "deg" => 176, "trade" => 8482, "reg" => 174,
      "copy" => 169, "eacute" => 233, "egrave" => 232, "uuml" => 252,
      "ouml" => 246, "auml" => 228, "ccedil" => 231, "ntilde" => 241,
      "frac12" => 189, "frac14" => 188, "frac34" => 190, "sup2" => 178,
      "sup3" => 179, "laquo" => 171, "raquo" => 187, "euro" => 8364,
      "pound" => 163, "cent" => 162, "sect" => 167, "para" => 182,
      "dagger" => 8224
    }.freeze
    PREDEFINED = %w[amp lt gt quot apos].freeze

    def self.parse(io_or_path)
      new(io_or_path).parse
    end

    def initialize(io_or_path)
      raw = io_or_path.respond_to?(:read) ? io_or_path.read : File.read(io_or_path)
      @raw = raw.dup.force_encoding("UTF-8")
    end

    def parse
      doc = Nokogiri::XML(sanitize(@raw))
      doc.remove_namespaces! # sidestep the ss: prefix
      rows = doc.xpath("//Worksheet/Table/Row")
      return [] if rows.empty?

      index = cell_values(rows.first).each_with_index.to_h
      grouped = {}

      rows.drop(1).each do |row|
        cells = cell_values(row)
        get = ->(name) { (cells[index[name]] || "").to_s.strip }
        sku = get.call("SKU")
        next if sku.blank?

        pid = product_id(sku, get.call("Link"))
        product = (grouped[pid] ||= {
          external_id: pid,
          title: decode(get.call("Title")).presence || decode(get.call("Product")).presence || pid,
          description: decode(get.call("Description")),
          price_cents: to_cents(get.call("Product Price")),
          tags: tags(get.call("Tags")),
          source_url: get.call("Link").presence,          # ArtsAdd product page — used for fast reordering
          product_type: decode(get.call("Product")).presence, # e.g. "All Over Print Snapback Hat"
          image_urls: [],
          variants: []
        })

        get.call("Images").scan(%r{https?://[^\s,;|]+}).each do |img|
          product[:image_urls] << img unless product[:image_urls].include?(img)
        end

        size = decode(get.call("Size")).presence || "Default"
        product[:variants] << {
          external_id: sku,
          sku: sku,
          title: size,
          options: { "Size" => size },
          price_cents: to_cents(get.call("Product Price")),
          available: get.call("Status").to_s.downcase.include?("sale")
        }
      end

      grouped.each_value { |p| p[:image_urls] = p[:image_urls].first(8) }
      grouped.values
    end

    private

    def cell_values(row)
      row.xpath("./Cell").map { |cell| cell.at_xpath("./Data")&.text.to_s }
    end

    # ArtsAdd product id = the numeric id in the storefront link (stable),
    # falling back to the SKU prefix before the size suffix.
    def product_id(sku, link)
      if (m = link[/-(\d+)\.html/, 1])
        "D#{m}"
      else
        sku.split("-").first
      end
    end

    def tags(str)
      str.to_s.split(",").map { |t| decode(t).strip.downcase }.reject(&:blank?).uniq.first(12)
    end

    def to_cents(str)
      num = str.to_s.gsub(/[^\d.]/, "")
      return 0 if num.blank?

      (num.to_f * 100).round
    end

    # Decode any entities left inside a cell value (numeric + double-encoded
    # named entities) down to plain text.
    def decode(str)
      return "" if str.blank?

      Nokogiri::HTML.fragment(str).text
    end

    # Turn the raw SpreadsheetML into valid XML: rewrite non-predefined named
    # entities as numeric ones (or drop unknown ones) so Nokogiri won't choke.
    def sanitize(raw)
      raw.gsub(/&([a-zA-Z][a-zA-Z0-9]*);/) do
        name = Regexp.last_match(1)
        if PREDEFINED.include?(name)
          "&#{name};"
        elsif (cp = ENTITIES[name])
          "&##{cp};"
        else
          ""
        end
      end
    end
  end
end
