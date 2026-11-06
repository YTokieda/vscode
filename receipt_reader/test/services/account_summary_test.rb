require "test_helper"

class AccountSummaryTest < ActiveSupport::TestCase
  setup do
    create_extracted_receipt(transaction_date: Date.new(2026, 1, 10), amount: 1000, account_item: "消耗品費")
    create_extracted_receipt(transaction_date: Date.new(2026, 1, 20), amount: 500, account_item: "消耗品費")
    create_extracted_receipt(transaction_date: Date.new(2026, 3, 1), amount: 2000, account_item: "旅費交通費")
    create_extracted_receipt(transaction_date: Date.new(2026, 4, 1), amount: 150_000, account_item: "消耗品費", description: "ノートパソコン")
    create_extracted_receipt(transaction_date: Date.new(2026, 5, 1), amount: 3000, account_item: "事業主貸")
    create_extracted_receipt(transaction_date: Date.new(2026, 6, 1), amount: 50_000, account_item: "売上高", entry_side: "収入")
    create_extracted_receipt(transaction_date: Date.new(2025, 12, 31), amount: 9999, account_item: "消耗品費") # 別の年
    create_extracted_receipt(transaction_date: Date.new(2026, 7, 1), amount: 777, account_item: nil)        # 未入力あり
    @summary = AccountSummary.new(Receipt.all, year: 2026)
  end

  test "科目ごと・月ごとに合計する（別の年と未入力のものは入れない）" do
    rows = @summary.expense_rows.index_by(&:account_item)
    assert_equal %w[旅費交通費 消耗品費], @summary.expense_rows.map(&:account_item) # 決算書に近い並び順
    assert_equal 1500, rows["消耗品費"].monthly[0]
    assert_equal 151_500, rows["消耗品費"].total
    assert_equal 2000, rows["旅費交通費"].monthly[2]
    assert_equal 153_500, @summary.expense_total
    assert_equal 6, @summary.receipt_count
  end

  test "事業主貸は経費に入れず、収入は分けて集計する" do
    assert_equal [ "事業主貸" ], @summary.private_rows.map(&:account_item)
    assert_equal 50_000, @summary.income_total
  end

  test "10万円以上の支出を拾う" do
    assert_equal [ "ノートパソコン" ], @summary.large_expenses.map(&:description)
  end

  test "CSVに月別の列と経費合計の行がある" do
    rows = CSV.parse(@summary.to_csv.delete_prefix("﻿"))
    assert_equal [ "区分", "勘定科目", "1月" ], rows.first.first(3)
    assert_equal "合計", rows.first.last
    assert_includes rows, [ "経費", "経費合計", "1500", "0", "2000", "150000", "0", "0", "0", "0", "0", "0", "0", "0", "153500" ]
    assert_equal [ "収入", "売上高" ], rows[1].first(2)
    assert_equal [ "経費外", "事業主貸" ], rows.last.first(2)
  end
end
