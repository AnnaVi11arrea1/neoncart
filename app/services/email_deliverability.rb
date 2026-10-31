require "resolv"

# Rejects addresses whose domain can't receive mail at all: a typo like
# gmial.con, or a made-up domain. It can't tell whether the mailbox exists;
# only a confirmation email can do that.
module EmailDeliverability
  # A DNS hiccup shouldn't turn a real customer away, so anything other than
  # a clear "this domain doesn't exist / has no mail server" passes.
  def self.deliverable?(email)
    domain = email.to_s.strip.split("@", 2).last.to_s.downcase
    return false unless domain.match?(/\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/)

    Resolv::DNS.open do |dns|
      dns.timeouts = 3
      # No MX record means mail goes to the domain's own address (RFC 5321).
      receives_mail?(dns, domain) ||
        # Resolv returns nothing on a timeout as well as on a missing domain,
        # so only reject when DNS demonstrably works for a known-good domain.
        !receives_mail?(dns, "gmail.com")
    end
  rescue Resolv::ResolvError, Resolv::ResolvTimeout, SocketError
    true
  end

  def self.receives_mail?(dns, domain)
    [Resolv::DNS::Resource::IN::MX, Resolv::DNS::Resource::IN::A, Resolv::DNS::Resource::IN::AAAA]
      .any? { |type| dns.getresources(domain, type).any? }
  end
  private_class_method :receives_mail?
end
