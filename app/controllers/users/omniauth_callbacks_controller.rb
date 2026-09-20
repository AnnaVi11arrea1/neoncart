module Users
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def google_oauth2
      user = User.from_omniauth(request.env["omniauth.auth"])
      if user.persisted?
        # Cart's "get $5 off" button passes ?origin=/cart through the OAuth
        # round-trip so signing in lands them back where they were, not on
        # the homepage — otherwise the whole point (immediately seeing and
        # applying the new credit) is lost a click away.
        origin = request.env.dig("omniauth.params", "origin")
        store_location_for(user, origin) if origin.present? && origin.start_with?("/")
        sign_in_and_redirect user, event: :authentication
        set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
      else
        session["devise.google_data"] = request.env["omniauth.auth"].except("extra")
        redirect_to new_user_registration_url, alert: "Could not complete Google sign-in."
      end
    rescue StandardError => e
      Rails.logger.error("Google OAuth failed: #{e.class}: #{e.message}")
      redirect_to new_user_session_path, alert: "Google sign-in failed. Please try again or use email."
    end

    def failure
      redirect_to new_user_session_path, alert: "Google sign-in was cancelled."
    end
  end
end
