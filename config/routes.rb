Rails.application.routes.draw do
  devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }

  root "home#index"

  resources :products, only: %i[index show], param: :slug

  get "sitemap.xml", to: "sitemaps#show", defaults: { format: "xml" }, as: :sitemap

  get "privacy", to: "pages#privacy", as: :privacy
  get "returns", to: "pages#returns", as: :return_policy

  # Painting gallery (public). Admin uploads live under /admin/paintings.
  get "gallery",       to: "gallery#index", as: :gallery
  get "gallery/:slug", to: "gallery#show",  as: :painting
  resource :cart, only: :show
  resources :cart_items, only: %i[create update destroy]
  resource :checkout, only: :create
  get "checkout/success", to: "checkouts#success"
  get "checkout/cancel",  to: "checkouts#cancel"

  # Order lookup + status (guests use number + email)
  resources :orders, only: %i[index show], param: :number
  get "track", to: "orders#lookup", as: :order_lookup
  post "track", to: "orders#find"

  # Product reviews — verified purchase only. Signed-in buyers jump straight
  # to new/create from their orders; guests prove purchase via order number +
  # email first (mirrors /track above), then get a signed link per item.
  get  "reviews/verify", to: "reviews#verify",  as: :verify_reviews
  post "reviews/verify", to: "reviews#locate",  as: :locate_reviews
  resources :order_items, only: [] do
    resource :review, only: %i[new create], controller: "reviews"
  end

  resources :favorites, only: %i[create destroy]
  resource :account, only: :show, controller: "account"

  # Support tickets
  resources :tickets, only: %i[index new create show], param: :token do
    resources :messages, only: :create, controller: "ticket_messages"
  end

  # Inbound payment webhooks
  namespace :webhooks do
    post "stripe", to: "stripe#create"
  end

  # Partner API
  namespace :api do
    namespace :v1 do
      resources :products, only: %i[index show], param: :slug
      resources :paintings, only: %i[index show], param: :slug
      resources :orders, only: %i[create show], param: :number
      get "ping", to: "base#ping"
    end
  end

  namespace :admin do
    root "dashboard#index"
    resources :products do
      member do
        post :archive
        delete :remove_video
      end
      resources :photos, only: :destroy, controller: "product_photos"
    end
    resources :orders, only: %i[index show] do
      member do
        post :resubmit
        post :cancel
        post :mark_shipped
        post :mark_placed
        post :ship
      end
      resources :shipments, only: :create
    end
    resources :fulfillments, only: %i[index update]
    resources :tickets, only: %i[index show update] do
      resources :messages, only: :create, controller: "/admin/ticket_messages"
    end
    resources :suppliers do
      member do
        post :sync
        post :test_connection
        post :import
      end
    end
    resources :paintings, param: :slug
    resources :reviews, only: %i[index] do
      member do
        post :approve
        post :reject
      end
    end
    resources :api_keys, only: %i[index create destroy]
    resources :webhook_endpoints, only: %i[index create update destroy]

    # In-person sales via Stripe Terminal (card-present POS)
    get  "terminal",                   to: "terminal#show"
    post "terminal/connection_token",  to: "terminal#connection_token"
    post "terminal/payment_intent",    to: "terminal#payment_intent"
    post "terminal/capture",           to: "terminal#capture"

    get "docs", to: "docs#show"
  end

  authenticate :user, ->(u) { u.admin? } do
    mount GoodJob::Engine => "admin/good_job", as: :admin_good_job
  end

  get "up", to: proc { [200, { "Content-Type" => "text/plain" }, ["ok"]] }
end
