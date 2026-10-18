class CreateReceipts < ActiveRecord::Migration[8.1]
  def change
    create_table :receipts do |t|
      t.string :status, null: false, default: "pending" # pending / extracted / failed
      t.date :transaction_date                            # 発生日（領収書の日付）
      t.string :vendor                                    # 取引先
      t.integer :amount                                   # 税込の合計金額（円）
      t.integer :reduced_rate_amount, null: false, default: 0 # うち軽減税率8%の対象額
      t.integer :main_tax_rate, null: false, default: 10  # 8%以外の部分の税率（10 または 0=対象外）
      t.string :entry_side, null: false, default: "支出"  # 収支区分（支出 / 収入）
      t.string :account_item                              # 勘定科目
      t.string :description                               # 内容（品目・但し書き）
      t.string :invoice_number                            # インボイス登録番号（T+13桁）
      t.string :payment_account                           # 決済口座（空なら未決済）
      t.text :ai_reason                                   # AIが科目を選んだ理由
      t.text :ai_warnings                                 # AIが自信のない点（改行区切り）
      t.text :error_message                               # 読み取り失敗時のエラー
      t.timestamps
    end
  end
end
