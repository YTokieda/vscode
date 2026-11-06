require "csv"

# 1年分の領収書を「勘定科目 × 月」で合計する。
# 確定申告の決算書（収支内訳書・青色申告決算書）の経費の欄に、科目ごとの年間合計を書き写すために使う。
class AccountSummary
  MONTHS = (1..12).to_a.freeze
  # 事業主貸は「事業のお金で私用の支払いをした」記録なので、経費の合計には入れない
  NON_EXPENSE_ACCOUNTS = %w[事業主貸].freeze
  # この金額以上の支出は、パソコンなどの備品なら一度に経費にできないことがある
  LARGE_EXPENSE_YEN = 100_000

  Row = Struct.new(:entry_side, :account_item, :monthly, keyword_init: true) do
    def total = monthly.sum
  end

  attr_reader :year

  def initialize(receipts, year:)
    @year = year
    @receipts = receipts.select { |r| r.complete? && r.transaction_date.year == year }
  end

  def receipt_count = @receipts.size

  def income_rows = rows_for("収入")
  def expense_rows = rows_for("支出").reject { |row| NON_EXPENSE_ACCOUNTS.include?(row.account_item) }
  def private_rows = rows_for("支出").select { |row| NON_EXPENSE_ACCOUNTS.include?(row.account_item) }

  def income_total = income_rows.sum(&:total)
  def expense_total = expense_rows.sum(&:total)

  def monthly_expense_totals
    MONTHS.map { |m| expense_rows.sum { |row| row.monthly[m - 1] } }
  end

  # 10万円以上の支出。備品なら減価償却などの扱いになることがあるので、画面で注意を出す
  def large_expenses
    @receipts.select { |r| r.entry_side == "支出" && !NON_EXPENSE_ACCOUNTS.include?(r.account_item) && r.amount >= LARGE_EXPENSE_YEN }
             .sort_by(&:transaction_date)
  end

  def to_csv
    "﻿" + CSV.generate do |csv|
      csv << [ "区分", "勘定科目", *MONTHS.map { |m| "#{m}月" }, "合計" ]
      income_rows.each { |row| csv << [ "収入", row.account_item, *row.monthly, row.total ] }
      expense_rows.each { |row| csv << [ "経費", row.account_item, *row.monthly, row.total ] }
      csv << [ "経費", "経費合計", *monthly_expense_totals, expense_total ]
      private_rows.each { |row| csv << [ "経費外", row.account_item, *row.monthly, row.total ] }
    end
  end

  private

  def rows_for(entry_side)
    receipts = @receipts.select { |r| r.entry_side == entry_side }
    receipts.group_by(&:account_item)
            .map { |account, list| Row.new(entry_side: entry_side, account_item: account, monthly: monthly_totals(list)) }
            .sort_by { |row| [ Receipt::ACCOUNT_ITEMS.index(row.account_item) || Receipt::ACCOUNT_ITEMS.size, row.account_item ] }
  end

  def monthly_totals(receipts)
    MONTHS.map { |m| receipts.select { |r| r.transaction_date.month == m }.sum(&:amount) }
  end
end
