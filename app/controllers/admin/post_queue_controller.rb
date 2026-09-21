module Admin
  # The approve queue. Posts are drafted in the CMS and go out only once Anna
  # says so here, which is the whole point of the page: the decision belongs in
  # the store admin she already has open, not in a second tool.
  #
  # Nothing is stored locally. The queue is the publisher's, because only the
  # publisher holds the CMS credential (PostQueue::Client explains why), and a
  # local copy of a pending post would start drifting from the document the
  # moment either side was edited. Only a post that has actually gone out gets a
  # row here, in published_posts.
  class PostQueueController < BaseController
    def index
      @posts = []
      @configured = PostQueue::Client.configured?
      return unless @configured

      @posts = client.pending
    rescue PostQueue::Client::Error => e
      @error = e.message
    end

    def approve
      decide("approved", "Post approved. The publisher sends it on its next run.")
    end

    def reject
      decide("rejected", "Post rejected. It stays in the CMS as a draft.")
    end

    private

    def decide(decision, notice)
      unless PostQueue::Client.configured?
        return redirect_to admin_post_queue_path,
                           alert: "The publisher is not connected yet, so nothing can be sent from here."
      end

      client.decide!(params[:id], decision:, actor: current_user.email, note: params[:note])
      redirect_to admin_post_queue_path, notice:
    rescue ArgumentError => e
      redirect_to admin_post_queue_path, alert: e.message
    rescue PostQueue::Client::Error => e
      # Say what the publisher said. A decision that silently failed would leave
      # Anna believing a post is going out when it is not.
      redirect_to admin_post_queue_path, alert: "That did not go through: #{e.message}."
    end

    def client = @client ||= PostQueue::Client.new
  end
end
