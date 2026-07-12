module Admin
  class BaseController < ApplicationController
    layout "admin"
    before_action :authenticate_user!
    before_action :require_admin!
  end
end
