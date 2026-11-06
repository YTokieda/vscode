# 画面の見た目を試すためのサンプルデータ。`bin/rails db:seed` で入る（APIキーがなくても動く）。
sample_image = Rails.root.join("test/fixtures/files/receipt.png")

[
  { transaction_date: Date.new(2026, 2, 14), vendor: "喫茶ひだまり", amount: 1650, account_item: "会議費",
    description: "コーヒー2杯", ai_reason: "2人分の飲み物なので打ち合わせと考えました。私用なら事業主貸です。",
    ai_warnings: "人数が読み取れません", filename: "cafe.png" },
  { transaction_date: Date.new(2026, 3, 5), vendor: "スーパーみどり", amount: 1620, reduced_rate_amount: 1080,
    account_item: "消耗品費", description: "ゴミ袋・お茶", ai_reason: "事務所用の日用品のため。",
    ai_warnings: "お茶（8%）は来客用なら会議費のほうが合うかもしれません", filename: "super.png" },
  { transaction_date: Date.new(2026, 3, 10), vendor: "郵便局", amount: 840, main_tax_rate: 0,
    account_item: "通信費", description: "切手", ai_reason: "郵送用の切手のため。切手は消費税の対象外です。", filename: "stamp.png" }
].each do |attrs|
  filename = attrs.delete(:filename)
  next if Receipt.exists?(vendor: attrs[:vendor], transaction_date: attrs[:transaction_date])

  receipt = Receipt.new(status: "extracted", **attrs)
  receipt.file.attach(io: File.open(sample_image), filename: filename, content_type: "image/png")
  receipt.save!
end
