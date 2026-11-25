# frozen_string_literal: true

module Admin
  # The admin console: accounts and the templates they start from. Only for admins,
  # and never for an access token (no admin action says allow_access_tokens). To
  # anyone else it isn't there.
  class BaseController < ApplicationController
    before_action :require_admin
    restrict_in_demo

    private

    def require_admin
      head :not_found unless Current.user&.admin?
    end
  end
end
