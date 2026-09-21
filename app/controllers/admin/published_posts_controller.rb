module Admin
  class PublishedPostsController < BaseController
    # The retro post search: everything that has actually gone out, newest
    # first, searchable by what it said.
    def index
      scope = PublishedPost
              .search(params[:q])
              .on_platform(params[:platform])
              .order(published_at: :desc)
      @pagy, @published_posts = pagy(scope, limit: 30)
    end
  end
end
