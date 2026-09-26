module PostQueue
  # One post awaiting a decision, as the publisher described it. Everything here
  # is read defensively: this is another service's JSON, and a queue page that
  # 500s because one post is missing a caption is worse than a page that shows
  # the post with the caption blank.
  class Post
    ASSET_KINDS = %w[image video].freeze

    def initialize(attrs)
      @attrs = attrs || {}
    end

    def id = @attrs["id"].presence
    def caption = @attrs["caption"].to_s
    def platform = @attrs["platform"].presence
    def post_format = @attrs["post_format"].presence

    # Rendered as an image source and as a link in the admin, so anything that
    # is not plainly http(s) is dropped: a "javascript:" URL here would run in
    # Anna's own signed-in session. The publisher is ours, so this guards
    # against it being wrong rather than against an attacker, but it is an
    # admin page and the check is one line.
    def asset_url
      value = @attrs["asset_url"].presence
      value if value.to_s.match?(%r{\Ahttps?://}i)
    end

    def asset_kind
      kind = @attrs["asset_kind"].to_s
      ASSET_KINDS.include?(kind) ? kind : nil
    end

    # A page showing this post as the platform will render it, which the queue
    # embeds in a sandboxed iframe. Same scheme guard as `asset_url`, for the
    # same reason and with more at stake: this one is framed rather than linked,
    # so a "javascript:" or "data:" URL would be a script running on this page.
    def preview_url
      value = @attrs["preview_url"].presence
      value if value.to_s.match?(%r{\Ahttps?://}i)
    end

    # The CMS document, without the variant key the publisher appends to address
    # one platform's card. `post-8f21__ig` is the row; `post-8f21` is what the
    # Studio knows about, so it is what a link into the Studio has to use.
    def document_id
      value = id
      return nil if value.blank?

      at = value.rindex("__")
      at&.positive? ? value[0...at] : value
    end

    def updated_at
      value = @attrs["updated_at"].presence
      value && Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # [{ store_id:, title: }] — the store ids let the queue link to the real
    # product here rather than to a CMS reference this app cannot resolve.
    def products
      Array(@attrs["products"]).filter_map do |entry|
        next unless entry.is_a?(Hash)

        { store_id: store_id_of(entry["store_id"]), title: entry["title"].to_s }
      end
    end

    def store_products
      ids = products.filter_map { |p| p[:store_id] }.select(&:positive?)
      return Product.none if ids.empty?

      Product.where(id: ids)
    end

    # [{ title:, ref:, url: }] — what the draft agent based the caption on. Only
    # its posts carry these. `ref` is a CMS id, a Knowledge Base path or a URL;
    # `url` is set only when it is plainly http(s), same guard as `asset_url`.
    def sources
      Array(@attrs["sources"]).filter_map do |entry|
        next unless entry.is_a?(Hash)

        title = entry["title"].to_s.presence
        ref = entry["ref"].to_s.presence
        next unless title || ref

        { title: title || ref, ref: ref, url: (ref if ref.to_s.match?(%r{\Ahttps?://}i)) }
      end
    end

    # Places two sources disagreed about something the caption touches, as the
    # agent described them. Worth reading before approving; never blocking.
    def conflicts
      Array(@attrs["conflicts"]).filter_map { |text| text.presence if text.is_a?(String) }
    end

    def errors   = messages("errors")
    def warnings = messages("warnings")

    # A post the publisher will refuse. Anna decided a post missing a required
    # field is flagged and blocked rather than quietly skipped, so the queue
    # shows it and says what is missing instead of hiding it.
    def blocked?
      verdict = @attrs["verdict"]
      return false unless verdict.is_a?(Hash)

      verdict["ok"] == false || errors.any?
    end

    # No verdict at all is not the same as a clean one, and must not read as a
    # green tick — the publisher re-checks at publish time either way.
    def unchecked? = !@attrs["verdict"].is_a?(Hash)

    private

    # Only a real id, so the label never reads "product 0" — `to_i` turns a word
    # or an object into 0, and product 0 does not exist.
    def store_id_of(value)
      return nil unless value.is_a?(String) || value.is_a?(Numeric)

      id = value.to_i
      id.positive? ? id : nil
    end

    def messages(key)
      verdict = @attrs["verdict"]
      return [] unless verdict.is_a?(Hash)

      Array(verdict[key]).filter_map do |entry|
        text = entry.is_a?(Hash) ? (entry["message"] || entry["text"]) : entry
        text.to_s.presence
      end
    end
  end
end
