module Api
  module V1
    class PublishedPostsController < BaseController
      # POST /api/v1/published_posts
      #
      # The publish worker calls this once a post has actually gone out, so the
      # store keeps its own record of it. Scope: posts:write.
      #
      # The payload is nested under `published_post` on purpose: a top-level
      # `format` key would collide with Rails' own request-format param, and
      # reading the wrong one would file every post under "json".
      #
      # Idempotent on `sanity_attempt_id`. The worker retries, and a retry has
      # to land on the same row — a second row would show Anna the same post
      # twice with no way to tell which was real.
      def create
        require_scope!("posts:write")
        return if performed?

        record, created = upsert!
        render json: post_json(record), status: created ? :created : :ok
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: "invalid", detail: e.message }, status: :unprocessable_entity
      end

      private

      def upsert!
        attempt_id = params.require(:published_post).require(:sanity_attempt_id)
        record = PublishedPost.find_or_initialize_by(sanity_attempt_id: attempt_id)
        created = !record.persisted?
        record.assign_attributes(archive_params)
        record.save!
        [record, created]
      rescue ActiveRecord::RecordNotUnique
        # Two retries landed together and both saw no row. The other one won,
        # which is the outcome we wanted anyway.
        [PublishedPost.find_by!(sanity_attempt_id: attempt_id), false]
      end

      def archive_params
        permitted = params.require(:published_post).permit(
          :sanity_post_id, :platform, :post_format, :caption, :permalink, :asset_url,
          :published_at, store_product_ids: []
        )
        # An archive must not refuse to record something that has already been
        # published. So a missing caption is stored as empty rather than
        # rejected, and only the fields that identify the post are required.
        permitted[:caption] = permitted[:caption].to_s
        permitted[:published_at] = permitted[:published_at].presence || Time.current
        permitted[:store_product_ids] = Array(permitted[:store_product_ids]).map(&:to_i)
        permitted
      end

      def post_json(record)
        {
          id: record.id,
          sanity_attempt_id: record.sanity_attempt_id,
          sanity_post_id: record.sanity_post_id,
          platform: record.platform,
          post_format: record.post_format,
          caption: record.caption,
          permalink: record.permalink,
          asset_url: record.asset_url,
          store_product_ids: record.store_product_ids,
          published_at: record.published_at&.iso8601
        }
      end
    end
  end
end
