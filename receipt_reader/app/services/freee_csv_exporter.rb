require "csv"

# freee会計の「取引・口座振替のインポート（一括登録）」用のCSVを作る。
#
# 列の並びは freee が配布しているサンプルファイル（取引インポート）のヘッダに合わせている。
# freee側で仕様が変わることがあるので、取り込む前にヘルプページのサンプルと見比べてほしい:
#   https://support.freee.co.jp/hc/ja/articles/202847320
#
# 必須項目は 収支区分・発生日・勘定科目・税区分・金額。
# 決済口座を入れると「決済済み」、空にすると「未決済」の取引として登録される。
class FreeeCsvExporter
  HEADERS = [
    "収支区分", "管理番号", "発生日", "決済期日", "取引先コード", "取引先", "勘定科目", "税区分",
    "金額", "税計算区分", "税額", "備考", "品目", "部門", "メモタグ（複数指定可、カンマ区切り）",
    "セグメント1", "セグメント2", "セグメント3", "決済日", "決済口座", "決済金額"
  ].freeze

  # freee の税区分名。支出は「課対仕入」、収入は「課税売上」を使う。
  # 免税事業者でも freee では通常この税区分のまま記帳する（消費税の申告をしないだけ）。
  TAX_CATEGORIES = {
    "支出" => { 10 => "課対仕入10%", 8 => "課対仕入8%（軽）", 0 => "対象外" },
    "収入" => { 10 => "課税売上10%", 8 => "課税売上8%（軽）", 0 => "対象外" }
  }.freeze

  # default_payment_account: 領収書ごとに決済口座が空のとき使う口座名（例: 現金、プライベート資金）。
  #   freee に登録済みの口座名と一字一句同じにする必要がある。nil なら未決済で取り込む。
  # encoding: freee のサンプルは Excel 用で Shift_JIS。UTF-8 も選べるようにしておく。
  def initialize(receipts, default_payment_account: nil, encoding: "Shift_JIS")
    @receipts = receipts
    @default_payment_account = default_payment_account.presence
    @encoding = encoding
  end

  def to_csv
    text = CSV.generate(row_sep: "\r\n") do |csv|
      csv << HEADERS
      rows.each { |row| csv << row }
    end
    return text if @encoding == "UTF-8"

    # Windows の Shift_JIS（CP932）にない文字は「?」に置き換える（髙・﨑 などは CP932 にあるので残る）
    text.encode("Windows-31J", invalid: :replace, undef: :replace, replace: "?")
  end

  def rows
    @receipts.flat_map do |receipt|
      account = receipt.payment_account.presence || @default_payment_account
      date = receipt.transaction_date.strftime("%Y/%m/%d")

      # 税率が混ざった領収書は、税率ごとに別の取引として出す（1行=1取引で、取り込みが一番確実なため）
      parts = receipt.amounts_by_tax_rate
      parts.each_with_index.map do |(rate, yen), index|
        [
          receipt.entry_side,                        # 収支区分
          management_number(receipt, index, parts.size), # 管理番号（このアプリでの番号。あとで照合しやすい）
          date,                                      # 発生日
          nil,                                       # 決済期日
          nil,                                       # 取引先コード
          receipt.vendor,                            # 取引先（freee にない名前は自動で作られる）
          receipt.account_item,                      # 勘定科目
          TAX_CATEGORIES.fetch(receipt.entry_side).fetch(rate), # 税区分
          yen,                                       # 金額（税込）
          "内税",                                    # 税計算区分
          nil,                                       # 税額（空なら freee が自動計算）
          memo(receipt),                             # 備考
          nil, nil, nil, nil, nil, nil,              # 品目・部門・メモタグ・セグメント1〜3
          account ? date : nil,                      # 決済日
          account,                                   # 決済口座
          account ? yen : nil                        # 決済金額
        ]
      end
    end
  end

  private

  # 例: R12。税率で2行に分けたときは R12-1, R12-2
  def management_number(receipt, index, count)
    count > 1 ? "R#{receipt.id}-#{index + 1}" : "R#{receipt.id}"
  end

  def memo(receipt)
    [ receipt.description, (receipt.invoice_number.present? ? "登録番号#{receipt.invoice_number}" : nil) ].compact_blank.join(" ")
  end
end
