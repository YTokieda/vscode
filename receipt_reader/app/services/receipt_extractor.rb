require "base64"
require "json"

# 領収書の画像・PDFを Claude API に送り、日付・金額・取引先などを JSON で受け取るクラス。
#
# 仕組み:
#   1. ファイルを Base64 文字列にして、画像なら "image"、PDFなら "document" として送る
#   2. output_config.format に JSON Schema を渡す（構造化出力）。
#      Claude の返答がこのスキーマどおりの JSON になることが保証されるので、
#      「返事の文章から数字を探す」ような不安定な処理がいらない
#   3. 受け取った JSON を Receipt の各項目に入れる
class ReceiptExtractor
  class Error < StandardError; end

  MODEL = ENV.fetch("CLAUDE_MODEL", "claude-opus-5-5")
  # 考える深さ。領収書の読み取りは難しすぎないので medium を既定にする（low / medium / high）
  EFFORT = ENV.fetch("CLAUDE_EFFORT", "medium")

  SYSTEM_PROMPT = <<~PROMPT.freeze
    あなたは日本の個人事業主の記帳を手伝うアシスタントです。
    渡された領収書・レシート・請求書の画像またはPDFを読み、確定申告の帳簿づけに必要な項目を取り出してください。

    - 日付は西暦の YYYY-MM-DD にしてください。令和などの和暦は西暦に直します（令和元年=2019年）。
    - 金額は税込の支払総額（円・整数）です。お預かり・お釣り・ポイント利用前の金額と取り違えないでください。
    - レシートに軽減税率（8%、「※」「軽」などの印）の対象があれば、その税込金額を reduced_rate_amount に入れます。なければ 0。
    - 8%以外の部分が消費税の対象外（切手・印紙・行政手数料・保険料など）なら main_tax_rate を 0、通常は 10 にします。
    - 取引先は店名・会社名です。支店名は分かれば含めます。
    - 適格請求書発行事業者の登録番号（T＋13桁）が書かれていれば invoice_number に入れます。
    - 勘定科目は候補の中から最も適切なものを選び、理由を reason に1〜2文で書きます。
      飲食代のように用途しだいで科目が変わるもの（会議費か接待交際費か、私用か）は、そのことも reason に書きます。
    - 読み取れない・判断に自信がない項目は推測で埋めず null にし、warnings に理由を書きます。
    - 領収書や請求書ではなさそうな画像なら is_receipt を false にします。
  PROMPT

  SCHEMA = {
    type: "object",
    properties: {
      is_receipt: { type: "boolean", description: "領収書・レシート・請求書として読めるか" },
      transaction_date: { anyOf: [ { type: "string", format: "date" }, { type: "null" } ], description: "取引日 YYYY-MM-DD" },
      vendor: { anyOf: [ { type: "string" }, { type: "null" } ], description: "取引先（店名・会社名）" },
      total_amount: { anyOf: [ { type: "integer" }, { type: "null" } ], description: "税込の支払総額（円）" },
      reduced_rate_amount: { type: "integer", description: "うち軽減税率8%対象の税込金額。なければ0" },
      main_tax_rate: { type: "integer", enum: Receipt::MAIN_TAX_RATES, description: "8%以外の部分の税率。10 または 0（対象外）" },
      entry_side: { type: "string", enum: Receipt::ENTRY_SIDES, description: "支払ったものなら支出、受け取ったお金なら収入" },
      description: { type: "string", description: "何を買ったか・何の代金か（短く）" },
      invoice_number: { anyOf: [ { type: "string" }, { type: "null" } ], description: "T＋13桁の登録番号" },
      suggested_account: { type: "string", enum: Receipt::ACCOUNT_ITEMS },
      reason: { type: "string", description: "その勘定科目を選んだ理由と、注意点" },
      warnings: { type: "array", items: { type: "string" }, description: "読み取りに自信がない点" }
    },
    required: %w[is_receipt transaction_date vendor total_amount reduced_rate_amount main_tax_rate
                 entry_side description invoice_number suggested_account reason warnings],
    additionalProperties: false
  }.freeze

  def initialize(client: nil)
    @client = client
  end

  # receipt の添付ファイルを読み取り、結果を receipt に保存する。
  def call(receipt)
    data = extract(receipt.file.download, receipt.file.content_type)
    apply(receipt, data)
    receipt.update!(status: "extracted", error_message: nil)
    receipt
  rescue Error, Anthropic::Errors::Error => e
    receipt.update_columns(status: "failed", error_message: friendly_message(e), updated_at: Time.current)
    receipt
  end

  # ファイルの中身（バイト列）と種類から、読み取った結果の Hash を返す。
  def extract(bytes, content_type)
    response = client.beta.messages.create(
      model: MODEL,
      max_tokens: 16_000,
      system_: SYSTEM_PROMPT,
      messages: [ { role: "user", content: [ file_block(bytes, content_type), { type: "text", text: "この書類を読み取ってください。" } ] } ],
      output_config: { effort: EFFORT.to_sym, format: { type: :json_schema, schema: SCHEMA } },
      # 安全上の理由で断られたとき、サーバー側で別のモデルに自動でやり直してもらう設定
      fallbacks: :default,
      betas: [ "server-side-fallback-2026-07-01" ]
    )

    case response.stop_reason
    when :refusal then raise Error, "AIがこの書類の読み取りを断りました"
    when :max_tokens then raise Error, "AIの返答が途中で切れました。もう一度お試しください"
    end

    text = response.content.find { |block| block.type == :text }&.text
    raise Error, "AIから読み取り結果が返ってきませんでした" if text.blank?

    JSON.parse(text)
  rescue JSON::ParserError
    raise Error, "AIの返答をJSONとして読めませんでした"
  end

  private

  def client
    @client ||= begin
      raise Error, "APIキーが設定されていません（環境変数 ANTHROPIC_API_KEY を設定してください）" if ENV["ANTHROPIC_API_KEY"].blank?

      Anthropic::Client.new # APIキーは環境変数 ANTHROPIC_API_KEY から読む
    end
  end

  def file_block(bytes, content_type)
    data = Base64.strict_encode64(bytes)
    if content_type == Receipt::PDF_TYPE
      { type: "document", source: { type: "base64", media_type: content_type, data: data } }
    else
      { type: "image", source: { type: "base64", media_type: content_type, data: data } }
    end
  end

  def apply(receipt, data)
    warnings = Array(data["warnings"])
    warnings.unshift("領収書・請求書ではない可能性があります") if data["is_receipt"] == false

    receipt.assign_attributes(
      transaction_date: parse_date(data["transaction_date"], warnings),
      vendor: data["vendor"],
      amount: data["total_amount"],
      reduced_rate_amount: data["reduced_rate_amount"].to_i,
      main_tax_rate: data["main_tax_rate"],
      entry_side: data["entry_side"],
      description: data["description"],
      invoice_number: data["invoice_number"],
      account_item: data["suggested_account"],
      ai_reason: data["reason"]
    )
    # AIが合計より大きい8%対象額を返したときは、保存できるように0に戻して注意を残す
    if receipt.amount && receipt.reduced_rate_amount > receipt.amount
      receipt.reduced_rate_amount = 0
      warnings << "軽減税率の金額が合計を超えていたため0にしました。確認してください"
    end
    receipt.ai_warnings = warnings.join("\n")
  end

  def parse_date(value, warnings)
    return nil if value.blank?

    Date.iso8601(value)
  rescue Date::Error
    warnings << "日付「#{value}」を読めませんでした"
    nil
  end

  def friendly_message(error)
    case error
    when Anthropic::Errors::AuthenticationError then "APIキーが正しくありません（ANTHROPIC_API_KEY を確認してください）"
    when Anthropic::Errors::RateLimitError then "APIの利用回数の上限に達しました。少し待ってから再読み取りしてください"
    when Anthropic::Errors::APIConnectionError then "Claude APIに接続できませんでした。ネットワークを確認してください"
    when Anthropic::Errors::APIStatusError then "Claude APIのエラー（#{error.status}）: #{error.message}"
    else error.message
    end
  end
end
