# 1枚の領収書・レシート・請求書（画像またはPDF）と、そこから読み取った内容を表すモデル。
class Receipt < ApplicationRecord
  STATUSES = %w[pending extracted failed].freeze
  ENTRY_SIDES = %w[支出 収入].freeze
  MAIN_TAX_RATES = [ 10, 0 ].freeze # 0 は「対象外」（切手・印紙・保険など消費税がかからないもの）

  # 個人事業主がよく使う勘定科目。青色申告決算書の経費の科目をもとにしている。
  # AIにはこの中から選ばせ、合わないときは画面で自由に書き換えられる。
  ACCOUNT_ITEMS = %w[
    仕入高 旅費交通費 通信費 接待交際費 会議費 消耗品費 新聞図書費 支払手数料
    地代家賃 水道光熱費 広告宣伝費 外注工賃 荷造運賃 修繕費 租税公課 損害保険料
    福利厚生費 研修費 車両費 雑費 売上高 事業主貸
  ].freeze

  # Claude API がそのまま読める形式。HEIC（iPhoneの標準形式）は非対応なので、JPEGで保存してもらう。
  IMAGE_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  PDF_TYPE = "application/pdf".freeze
  MAX_IMAGE_BYTES = 5.megabytes   # Claude API の画像1枚あたりの上限
  MAX_PDF_BYTES = 30.megabytes    # リクエスト全体の上限（32MB）に収まるように少し余裕をみる

  has_one_attached :file

  validates :status, inclusion: { in: STATUSES }
  validates :entry_side, inclusion: { in: ENTRY_SIDES }
  validates :main_tax_rate, inclusion: { in: MAIN_TAX_RATES }
  validates :amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :reduced_rate_amount, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :file_must_be_supported
  validate :reduced_rate_amount_within_total

  scope :extracted, -> { where(status: "extracted") }
  scope :in_year, ->(year) { where(transaction_date: Date.new(year).all_year) }
  scope :chronological, -> { order(:transaction_date, :id) }

  def pending? = status == "pending"
  def extracted? = status == "extracted"
  def failed? = status == "failed"

  def pdf? = file.attached? && file.content_type == PDF_TYPE

  # 8%以外の部分（10% または 対象外）の金額
  def main_rate_amount
    amount.to_i - reduced_rate_amount.to_i
  end

  # 税率ごとの内訳。[[税率, 金額], ...] の形で、金額が0の行は含めない。
  # 例: 合計1,080円のうち8%対象が540円なら [[10, 540], [8, 540]]
  def amounts_by_tax_rate
    [ [ main_tax_rate, main_rate_amount ], [ 8, reduced_rate_amount.to_i ] ].reject { |_, yen| yen.zero? }
  end

  def warnings_list
    ai_warnings.to_s.split("\n").reject(&:blank?)
  end

  # 日付・金額・取引先がそろっていて、CSVに出して大丈夫そうか
  def complete?
    extracted? && transaction_date.present? && amount.present? && vendor.present? && account_item.present?
  end

  private

  def file_must_be_supported
    return errors.add(:file, "を選んでください") unless file.attached?

    type = file.content_type
    size = file.blob.byte_size
    if type == "image/heic" || type == "image/heif"
      errors.add(:file, "がHEIC形式です。JPEGかPNGで保存し直してください")
    elsif IMAGE_TYPES.include?(type)
      errors.add(:file, "が大きすぎます（画像は5MBまで）") if size > MAX_IMAGE_BYTES
    elsif type == PDF_TYPE
      errors.add(:file, "が大きすぎます（PDFは30MBまで）") if size > MAX_PDF_BYTES
    else
      errors.add(:file, "の形式（#{type}）には対応していません。JPEG・PNG・GIF・WebP・PDFが使えます")
    end
  end

  def reduced_rate_amount_within_total
    return if amount.nil?

    errors.add(:reduced_rate_amount, "が合計金額を超えています") if reduced_rate_amount.to_i > amount
  end
end
