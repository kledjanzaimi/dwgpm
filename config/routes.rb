Rails.application.routes.draw do
  # Liveness probe for Docker/Caddy; no login, no database.
  get "up" => "rails/health#show", as: :rails_health_check

  get    "login",  to: "sessions#new"
  post   "login",  to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  root "projects#index"
  resources :users, only: %i[index new create destroy]

  resources :projects, only: %i[index new create], param: :slug do
    resources :memberships, only: %i[index create destroy]

    # `*path` is a glob carrying the relative path inside the project tree.
    # ORDER MATTERS: the bare `files(/*path)` glob would swallow every route
    # below it, so the specific verbs are declared first.
    get    "files/*path/locate",   to: "files#locate",   as: :locate_files,     format: false
    get    "files/*path/download", to: "files#download", as: :download_files,   format: false
    post   "files/upload",         to: "files#upload",   as: :upload_files_root
    post   "files/*path/upload",   to: "files#upload",   as: :upload_files,     format: false
    post   "files/mkdir",          to: "files#mkdir",    as: :mkdir_files_root
    post   "files/*path/mkdir",    to: "files#mkdir",    as: :mkdir_files,      format: false
    delete "files/*path",          to: "files#destroy",  as: :file,             format: false
    get    "files(/*path)",        to: "files#index",    as: :files,            format: false
  end
end
