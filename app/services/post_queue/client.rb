module PostQueue
  # Posts waiting on approval live in the CMS, and this app deliberately holds
  # no CMS credential. A Sanity token cannot be narrowed to one dataset or one
  # document type without an Enterprise plan, so a token kept here would also
  # read the private knowledge-base notes in the same project. The publisher
  # already holds that credential, so it serves the queue and takes the
  # decisions, and this client is the only thing in the store that talks to it.
  #
  # The contract the publisher has to answer is written down in
  # docs/post-queue-contract.md.
  class Client
    class Error < StandardError; end

    TIMEOUT = 15
    OPEN_TIMEOUT = 8
    DECISIONS = %w[approved rejected].freeze

    def self.base_url = Rails.configuration.x.post_worker_url.presence
    def self.token = Rails.configuration.x.post_worker_token.presence
    def self.configured? = base_url.present? && token.present?

    # Returns the posts awaiting a decision, newest first as the publisher
    # ordered them. An unreadable queue raises rather than returning [], so the
    # admin can say "I could not reach the publisher" instead of showing an
    # empty queue that looks like there is nothing to approve.
    def pending
      body = request(:get, "posts/pending")
      list = body.is_a?(Hash) ? body["posts"] : body
      Array(list).filter_map { |attrs| Post.new(attrs) if attrs.is_a?(Hash) }
    end

    def decide!(id, decision:, actor:, note: nil)
      raise ArgumentError, "decision must be one of #{DECISIONS.join(", ")}" unless DECISIONS.include?(decision)
      raise ArgumentError, "a post id is required" if id.blank?

      request(:post, "posts/#{CGI.escape(id)}/decision", decision:, actor:, note: note.presence)
    end

    private

    def request(method, path, payload = nil)
      raise Error, "the publisher is not configured" unless self.class.configured?

      response = http.public_send(method, path, payload)
      unless response.success?
        raise Error, "the publisher returned #{response.status}#{detail(response)}"
      end

      response.body
    rescue Faraday::TimeoutError
      raise Error, "the publisher did not answer within #{TIMEOUT} seconds"
    rescue Faraday::Error => e
      raise Error, "could not reach the publisher (#{e.class.name.demodulize})"
    end

    # The publisher's own words if it sent any, so a rejected decision says why
    # rather than only showing a status code.
    def detail(response)
      body = response.body
      message = body.is_a?(Hash) ? (body["error"] || body["message"]) : nil
      message.present? ? ": #{message.to_s.truncate(200)}" : ""
    end

    def http
      @http ||= Faraday.new(url: File.join(self.class.base_url, "/")) do |f|
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.options.timeout = TIMEOUT
        f.options.open_timeout = OPEN_TIMEOUT
        f.headers["Authorization"] = "Bearer #{self.class.token}"
        f.headers["User-Agent"] = "Neoncart/1.0"
      end
    end
  end
end
