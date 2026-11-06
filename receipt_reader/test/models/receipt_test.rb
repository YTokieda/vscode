require "test_helper"

class ReceiptTest < ActiveSupport::TestCase
  test "画像とPDFは保存できる" do
    assert create_receipt.persisted?
    assert create_receipt(filename: "invoice.pdf", content_type: "application/pdf").pdf?
  end

  test "対応していない形式やHEICは保存できない" do
    receipt = Receipt.new
    receipt.file.attach(io: file_fixture("note.txt").open, filename: "note.txt", content_type: "text/plain")
    assert_not receipt.valid?
    assert_match "対応していません", receipt.errors.full_messages.join

    heic = Receipt.new
    heic.file.attach(io: file_fixture("receipt.png").open, filename: "photo.heic", content_type: "image/heic", identify: false)
    assert_not heic.valid?
    assert_match "HEIC", heic.errors.full_messages.join
  end

  test "税率ごとの内訳を返す" do
    receipt = Receipt.new(amount: 1080, reduced_rate_amount: 540, main_tax_rate: 10)
    assert_equal [ [ 10, 540 ], [ 8, 540 ] ], receipt.amounts_by_tax_rate

    assert_equal [ [ 8, 864 ] ], Receipt.new(amount: 864, reduced_rate_amount: 864).amounts_by_tax_rate
    assert_equal [ [ 0, 84 ] ], Receipt.new(amount: 84, main_tax_rate: 0).amounts_by_tax_rate
  end

  test "8%対象額が合計を超えると保存できない" do
    receipt = create_receipt
    assert_not receipt.update(amount: 100, reduced_rate_amount: 200)
  end

  test "日付・金額・取引先・勘定科目がそろえば complete" do
    receipt = create_extracted_receipt
    assert receipt.complete?
    receipt.vendor = nil
    assert_not receipt.complete?
  end
end
