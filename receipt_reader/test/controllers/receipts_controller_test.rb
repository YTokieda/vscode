require "test_helper"

class ReceiptsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "一覧が表示される" do
    create_extracted_receipt
    get receipts_path
    assert_response :success
    assert_select "td", "文具のミドリ"
  end

  test "複数ファイルをアップロードすると、読み取りジョブが登録される" do
    files = [ fixture_file_upload("receipt.png", "image/png"), fixture_file_upload("invoice.pdf", "application/pdf") ]
    assert_enqueued_jobs 2, only: ExtractReceiptJob do
      post receipts_path, params: { files: files }
    end
    assert_redirected_to receipts_path
    assert_equal 2, Receipt.where(status: "pending").count
  end

  test "対応していないファイルは理由を表示して保存しない" do
    assert_no_difference "Receipt.count" do
      post receipts_path, params: { files: [ fixture_file_upload("note.txt", "text/plain") ] }
    end
    follow_redirect!
    assert_match "note.txt", response.body
  end

  test "修正を保存できる" do
    receipt = create_receipt(status: "failed", error_message: "読めませんでした")
    patch receipt_path(receipt), params: { receipt: { transaction_date: "2026-04-01", vendor: "駅前書店", amount: 2200, account_item: "新聞図書費" } }
    receipt.reload
    assert receipt.complete?
    assert_nil receipt.error_message
  end

  test "freee用CSVをダウンロードできる（年で絞り込み）" do
    create_extracted_receipt
    create_extracted_receipt(transaction_date: Date.new(2025, 12, 31), vendor: "去年の店")
    create_receipt # 読み取り中のものは出さない

    get export_receipts_path(kind: "freee", year: 2026, payment_account: "現金")
    assert_response :success
    assert_match "shift_jis", response.media_type + response.charset.to_s.downcase
    text = response.body.force_encoding("Windows-31J").encode("UTF-8")
    assert_match "文具のミドリ", text
    assert_no_match "去年の店", text
    assert_equal 2, text.lines.size # ヘッダ + 1行
  end

  test "一覧CSVをダウンロードできる" do
    create_extracted_receipt
    get export_receipts_path(kind: "generic")
    assert_response :success
    assert_match "文具のミドリ", response.body.force_encoding("UTF-8")
  end

  test "出力できるものがなければ一覧に戻る" do
    get export_receipts_path(kind: "freee")
    assert_redirected_to receipts_path(year: nil)
  end

  test "科目別集計を表示してCSVでダウンロードできる" do
    create_extracted_receipt
    create_extracted_receipt(vendor: nil)
    get summary_receipts_path(year: 2026)
    assert_response :success
    assert_select "td", "消耗品費"
    assert_match "1 件は", response.body

    get summary_receipts_path(year: 2026, format: :csv)
    assert_response :success
    assert_match "経費合計", response.body.force_encoding("UTF-8")
  end

  test "領収書がなくても科目別集計の画面は開ける" do
    get summary_receipts_path
    assert_response :success
  end
end
