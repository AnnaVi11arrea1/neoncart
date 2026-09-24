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

      # One query for the whole page. `PublishedPost#products` is a plain
      # where() over an id array rather than an association, so `includes`
      # cannot batch it and each row would be its own round trip — thirty of
      # them per page, on a box in her studio.
      ids = @published_posts.flat_map(&:store_product_ids).uniq
      @products_by_id = ids.any? ? Product.where(id: ids).index_by(&:id) : {}
    end
  end
end
