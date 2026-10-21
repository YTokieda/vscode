Rails.application.routes.draw do
  root "receipts#index"

  resources :receipts, only: %i[index create edit update destroy] do
    collection do
      get :export   # CSVのダウンロード（?kind=generic または freee）
      get :summary  # 勘定科目ごと・月ごとの集計表（?year=2026、format: :csv でダウンロード）
    end
    member do
      post :reextract # もう一度AIに読み取らせる
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
