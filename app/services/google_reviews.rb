# Pulls the store's Google reviews from the Places API (New) for the home page.
#
# Place Details returns at most 5 reviews, chosen by Google ("most relevant"),
# plus the overall rating and review count. Reviews are shown as Google sends
# them, with the reviewer's name and photo linked back to Google, which the
# Places policies require.
#
# A reviews request bills as Place Details Enterprise + Atmosphere, which has
# 1,000 free calls a month. Caching the answer for an hour keeps the home page
# to about 744 calls a month however busy it gets. A failed call is cached for
# 10 minutes so an outage doesn't hit the API on every page view, and the page
# then shows the hand-saved reviews in shared/_saved_reviews.html.erb.
#
# Needs GOOGLE_PLACES_API_KEY (Cloud console, Places API (New) enabled, key
# restricted to that API) and GOOGLE_PLACE_ID. Without them nothing is fetched.
module GoogleReviews
  ENDPOINT = "https://places.googleapis.com/v1/places/".freeze
  FIELDS = "rating,userRatingCount,googleMapsUri,reviews".freeze
  CACHE_KEY = "google_reviews/v1".freeze

  Summary = Struct.new(:rating, :count, :maps_url, :reviews, keyword_init: true)
  Review = Struct.new(:author, :author_url, :photo_url, :rating, :text, :when, :url, keyword_init: true)

  def self.enabled? = ENV["GOOGLE_PLACES_API_KEY"].present? && ENV["GOOGLE_PLACE_ID"].present?

  def self.summary
    return unless enabled?

    cached = Rails.cache.read(CACHE_KEY)
    return (cached unless cached == :failed) if cached

    result = fetch
    Rails.cache.write(CACHE_KEY, result || :failed, expires_in: result ? 1.hour : 10.minutes)
    result
  end

  def self.fetch
    resp = Faraday.get("#{ENDPOINT}#{ENV['GOOGLE_PLACE_ID']}") do |req|
      req.params = { languageCode: "en" }
      req.headers["X-Goog-Api-Key"] = ENV["GOOGLE_PLACES_API_KEY"]
      req.headers["X-Goog-FieldMask"] = FIELDS
      # The home page waits on this, so give up quickly.
      req.options.timeout = 3
      req.options.open_timeout = 2
    end

    unless resp.success?
      Rails.logger.warn("[google_reviews] Places API HTTP #{resp.status}: #{resp.body.to_s[0, 300]}")
      return
    end

    parse(JSON.parse(resp.body))
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.warn("[google_reviews] #{e.class}: #{e.message}")
    nil
  end

  def self.parse(place)
    reviews = Array(place["reviews"]).filter_map do |r|
      text = r.dig("text", "text").presence || r.dig("originalText", "text")
      next if text.blank? # star-only reviews make empty cards

      author = r["authorAttribution"] || {}
      Review.new(
        author: author["displayName"].presence || "Google user",
        author_url: author["uri"],
        photo_url: author["photoUri"],
        rating: r["rating"].to_i.clamp(0, 5),
        text: text,
        when: r["relativePublishTimeDescription"],
        url: r["googleMapsUri"]
      )
    end

    Summary.new(rating: place["rating"], count: place["userRatingCount"], maps_url: place["googleMapsUri"], reviews: reviews)
  end
end
