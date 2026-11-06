class ReceiptsController < ApplicationController
  before_action :set_receipt, only: %i[edit update destroy reextract]

  def index
    @years = available_years
    @year = params[:year].presence&.to_i
    scope = Receipt.with_attached_file.order(Arel.sql("transaction_date IS NULL DESC"), transaction_date: :desc, id: :desc)
    @receipts = @year ? scope.in_year(@year) : scope
  end

  # 複数のファイルをまとめて受け取り、1ファイルごとに Receipt を作って読み取りジョブに回す
  def create
    files = Array(params[:files]).compact_blank
    if files.empty?
      redirect_to receipts_path, alert: "ファイルを選んでください"
      return
    end

    errors = []
    files.each do |file|
      receipt = Receipt.new(file: file)
      if receipt.save
        ExtractReceiptJob.perform_later(receipt)
      else
        errors << "#{file.original_filename}: #{receipt.errors.full_messages.to_sentence}"
      end
    end

    notice = "#{files.size - errors.size}件を読み取り中です" if errors.size < files.size
    redirect_to receipts_path, notice: notice, alert: errors.presence&.join("\n")
  end

  def edit
  end

  def update
    # 人が確認・修正したら、読み取り失敗の状態でも「読み取り済み」として扱う
    if @receipt.update(receipt_params.merge(status: "extracted", error_message: nil))
      redirect_to receipts_path(year: @receipt.transaction_date&.year), notice: "保存しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @receipt.file.purge_later
    @receipt.destroy!
    redirect_to receipts_path, notice: "削除しました"
  end

  def reextract
    @receipt.update!(status: "pending", error_message: nil)
    ExtractReceiptJob.perform_later(@receipt)
    redirect_to receipts_path, notice: "もう一度読み取っています"
  end

  # CSVのダウンロード。日付・金額・取引先・勘定科目がそろったものだけを出す
  def export
    year = params[:year].presence&.to_i
    scope = Receipt.extracted.with_attached_file.chronological
    scope = scope.in_year(year) if year
    receipts = scope.select(&:complete?)

    if receipts.empty?
      redirect_to receipts_path(year: year), alert: "出力できる領収書がありません（日付・金額・取引先・勘定科目がそろったものだけ出力します）"
      return
    end

    label = year ? "#{year}年" : "全期間"
    if params[:kind] == "freee"
      exporter = FreeeCsvExporter.new(receipts, default_payment_account: params[:payment_account], encoding: params[:encoding] == "UTF-8" ? "UTF-8" : "Shift_JIS")
      charset = params[:encoding] == "UTF-8" ? "utf-8" : "shift_jis"
      send_data exporter.to_csv, filename: "freee取引インポート_#{label}.csv", type: "text/csv; charset=#{charset}"
    else
      send_data ReceiptCsvExporter.new(receipts).to_csv, filename: "領収書一覧_#{label}.csv", type: "text/csv; charset=utf-8"
    end
  end

  # 確定申告用に、1年分を勘定科目ごと・月ごとに合計した表
  def summary
    @years = available_years
    @year = params[:year].presence&.to_i || @years.first || Date.current.year
    @summary = AccountSummary.new(Receipt.extracted.with_attached_file.in_year(@year), year: @year)
    @excluded_count = Receipt.in_year(@year).count - @summary.receipt_count

    respond_to do |format|
      format.html
      format.csv { send_data @summary.to_csv, filename: "科目別集計_#{@year}年.csv", type: "text/csv; charset=utf-8" }
    end
  end

  private

  def available_years
    Receipt.where.not(transaction_date: nil).pluck(:transaction_date).map(&:year).uniq.sort.reverse
  end

  def set_receipt
    @receipt = Receipt.find(params[:id])
  end

  def receipt_params
    params.require(:receipt).permit(:transaction_date, :vendor, :amount, :reduced_rate_amount, :main_tax_rate,
                                    :entry_side, :account_item, :description, :invoice_number, :payment_account)
  end
end
