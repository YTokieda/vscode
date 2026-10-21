require "test_helper"
require "csv"

class FreeeCsvExporterTest < ActiveSupport::TestCase
  def parse(csv_text, encoding: "Windows-31J")
    CSV.parse(csv_text.dup.force_encoding(encoding).encode("UTF-8"), headers: true)
  end

  test "freeeの取引インポートのヘッダと1行目を出す" do
    receipt = create_extracted_receipt(invoice_number: "T1234567890123")
    rows = parse(FreeeCsvExporter.new([ receipt ], default_payment_account: "現金").to_csv)

    assert_equal FreeeCsvExporter::HEADERS, rows.headers
    row = rows.first
    assert_equal "支出", row["収支区分"]
    assert_equal "2026/03/05", row["発生日"]
    assert_equal "文具のミドリ", row["取引先"]
    assert_equal "消耗品費", row["勘定科目"]
    assert_equal "課対仕入10%", row["税区分"]
    assert_equal "1100", row["金額"]
    assert_equal "内税", row["税計算区分"]
    assert_equal "ボールペン 登録番号T1234567890123", row["備考"]
    assert_equal "2026/03/05", row["決済日"]
    assert_equal "現金", row["決済口座"]
    assert_equal "1100", row["決済金額"]
  end

  test "決済口座がなければ未決済（決済の列は空）" do
    row = parse(FreeeCsvExporter.new([ create_extracted_receipt ]).to_csv).first
    assert_nil row["決済日"]
    assert_nil row["決済口座"]
    assert_nil row["決済金額"]
  end

  test "領収書ごとの決済口座が出力時の指定より優先される" do
    receipt = create_extracted_receipt(payment_account: "プライベート資金")
    row = parse(FreeeCsvExporter.new([ receipt ], default_payment_account: "現金").to_csv).first
    assert_equal "プライベート資金", row["決済口座"]
  end

  test "8%と10%が混ざった領収書は税率ごとに別の行になる" do
    receipt = create_extracted_receipt(amount: 1620, reduced_rate_amount: 1080, account_item: "会議費")
    rows = parse(FreeeCsvExporter.new([ receipt ]).to_csv)

    assert_equal 2, rows.size
    assert_equal [ "課対仕入10%", "540" ], [ rows[0]["税区分"], rows[0]["金額"] ]
    assert_equal [ "課対仕入8%（軽）", "1080" ], [ rows[1]["税区分"], rows[1]["金額"] ]
    assert_equal [ "R#{receipt.id}-1", "R#{receipt.id}-2" ], rows.map { |r| r["管理番号"] }
  end

  test "対象外と収入の税区分" do
    stamp = create_extracted_receipt(amount: 110, main_tax_rate: 0, account_item: "通信費")
    sale = create_extracted_receipt(entry_side: "収入", account_item: "売上高")
    rows = parse(FreeeCsvExporter.new([ stamp, sale ]).to_csv)
    assert_equal [ "対象外", "課税売上10%" ], rows.map { |r| r["税区分"] }
  end

  test "UTF-8でも出せる" do
    text = FreeeCsvExporter.new([ create_extracted_receipt ], encoding: "UTF-8").to_csv
    assert_equal Encoding::UTF_8, text.encoding
    assert_equal "文具のミドリ", parse(text, encoding: "UTF-8").first["取引先"]
  end

  test "Shift_JISにない文字は?に置き換えて落ちない" do
    text = FreeeCsvExporter.new([ create_extracted_receipt(vendor: "髙橋商店🍰") ]).to_csv
    assert_equal "髙橋商店?", parse(text).first["取引先"]
  end
end
