class ApplicationMailer < ActionMailer::Base
  default from: -> { "#{Rails.configuration.x.store_name} <#{Rails.configuration.x.store_email}>" }
  layout "mailer"
end
