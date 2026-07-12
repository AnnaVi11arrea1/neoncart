module Tracking
  # Free tracking links — no paid tracking API needed. Known carriers get
  # a direct link; anything else falls back to 17TRACK's universal page.
  module LinkBuilder
    TEMPLATES = {
      "usps" => "https://tools.usps.com/go/TrackConfirmAction?tLabels=%s",
      "ups" => "https://www.ups.com/track?tracknum=%s",
      "fedex" => "https://www.fedex.com/fedextrack/?trknbr=%s",
      "dhl" => "https://www.dhl.com/us-en/home/tracking.html?tracking-id=%s",
      "canada post" => "https://www.canadapost-postescanada.ca/track-reperage/en#/search?searchFor=%s",
      "yunexpress" => "https://www.yuntrack.com/parcelTracking?id=%s",
      "yanwen" => "https://track.yw56.com.cn/en/querydel?nums=%s",
      "4px" => "https://track.4px.com/#/result/0/%s",
      "china post" => "https://t.17track.net/en#nums=%s"
    }.freeze

    FALLBACK = "https://t.17track.net/en#nums=%s".freeze

    def self.url_for(carrier, tracking_number)
      return nil if tracking_number.blank?

      key = TEMPLATES.keys.find { |k| carrier.to_s.downcase.include?(k) }
      format(key ? TEMPLATES[key] : FALLBACK, tracking_number)
    end
  end
end
