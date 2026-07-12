class TicketMailer < ApplicationMailer
  def reply(message)
    @message = message
    @ticket = message.ticket
    mail(to: @ticket.email, subject: "Re: [#{@ticket.token.first(6)}] #{@ticket.subject}")
  end

  def admin_alert(message)
    @message = message
    @ticket = message.ticket
    admin_to = ENV.fetch("ADMIN_EMAIL", Rails.configuration.x.store_email)
    mail(to: admin_to, subject: "New support message: #{@ticket.subject}")
  end
end
