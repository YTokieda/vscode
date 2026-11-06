require "csv"

# 読み取った領収書を、Excel などで開ける汎用のCSVにする。
# 1枚の領収書に8%と10%が混ざっているときは、税率ごとに行を分ける。
class ReceiptCsvExporter
  HEADERS = %w[日付 収支区分 取引先 勘定科目 税率 金額（税込） 内容 インボイス登録番号 決済口座 AIの判断理由 確認が必要な点 ファイル名].freeze

  def initialize(receipts)
    @receipts = receipts
  end

  # Excel でそのまま開いても文字化けしないよう、UTF-8 の先頭に BOM を付ける
  def to_csv
    "﻿" + CSV.generate do |csv|
      csv << HEADERS
      @receipts.each do |receipt|
        receipt.amounts_by_tax_rate.each do |rate, yen|
          csv << [
            receipt.transaction_date&.strftime("%Y/%m/%d"),
            receipt.entry_side,
            receipt.vendor,
            receipt.account_item,
            rate.zero? ? "対象外" : "#{rate}%",
            yen,
            receipt.description,
            receipt.invoice_number,
            receipt.payment_account,
            receipt.ai_reason,
            receipt.warnings_list.join(" / "),
            receipt.file.attached? ? receipt.file.filename.to_s : nil
          ]
        end
      end
    end
  end
end
