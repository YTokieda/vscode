require "test_helper"
require "csv"

class ReceiptCsvExporterTest < ActiveSupport::TestCase
  test "Excelで開けるようBOM付きUTF-8で出す" do
    receipt = create_extracted_receipt(ai_reason: "文房具のため", ai_warnings: "日付がかすれている")
    text = ReceiptCsvExporter.new([ receipt ]).to_csv

    assert text.start_with?("﻿")
    rows = CSV.parse(text.delete_prefix("﻿"), headers: true)
    row = rows.first
    assert_equal "2026/03/05", row["日付"]
    assert_equal "10%", row["税率"]
    assert_equal "1100", row["金額（税込）"]
    assert_equal "日付がかすれている", row["確認が必要な点"]
    assert_equal "receipt.png", row["ファイル名"]
  end
end
