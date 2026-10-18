Rails.application.routes.draw do
  root "receipts#index"

  resources :receipts, only: %i[index create edit update destroy] do
    collection do
      get :export   # CSVのダウンロード（?kind=generic または freee）
    end
    member do
      post :reextract # もう一度AIに読み取らせる
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
