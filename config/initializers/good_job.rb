Rails.application.configure do
  config.good_job.execution_mode = Rails.env.production? ? :external : :async
  config.good_job.max_threads = ENV.fetch("GOOD_JOB_MAX_THREADS", 3).to_i
  config.good_job.enable_cron = true
  config.good_job.cron = {
    sync_tracking: {
      cron: "*/30 * * * *", # every 30 minutes
      class: "SyncTrackingJob",
      description: "Poll suppliers for shipment/tracking updates"
    },
    sync_products: {
      cron: "0 4 * * *", # daily at 4am
      class: "SyncAllProductsJob",
      description: "Pull latest catalog from all active suppliers"
    }
  }
end
